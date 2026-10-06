import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 公告。 */
export interface Announcement {
  id?: string;
  title: string;
  body?: string;
  audience?: 'all' | 'accounts';
  account_list?: string[];
  start_at?: string | null;
  end_at?: string | null;
  status?: 'draft' | 'scheduled' | 'published' | 'offline';
  created_at?: string;
  updated_at?: string;
}

export function listAnnouncements() {
  return apiFetch<ListResponse<Announcement>>('/admin/announcements');
}

export function createAnnouncement(body: Announcement) {
  return apiFetch<Announcement>('/admin/announcements', { method: 'POST', body });
}

export function updateAnnouncement(id: string, body: Announcement) {
  return apiFetch<Announcement>(`/admin/announcements/${encodeURIComponent(id)}`, {
    method: 'PUT',
    body,
  });
}

export function deleteAnnouncement(id: string) {
  return apiFetch<void>(`/admin/announcements/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
