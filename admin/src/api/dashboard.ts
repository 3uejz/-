import { apiFetch } from './client';

/** 仪表盘汇总：字段可能随后端演进，全部按可选处理。 */
export interface DashboardSummary {
  accounts?: { total?: number; disabled?: number };
  saves?: { slots?: number; versions?: number; bytes?: number };
  world?: Record<string, unknown>;
  telemetry?: { total?: number; last_7d?: number; last_30d?: number };
  backups?: {
    count?: number;
    latest?: { name?: string; size?: number; created_at?: string } | null;
  };
  health?: { status?: string; postgres?: string; redis?: string; storage?: string };
}

export function getDashboardSummary() {
  return apiFetch<DashboardSummary>('/admin/dashboard/summary');
}
