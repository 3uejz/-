import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import {
  createRelease,
  listPacks,
  listReleases,
  releaseAction,
  uploadPack,
  validatePack,
  type ContentPack,
  type ContentRelease,
  type ReleaseAction,
} from '../api/content';
import { errorMessage } from '../utils/error';

export function useContentPacks() {
  return useQuery({
    queryKey: ['admin', 'content-packs'],
    queryFn: listPacks,
  });
}

export function useReleases() {
  return useQuery({
    queryKey: ['admin', 'content-releases'],
    queryFn: listReleases,
  });
}

export function useUploadPack() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (pack: ContentPack) => uploadPack(pack),
    onSuccess: () => {
      message.success('内容包已上传并合入清单');
      queryClient.invalidateQueries({ queryKey: ['admin', 'content-packs'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

export function useValidatePack() {
  return useMutation({
    mutationFn: (name: string) => validatePack(name),
  });
}

export function useCreateRelease() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (release: ContentRelease) => createRelease(release),
    onSuccess: () => {
      message.success('发布批次已创建');
      queryClient.invalidateQueries({ queryKey: ['admin', 'content-releases'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

export function useReleaseAction() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: ReleaseAction }) => releaseAction(id, action),
    onSuccess: (_data, vars) => {
      const labels: Record<ReleaseAction, string> = { pause: '已暂停', resume: '已继续', rollback: '已回滚' };
      message.success(labels[vars.action]);
      queryClient.invalidateQueries({ queryKey: ['admin', 'content-releases'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
