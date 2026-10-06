import { Button, Card, Col, Descriptions, Row, Space, Tag } from 'antd';
import {
  CloudDownloadOutlined,
  DatabaseOutlined,
  LineChartOutlined,
  TeamOutlined,
  UserDeleteOutlined,
} from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { StatCard } from '../../components/StatCard';
import { BarList } from '../../components/BarList';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import { useDashboardSummary } from '../../features/useDashboard';
import { formatBytes, formatDateTime, formatNumber } from '../../utils/format';

/** 仪表盘：概览卡片 + 全球宏观摘要 + 遥测趋势。 */
export function DashboardPage() {
  const { data, isLoading, error, refetch, isFetching } = useDashboardSummary();

  if (error) {
    return (
      <>
        <PageHeader title="仪表盘" />
        <QueryError error={error} />
      </>
    );
  }

  const totalAccounts = data?.accounts?.total;
  const disabledAccounts = data?.accounts?.disabled;
  const slots = data?.saves?.slots;
  const bytes = data?.saves?.bytes;
  const telemetryTotal = data?.telemetry?.total;
  const latestBackup = data?.backups?.latest;

  const world = (data?.world ?? {}) as Record<string, unknown>;
  const worldNumber = (key: string): number | undefined => {
    const value = world[key];
    return typeof value === 'number' ? value : undefined;
  };

  return (
    <>
      <PageHeader
        title="仪表盘"
        description="概览指标、全球宏观摘要与服务健康。"
        extra={
          <Button onClick={() => void refetch()} loading={isFetching}>
            刷新
          </Button>
        }
      />
      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="账号总数"
            value={formatNumber(totalAccounts)}
            prefix={<TeamOutlined />}
            loading={isLoading}
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="已封禁账号"
            value={formatNumber(disabledAccounts)}
            prefix={<UserDeleteOutlined />}
            loading={isLoading}
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="存档槽位"
            value={formatNumber(slots)}
            suffix={bytes !== undefined ? formatBytes(bytes) : undefined}
            prefix={<DatabaseOutlined />}
            loading={isLoading}
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="遥测事件总数"
            value={formatNumber(telemetryTotal)}
            prefix={<LineChartOutlined />}
            loading={isLoading}
          />
        </Col>
      </Row>

      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col xs={24} lg={12}>
          <Card size="small" title="遥测事件量">
            <Space size="large" wrap>
              <StatCard title="近 7 日" value={formatNumber(data?.telemetry?.last_7d)} loading={isLoading} />
              <StatCard title="近 30 日" value={formatNumber(data?.telemetry?.last_30d)} loading={isLoading} />
              <StatCard title="备份份数" value={formatNumber(data?.backups?.count)} loading={isLoading} />
            </Space>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card size="small" title="服务健康">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="状态">
                <Tag color={data?.health?.status === 'ok' ? 'green' : 'orange'}>
                  {data?.health?.status || '未知'}
                </Tag>
              </Descriptions.Item>
              <Descriptions.Item label="最近备份">
                {latestBackup ? (
                  <Space direction="vertical" size={0}>
                    <span>{latestBackup.name}</span>
                    <span>
                      {formatBytes(latestBackup.size)} · {formatDateTime(latestBackup.created_at)}
                    </span>
                  </Space>
                ) : (
                  '-'
                )}
              </Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
      </Row>

      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col xs={24} lg={12}>
          <Card size="small" title="全球宏观摘要">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="人口">
                {formatNumber(worldNumber('population'))}
              </Descriptions.Item>
              <Descriptions.Item label="GDP 估计">
                {worldNumber('gdp_est') ?? '-'}
              </Descriptions.Item>
              <Descriptions.Item label="通胀率">
                {worldNumber('inflation_rate') ?? '-'}
              </Descriptions.Item>
              <Descriptions.Item label="失业率">
                {worldNumber('unemployment_rate') ?? '-'}
              </Descriptions.Item>
              <Descriptions.Item label="世界时间（绝对分钟）">
                {formatNumber(worldNumber('absolute_minutes'))}
              </Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <BarList
            title="遥测占比"
            showPercent
            data={[
              { label: '近 7 日', value: data?.telemetry?.last_7d ?? 0 },
              { label: '近 8-30 日', value: Math.max((data?.telemetry?.last_30d ?? 0) - (data?.telemetry?.last_7d ?? 0), 0) },
              { label: '30 日以外', value: Math.max((telemetryTotal ?? 0) - (data?.telemetry?.last_30d ?? 0), 0) },
            ]}
          />
        </Col>
      </Row>

      <Card size="small" title="原始汇总数据" style={{ marginTop: 16 }}>
        <JsonBlock value={data} title="dashboard/summary" />
      </Card>

      <Card size="small" style={{ marginTop: 16 }}>
        <Space>
          <CloudDownloadOutlined />
          <span>数据每 60 秒自动刷新；可随时点击右上角“刷新”手动获取最新汇总。</span>
        </Space>
      </Card>
    </>
  );
}
