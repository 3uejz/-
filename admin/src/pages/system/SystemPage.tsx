import { Button, Card, Col, Descriptions, Popconfirm, Row, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { CloudUploadOutlined, ReloadOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { StatCard } from '../../components/StatCard';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import { useBackups, useMigrations, useSystemStatus, useTriggerBackup } from '../../features/useSystem';
import type { BackupEntry } from '../../api/system';
import { formatBytes, formatDateTime, formatDuration } from '../../utils/format';

/** 系统运维：服务健康、密钥存在性、备份与迁移。 */
export function SystemPage() {
  const statusQuery = useSystemStatus();
  const backupsQuery = useBackups();
  const migrationsQuery = useMigrations();
  const triggerBackup = useTriggerBackup();

  const backupColumns: ColumnsType<BackupEntry> = [
    { title: '备份文件', dataIndex: 'name' },
    { title: '大小', dataIndex: 'size', render: (value?: number) => formatBytes(value) },
    { title: '创建时间', dataIndex: 'created_at', render: (value?: string) => formatDateTime(value) },
  ];

  const secrets = statusQuery.data?.secrets ?? {};
  const alerts = statusQuery.data?.alerts ?? [];

  return (
    <>
      <PageHeader
        title="系统运维"
        description="服务健康、密钥存在性、备份与数据库迁移。"
        extra={
          <Popconfirm
            title="确认手动触发一次备份？"
            okText="触发"
            cancelText="取消"
            onConfirm={() => triggerBackup.mutate()}
          >
            <Button
              type="primary"
              icon={<CloudUploadOutlined />}
              loading={triggerBackup.isPending}
            >
              手动备份
            </Button>
          </Popconfirm>
        }
      />

      {statusQuery.error ? <QueryError error={statusQuery.error} /> : null}

      {alerts.length > 0 ? (
        <Card size="small" style={{ marginBottom: 16 }}>
          <Typography.Text type="warning">
            缺失密钥：{alerts.join('、')}
          </Typography.Text>
        </Card>
      ) : null}

      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={6}>
          <StatCard title="Go 运行时" value={statusQuery.data?.go || '-'} loading={statusQuery.isLoading} />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="运行时长"
            value={formatDuration(statusQuery.data?.uptime_s)}
            loading={statusQuery.isLoading}
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard title="PostgreSQL" value={statusQuery.data?.postgres || '-'} loading={statusQuery.isLoading} />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard title="Redis" value={statusQuery.data?.redis || '-'} loading={statusQuery.isLoading} />
        </Col>
      </Row>

      <Card size="small" title="关键密钥存在性" style={{ marginTop: 16 }}>
        <Space wrap>
          {Object.entries(secrets).length === 0 ? (
            <Typography.Text type="secondary">暂无数据</Typography.Text>
          ) : (
            Object.entries(secrets).map(([key, present]) => (
              <Tag key={key} color={present ? 'green' : 'red'}>
                {key}：{present ? '已配置' : '缺失'}
              </Tag>
            ))
          )}
        </Space>
      </Card>

      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col xs={24} lg={12}>
          <Card
            size="small"
            title="备份记录"
            extra={
              <Button
                size="small"
                icon={<ReloadOutlined />}
                onClick={() => void backupsQuery.refetch()}
                loading={backupsQuery.isFetching}
              >
                刷新
              </Button>
            }
          >
            {backupsQuery.error ? <QueryError error={backupsQuery.error} /> : null}
            <Table<BackupEntry>
              rowKey="name"
              columns={backupColumns}
              dataSource={backupsQuery.data?.items ?? []}
              loading={backupsQuery.isLoading}
              pagination={false}
              size="small"
            />
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card size="small" title="数据库迁移">
            {migrationsQuery.error ? <QueryError error={migrationsQuery.error} /> : null}
            <Descriptions column={1} size="small">
              <Descriptions.Item label="当前版本">
                <Tag color="blue">{migrationsQuery.data?.current || '-'}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="可用迁移数">
                {migrationsQuery.data?.available?.length ?? 0}
              </Descriptions.Item>
            </Descriptions>
            <JsonBlock value={migrationsQuery.data?.available ?? []} title="迁移列表" />
          </Card>
        </Col>
      </Row>

      <Card size="small" title="系统状态原始数据" style={{ marginTop: 16 }}>
        <JsonBlock value={statusQuery.data} title="system/status" />
      </Card>
    </>
  );
}
