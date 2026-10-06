import { apiFetch } from './client';
import type { ListResponse } from './types';

/** 遥测明细事件。 */
export interface TelemetryEvent {
  event_id?: string;
  event_type?: string;
  occurred_at?: string;
  account_id?: string;
  schema_version?: number;
  payload?: unknown;
}

export interface Aggregates {
  total?: number;
  by_type?: Record<string, number>;
  by_day?: Record<string, number>;
}

export interface LifeStats {
  total?: number;
  by_type?: Record<string, number>;
}

export function listEvents(query: { limit?: number; event_type?: string } = {}) {
  return apiFetch<ListResponse<TelemetryEvent>>('/admin/telemetry/events', { query: { ...query } });
}

export function getAggregates() {
  return apiFetch<Aggregates>('/admin/telemetry/aggregates');
}

export function getLifeStats() {
  return apiFetch<LifeStats>('/admin/telemetry/life-stats');
}

/** 导出遥测：返回原始 Response，供页面触发下载。 */
export function exportTelemetry(query: { format?: 'json' | 'csv'; account_id?: string } = {}) {
  return apiFetch<Response>('/admin/telemetry/export', {
    method: 'POST',
    query: { ...query },
    raw: true,
  });
}

export function purgeTelemetry(body: { account_id?: string; before?: string }) {
  return apiFetch<{ removed?: number }>('/admin/telemetry/purge', { method: 'POST', body });
}
