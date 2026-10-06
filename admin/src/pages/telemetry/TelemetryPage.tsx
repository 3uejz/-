import { useState } from 'react';
import {
  Button,
  Card,
  Col,
  Form,
  Input,
  Row,
  Select,
  Space,
  Table,
  Tabs,
  Tag,
  Typography,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { DownloadOutlined, DeleteOutlined, ReloadOutlined, SearchOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { StatCard } from '../../components/StatCard';
import { BarList } from '../../components/BarList';
import { DangerConfirm } from '../../components/DangerConfirm';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import {
  useExportTelemetry,
  useLifeStats,
  usePurgeTelemetry,
  useTelemetryAggregates,
  useTelemetryEvents,
} from '../../features/useTelemetry';
import type { TelemetryEvent } from '../../api/telemetry';
import { formatDateTime, formatNumber, safeText } from '../../utils/format';
import { downloadResponse, timestampedName } from '../../utils/download';

/** 遥测与统计：明细、日聚合、人生统计、导出与合规删除。 */
export function TelemetryPage() {
  const [eventType, setEventType] = useState<string | undefined>();
  const [limit, setLimit] = useState(100);
  const eventsQuery = useTelemetryEvents({ limit, event_type: eventType });
  const aggregatesQuery = useTelemetryAggregates();
  const lifeStatsQuery = useLifeStats();
  const exportTelemetry = useExportTelemetry();
  const purgeTelemetry = usePurgeTelemetry();

  const [exportFormat, setExportFormat] = useState<'json' | 'csv'>('json');
  const [exportAccount, setExportAccount] = useState('');
  const [purgeAccount, setPurgeAccount] = useState('');
  const [purgeBefore, setPurgeBefore] = useState('');
  const [purgeOpen, setPurgeOpen] = useState(false);

  const handleExport = async () => {
    const res = await exportTelemetry.mutateAsync({
      format: exportFormat,
      account_id: exportAccount || undefined,
    });
    await downloadResponse(
      res,
      timestampedName('telemetry', exportFormat),
      exportFormat === 'csv' ? 'text/csv;charset=utf-8' : 'application/json;charset=utf-8',
    );
  };

  const eventColumns: ColumnsType<TelemetryEvent> = [
    { title: '事件类型', dataIndex: 'event_type', render: (value?: string) => <Tag color="blue">{value || '-'}</Tag> },
    { title: '发生时间', dataIndex: 'occurred_at', render: (value?: string) => formatDateTime(value) },
    { title: '账号 ID', dataIndex: 'account_id', render: (value?: string) => value || '-' },
    {
      title: '负载',
      dataIndex: 'payload',
      render: (value: unknown) => (
        <Typography.Text code style={{ fontSize: 12 }}>
          {safeText(value).slice(0, 120)}
        </Typography.Text>
      ),
    },
  ];

  return (
    <>
      <PageHeader title="遥测与统计" description="明细保留 90 天，日聚合长期保留；导出与删除均记审计。" />

      {aggregatesQuery.error ? <QueryError error={aggregatesQuery.error} /> : null}

      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={24} sm={8}>
          <StatCard title="聚合事件总数" value={formatNumber(aggregatesQuery.data?.total)} loading={aggregatesQuery.isLoading} />
        </Col>
        <Col xs={24} sm={8}>
          <StatCard title="事件类型数" value={formatNumber(Object.keys(aggregatesQuery.data?.by_type ?? {}).length)} loading={aggregatesQuery.isLoading} />
        </Col>
        <Col xs={24} sm={8}>
          <StatCard title="统计天数" value={formatNumber(Object.keys(aggregatesQuery.data?.by_day ?? {}).length)} loading={aggregatesQuery.isLoading} />
        </Col>
      </Row>

      <Tabs
        items={[
          {
            key: 'events',
            label: '事件明细',
            children: (
              <Card size="small">
                <Form layout="inline" style={{ marginBottom: 12 }}>
                  <Form.Item label="事件类型">
                    <Input
                      allowClear
                      placeholder="如 life.death"
                      prefix={<SearchOutlined />}
                      value={eventType}
                      onChange={(event) => setEventType(event.target.value || undefined)}
                    />
                  </Form.Item>
                  <Form.Item label="数量">
                    <Select
                      style={{ width: 120 }}
                      value={limit}
                      onChange={setLimit}
                      options={[
                        { value: 100, label: '100' },
                        { value: 500, label: '500' },
                        { value: 1000, label: '1000' },
                      ]}
                    />
                  </Form.Item>
                  <Form.Item>
                    <Button icon={<ReloadOutlined />} onClick={() => void eventsQuery.refetch()}>
                      刷新
                    </Button>
                  </Form.Item>
                </Form>
                {eventsQuery.error ? <QueryError error={eventsQuery.error} /> : null}
                <Table<TelemetryEvent>
                  rowKey={(record) => record.event_id ?? `${record.event_type}-${record.occurred_at}`}
                  columns={eventColumns}
                  dataSource={eventsQuery.data?.items ?? []}
                  loading={eventsQuery.isLoading}
                  pagination={{ pageSize: 20 }}
                  scroll={{ x: 900 }}
                />
              </Card>
            ),
          },
          {
            key: 'aggregates',
            label: '日聚合',
            children: (
              <Row gutter={[16, 16]}>
                <Col xs={24} lg={12}>
                  <BarList title="按事件类型" showPercent data={aggregatesQuery.data?.by_type ?? {}} />
                </Col>
                <Col xs={24} lg={12}>
                  <BarList title="按日期" showPercent data={aggregatesQuery.data?.by_day ?? {}} />
                </Col>
              </Row>
            ),
          },
          {
            key: 'life',
            label: '人生统计',
            children: (
              <Row gutter={[16, 16]}>
                <Col xs={24}>
                  <StatCard title="人生事件总数" value={formatNumber(lifeStatsQuery.data?.total)} loading={lifeStatsQuery.isLoading} />
                </Col>
                <Col xs={24}>
                  <BarList title="人生事件分布" data={lifeStatsQuery.data?.by_type ?? {}} />
                </Col>
              </Row>
            ),
          },
          {
            key: 'ops',
            label: '导出与删除',
            children: (
              <Row gutter={[16, 16]}>
                <Col xs={24} lg={12}>
                  <Card size="small" title="导出遥测">
                    <Space direction="vertical" style={{ width: '100%' }}>
                      <Select
                        value={exportFormat}
                        onChange={setExportFormat}
                        style={{ width: 160 }}
                        options={[
                          { value: 'json', label: 'JSON' },
                          { value: 'csv', label: 'CSV' },
                        ]}
                      />
                      <Input
                        placeholder="按账号 ID 导出（留空为全部）"
                        value={exportAccount}
                        onChange={(event) => setExportAccount(event.target.value)}
                      />
                      <Button
                        type="primary"
                        icon={<DownloadOutlined />}
                        loading={exportTelemetry.isPending}
                        onClick={() => void handleExport()}
                      >
                        导出
                      </Button>
                      <Typography.Text type="secondary">单次导出上限 10 万行 / 50MB。</Typography.Text>
                    </Space>
                  </Card>
                </Col>
                <Col xs={24} lg={12}>
                  <Card size="small" title="合规删除">
                    <Space direction="vertical" style={{ width: '100%' }}>
                      <Input
                        placeholder="账号 ID（按账号删除）"
                        value={purgeAccount}
                        onChange={(event) => setPurgeAccount(event.target.value)}
                      />
                      <Input
                        placeholder="删除早于该时间（RFC3339，可留空按保留期）"
                        value={purgeBefore}
                        onChange={(event) => setPurgeBefore(event.target.value)}
                      />
                      <Button danger icon={<DeleteOutlined />} onClick={() => setPurgeOpen(true)}>
                        执行删除
                      </Button>
                    </Space>
                  </Card>
                </Col>
              </Row>
            ),
          },
        ]}
      />

      <Card size="small" title="原始聚合数据" style={{ marginTop: 16 }}>
        <JsonBlock value={aggregatesQuery.data} title="aggregates" />
      </Card>

      <DangerConfirm
        open={purgeOpen}
        title="合规删除遥测"
        description="按账号或时间删除遥测明细，操作不可撤销并会记录审计。"
        confirmText={purgeAccount || '确认删除'}
        confirmLabel="确认删除"
        loading={purgeTelemetry.isPending}
        onCancel={() => setPurgeOpen(false)}
        onConfirm={() =>
          purgeTelemetry.mutate(
            { account_id: purgeAccount || undefined, before: purgeBefore || undefined },
            { onSettled: () => setPurgeOpen(false) },
          )
        }
      />
    </>
  );
}
