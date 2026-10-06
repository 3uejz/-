import type { ReactNode } from 'react';
import { Card, Skeleton, Statistic } from 'antd';

interface StatCardProps {
  title: string;
  value?: number | string;
  suffix?: string;
  prefix?: ReactNode;
  loading?: boolean;
}

/** 概览指标卡。 */
export function StatCard({ title, value, suffix, prefix, loading }: StatCardProps) {
  return (
    <Card size="small">
      {loading ? (
        <Skeleton active paragraph={{ rows: 1 }} title={false} />
      ) : (
        <Statistic title={title} value={value ?? '-'} suffix={suffix} prefix={prefix} />
      )}
    </Card>
  );
}
