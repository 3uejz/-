import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 远程配置版本。 */
export interface ConfigVersion {
  id?: string;
  version: number;
  revision: number;
  values: Record<string, unknown>;
  created_by?: string;
  created_at?: string;
}

export function getConfig() {
  return apiFetch<ConfigVersion>('/admin/config');
}

/** 发布配置（乐观锁：携带 revision）。 */
export function putConfig(payload: { revision: number; values: Record<string, unknown> }) {
  return apiFetch<ConfigVersion>('/admin/config', { method: 'PUT', body: payload });
}

export function listConfigVersions() {
  return apiFetch<ListResponse<ConfigVersion>>('/admin/config/versions');
}

export function rollbackConfig(version: number) {
  return apiFetch<ConfigVersion>('/admin/config/rollback', { method: 'POST', body: { version } });
}
