import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import {
  createAnnouncement,
  deleteAnnouncement,
  listAnnouncements,
  updateAnnouncement,
  type Announcement,
} from '../api/announcements';
import { errorMessage } from '../utils/error';

export function useAnnouncements() {
  return useQuery({
    queryKey: ['admin', 'announcements'],
    queryFn: listAnnouncements,
  });
}

export function useCreateAnnouncement() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: Announcement) => createAnnouncement(body),
    onSuccess: () => {
      message.success('公告已创建');
      queryClient.invalidateQueries({ queryKey: ['admin', 'announcements'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

export function useUpdateAnnouncement() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: Announcement }) => updateAnnouncement(id, body),
    onSuccess: () => {
      message.success('公告已更新');
      queryClient.invalidateQueries({ queryKey: ['admin', 'announcements'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

export function useDeleteAnnouncement() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => deleteAnnouncement(id),
    onSuccess: () => {
      message.success('公告已删除');
      queryClient.invalidateQueries({ queryKey: ['admin', 'announcements'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
