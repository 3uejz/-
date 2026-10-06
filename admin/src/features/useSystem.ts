import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { getMigrations, getSystemStatus, listBackups, triggerBackup } from '../api/system';
import { errorMessage } from '../utils/error';

export function useSystemStatus() {
  return useQuery({
    queryKey: ['admin', 'system-status'],
    queryFn: getSystemStatus,
    refetchInterval: 60 * 1000,
  });
}

export function useBackups() {
  return useQuery({
    queryKey: ['admin', 'system-backups'],
    queryFn: listBackups,
  });
}

export function useMigrations() {
  return useQuery({
    queryKey: ['admin', 'system-migrations'],
    queryFn: getMigrations,
  });
}

/** 手动触发备份。 */
export function useTriggerBackup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: triggerBackup,
    onSuccess: () => {
      message.success('备份任务已触发');
      queryClient.invalidateQueries({ queryKey: ['admin', 'system-backups'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
