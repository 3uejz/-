import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import {
  exportTelemetry,
  getAggregates,
  getLifeStats,
  listEvents,
  purgeTelemetry,
} from '../api/telemetry';
import { errorMessage } from '../utils/error';

export function useTelemetryEvents(query: { limit?: number; event_type?: string }) {
  return useQuery({
    queryKey: ['admin', 'telemetry-events', query],
    queryFn: () => listEvents(query),
  });
}

export function useTelemetryAggregates() {
  return useQuery({
    queryKey: ['admin', 'telemetry-aggregates'],
    queryFn: getAggregates,
  });
}

export function useLifeStats() {
  return useQuery({
    queryKey: ['admin', 'telemetry-life-stats'],
    queryFn: getLifeStats,
  });
}

/** 导出遥测；返回原始 Response，由页面触发下载。 */
export function useExportTelemetry() {
  return useMutation({
    mutationFn: (query: { format?: 'json' | 'csv'; account_id?: string }) => exportTelemetry(query),
    onError: (error) => message.error(errorMessage(error)),
  });
}

/** 合规删除遥测。 */
export function usePurgeTelemetry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: { account_id?: string; before?: string }) => purgeTelemetry(body),
    onSuccess: (data) => {
      message.success(`已删除 ${data.removed ?? 0} 条遥测记录`);
      queryClient.invalidateQueries({ queryKey: ['admin', 'telemetry-events'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'telemetry-aggregates'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
