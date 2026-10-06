import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { getConfig, listConfigVersions, putConfig, rollbackConfig } from '../api/config';
import { errorMessage } from '../utils/error';

export function useConfig() {
  return useQuery({
    queryKey: ['admin', 'config'],
    queryFn: getConfig,
  });
}

export function useConfigVersions() {
  return useQuery({
    queryKey: ['admin', 'config-versions'],
    queryFn: listConfigVersions,
  });
}

export function usePutConfig() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: { revision: number; values: Record<string, unknown> }) => putConfig(payload),
    onSuccess: () => {
      message.success('配置已发布');
      queryClient.invalidateQueries({ queryKey: ['admin', 'config'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'config-versions'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

export function useRollbackConfig() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (version: number) => rollbackConfig(version),
    onSuccess: () => {
      message.success('配置已回滚');
      queryClient.invalidateQueries({ queryKey: ['admin', 'config'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'config-versions'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
