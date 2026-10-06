import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import {
  getSave,
  getSaveVersions,
  getStorageUsage,
  listSaves,
  rollbackSave,
  storageGC,
} from '../api/saves';
import { errorMessage } from '../utils/error';

export function useSaves(limit = 50) {
  return useQuery({
    queryKey: ['admin', 'saves', limit],
    queryFn: () => listSaves(limit),
  });
}

export function useSave(id: string | undefined) {
  return useQuery({
    queryKey: ['admin', 'save', id],
    queryFn: () => getSave(id as string),
    enabled: Boolean(id),
  });
}

export function useSaveVersions(id: string | undefined) {
  return useQuery({
    queryKey: ['admin', 'save-versions', id],
    queryFn: () => getSaveVersions(id as string),
    enabled: Boolean(id),
  });
}

export function useStorageUsage() {
  return useQuery({
    queryKey: ['admin', 'storage-usage'],
    queryFn: getStorageUsage,
  });
}

/** 回滚存档到指定版本。 */
export function useRollbackSave(id: string | undefined) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (version: number) => rollbackSave(id as string, version),
    onSuccess: () => {
      message.success('存档已回滚');
      queryClient.invalidateQueries({ queryKey: ['admin', 'save', id] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'save-versions', id] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'saves'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

/** 触发孤儿对象清理。 */
export function useStorageGC() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: storageGC,
    onSuccess: (data) => {
      message.success(data.message || '清理任务已受理');
      queryClient.invalidateQueries({ queryKey: ['admin', 'storage-usage'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
