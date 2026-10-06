import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 审计日志（只读）。 */
export interface AuditEntry {
  id?: string;
  actor_account_id?: string;
  action?: string;
  target_type?: string;
  target_id?: string;
  before?: Record<string, unknown> | null;
  after?: Record<string, unknown> | null;
  result?: 'ok' | 'error';
  ip?: string;
  user_agent?: string;
  created_at?: string;
}

export interface AuditQuery {
  limit?: number;
  action?: string;
  actor?: string;
  target?: string;
}

export function listAuditLogs(query: AuditQuery = {}) {
  return apiFetch<ListResponse<AuditEntry>>('/admin/audit-logs', { query: { ...query } });
}
