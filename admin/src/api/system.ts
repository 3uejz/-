import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 系统状态。 */
export interface SystemStatus {
  go?: string;
  uptime_s?: number;
  postgres?: string;
  redis?: string;
  storage?: string;
  secrets?: Record<string, boolean>;
  alerts?: string[];
}

export interface BackupEntry {
  name: string;
  size?: number;
  created_at?: string;
}

export interface MigrationInfo {
  available?: string[];
  current?: string;
}

export function getSystemStatus() {
  return apiFetch<SystemStatus>('/admin/system/status');
}

export function listBackups() {
  return apiFetch<ListResponse<BackupEntry>>('/admin/system/backups');
}

export function triggerBackup() {
  return apiFetch<{ path?: string }>('/admin/system/backup', { method: 'POST' });
}

export function getMigrations() {
  return apiFetch<MigrationInfo>('/admin/system/migrations');
}
