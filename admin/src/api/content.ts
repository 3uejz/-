import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 内容包。 */
export interface ContentPack {
  name: string;
  kind: string;
  version: string;
  hash: string;
  size: number;
  url: string;
  status?: string;
}

/** 灰度发布批次。 */
export interface ContentRelease {
  id?: string;
  pack_name: string;
  pack_version: string;
  strategy?: 'all' | 'percent' | 'accounts';
  rollout_percent?: number;
  account_list?: string[];
  status?: 'scheduled' | 'rolling' | 'paused' | 'completed' | 'rolled_back';
  manifest_version?: number;
  created_at?: string;
  updated_at?: string;
}

/** 内容包校验报告。 */
export interface ValidateReport {
  name?: string;
  valid?: boolean;
  issues?: string[];
}

export function listPacks() {
  return apiFetch<ListResponse<ContentPack>>('/admin/content/packs');
}

export function uploadPack(pack: ContentPack) {
  return apiFetch<ContentPack>('/admin/content/packs', { method: 'POST', body: pack });
}

export function validatePack(name: string) {
  return apiFetch<ValidateReport>(`/admin/content/packs/${encodeURIComponent(name)}/validate`, {
    method: 'POST',
  });
}

/** 兼容旧端点的整体清单发布。 */
export function publishManifest(manifest: Record<string, unknown>) {
  return apiFetch<void>('/admin/content/publish', { method: 'POST', body: manifest });
}

export function listReleases() {
  return apiFetch<ListResponse<ContentRelease>>('/admin/content/releases');
}

export function createRelease(release: ContentRelease) {
  return apiFetch<ContentRelease>('/admin/content/releases', { method: 'POST', body: release });
}

export type ReleaseAction = 'pause' | 'resume' | 'rollback';

export function releaseAction(id: string, action: ReleaseAction) {
  return apiFetch<ContentRelease>(
    `/admin/content/releases/${encodeURIComponent(id)}/${action}`,
    { method: 'POST' },
  );
}
