import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Button, Card, Col, Row, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { DeleteOutlined, ReloadOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { StatCard } from '../../components/StatCard';
import { DangerConfirm } from '../../components/DangerConfirm';
import { QueryError } from '../../components/JsonBlock';
import { useSaves, useStorageGC, useStorageUsage } from '../../features/useSaves';
import type { SaveSlot } from '../../api/saves';
import { formatBytes, formatDateTime, formatNumber, shortHash } from '../../utils/format';

/** 存档运维：全库存档列表、存储占用与孤儿对象清理。 */
export function SavesPage() {
  const [limit, setLimit] = useState(50);
  const { data, isLoading, isFetching, error, refetch } = useSaves(limit);
  const usageQuery = useStorageUsage();
  const storageGC = useStorageGC();
  const [gcOpen, setGcOpen] = useState(false);

  const columns: ColumnsType<SaveSlot> = [
    {
      title: '存档 ID',
      key: 'id',
      render: (_value, record) => {
        const saveId = `${record.account_id ?? ''}:${record.slot}`;
        return <Link to={`/saves/${saveId}`}>{saveId}</Link>;
      },
    },
    { title: '槽位', dataIndex: 'slot' },
    { title: '版本', dataIndex: 'version', render: (value: number) => <Tag>v{value}</Tag> },
    {
      title: '哈希',
      dataIndex: 'hash',
      render: (value: string) => <Typography.Text code>{shortHash(value)}</Typography.Text>,
    },
    { title: '大小', dataIndex: 'size', render: (value?: number) => formatBytes(value) },
    { title: '更新时间', dataIndex: 'updated_at', render: (value?: string) => formatDateTime(value) },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Link to={`/saves/${record.account_id ?? ''}:${record.slot}`}>详情</Link>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="存档运维"
        description="存档 ID 形如 account_id:slot；后台只读并支持回滚。"
        extra={
          <Button danger icon={<DeleteOutlined />} onClick={() => setGcOpen(true)}>
            清理孤儿对象
          </Button>
        }
      />

      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={24} sm={8}>
          <StatCard
            title="存档槽位"
            value={formatNumber(usageQuery.data?.slots)}
            loading={usageQuery.isLoading}
          />
        </Col>
        <Col xs={24} sm={8}>
          <StatCard
            title="历史版本"
            value={formatNumber(usageQuery.data?.versions)}
            loading={usageQuery.isLoading}
          />
        </Col>
        <Col xs={24} sm={8}>
          <StatCard
            title="存储占用"
            value={formatBytes(usageQuery.data?.bytes)}
            loading={usageQuery.isLoading}
          />
        </Col>
      </Row>

      {error ? <QueryError error={error} /> : null}

      <Card size="small" title="全库存档">
        <Space style={{ marginBottom: 12 }}>
          <Button onClick={() => setLimit(50)} type={limit === 50 ? 'primary' : 'default'}>
            50 条
          </Button>
          <Button onClick={() => setLimit(200)} type={limit === 200 ? 'primary' : 'default'}>
            200 条
          </Button>
          <Button icon={<ReloadOutlined />} onClick={() => void refetch()}>
            刷新
          </Button>
        </Space>
        <Table<SaveSlot>
          rowKey={(record) => `${record.account_id ?? ''}:${record.slot}`}
          columns={columns}
          dataSource={data?.items ?? []}
          loading={isLoading || isFetching}
          pagination={false}
          scroll={{ x: 900 }}
        />
        {data?.id_hint ? (
          <Typography.Text type="secondary">提示：{data.id_hint}</Typography.Text>
        ) : null}
      </Card>

      <DangerConfirm
        open={gcOpen}
        title="清理孤儿对象"
        description="扫描并清理对象存储中无引用的孤立对象，操作不可撤销。"
        confirmText="清理孤儿对象"
        confirmLabel="确认清理"
        loading={storageGC.isPending}
        onCancel={() => setGcOpen(false)}
        onConfirm={() =>
          storageGC.mutate(undefined, { onSettled: () => setGcOpen(false) })
        }
      />
    </>
  );
}
