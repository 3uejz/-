import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 存档槽位快照（admin 全库）。 */
export interface SaveSlot {
  account_id?: string;
  slot: number;
  version: number;
  hash?: string;
  playthrough_id?: string;
  updated_at?: string;
  size?: number;
  created_at?: string;
}

export interface SaveDetail {
  account_id?: string;
  slot?: number;
  version?: number;
  hash?: string;
  playthrough_id?: string;
  size?: number;
  created_at?: string;
}

export interface SaveVersion {
  version: number;
  hash?: string;
  created_at?: string;
}

export interface StorageUsage {
  slots?: number;
  versions?: number;
  bytes?: number;
}

export interface StorageGCResult {
  scanned?: number;
  removed?: number;
  message?: string;
}

/** 列表响应额外带 id_hint，提示 id 形如 account_id:slot。 */
export interface SaveListResponse extends ListResponse<SaveSlot> {
  id_hint?: string;
}

export function listSaves(limit = 50) {
  return apiFetch<SaveListResponse>('/admin/saves', { query: { limit } });
}

export function getSave(id: string) {
  return apiFetch<SaveDetail>(`/admin/saves/${encodeURIComponent(id)}`);
}

export function getSaveVersions(id: string) {
  return apiFetch<ListResponse<SaveVersion>>(`/admin/saves/${encodeURIComponent(id)}/versions`);
}

export function rollbackSave(id: string, version: number) {
  return apiFetch<{ version?: number; hash?: string }>(
    `/admin/saves/${encodeURIComponent(id)}/rollback`,
    { method: 'POST', body: { version } },
  );
}

export function getStorageUsage() {
  return apiFetch<StorageUsage>('/admin/storage/usage');
}

export function storageGC() {
  return apiFetch<StorageGCResult>('/admin/storage/gc', { method: 'POST' });
}
