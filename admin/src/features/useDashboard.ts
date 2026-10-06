import { useQuery } from '@tanstack/react-query';
import { getDashboardSummary } from '../api/dashboard';

export function useDashboardSummary() {
  return useQuery({
    queryKey: ['admin', 'dashboard'],
    queryFn: getDashboardSummary,
    refetchInterval: 60 * 1000,
  });
}
