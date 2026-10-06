import { Card, Empty, Progress, Typography } from 'antd';

interface BarListProps {
  title?: string;
  data: Record<string, number> | Array<{ label: string; value: number }>;
  /** 是否显示百分比进度条；否则显示数值条。 */
  showPercent?: boolean;
  emptyText?: string;
}

/** 轻量水平条形图，避免引入重型图表依赖。 */
export function BarList({ title, data, showPercent = true, emptyText = '暂无数据' }: BarListProps) {
  const entries: Array<{ label: string; value: number }> = Array.isArray(data)
    ? data
    : Object.entries(data || {}).map(([label, value]) => ({ label, value: Number(value) || 0 }));

  const sorted = [...entries].sort((a, b) => b.value - a.value);
  const max = sorted.reduce((acc, item) => Math.max(acc, item.value), 0);
  const total = sorted.reduce((acc, item) => acc + item.value, 0);

  return (
    <Card size="small" title={title}>
      {sorted.length === 0 ? (
        <Empty description={emptyText} image={Empty.PRESENTED_IMAGE_SIMPLE} />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {sorted.slice(0, 12).map((item) => {
            const percent = showPercent
              ? total > 0
                ? Math.round((item.value / total) * 100)
                : 0
              : max > 0
                ? Math.round((item.value / max) * 100)
                : 0;
            return (
              <div key={item.label}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                  <Typography.Text ellipsis style={{ maxWidth: '70%' }}>
                    {item.label}
                  </Typography.Text>
                  <Typography.Text type="secondary">{item.value}</Typography.Text>
                </div>
                <Progress percent={percent} showInfo={false} size="small" />
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
}
