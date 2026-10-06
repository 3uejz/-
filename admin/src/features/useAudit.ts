import { useQuery } from '@tanstack/react-query';
import { listAuditLogs, type AuditQuery } from '../api/audit';

export function useAuditLogs(query: AuditQuery) {
  return useQuery({
    queryKey: ['admin', 'audit-logs', query],
    queryFn: () => listAuditLogs(query),
  });
}
