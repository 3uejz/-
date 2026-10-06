import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Button, Card, Descriptions, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { ArrowLeftOutlined, RollbackOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { DangerConfirm } from '../../components/DangerConfirm';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import { useRollbackSave, useSave, useSaveVersions } from '../../features/useSaves';
import type { SaveVersion } from '../../api/saves';
import { formatBytes, formatDateTime, shortHash } from '../../utils/format';

/** 存档详情：元数据、历史版本、回滚。 */
export function SaveDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const saveQuery = useSave(id);
  const versionsQuery = useSaveVersions(id);
  const rollback = useRollbackSave(id);
  const [rollbackVersion, setRollbackVersion] = useState<number | null>(null);

  const columns: ColumnsType<SaveVersion> = [
    { title: '版本', dataIndex: 'version', render: (value: number) => <Tag>v{value}</Tag> },
    {
      title: '哈希',
      dataIndex: 'hash',
      render: (value?: string) => <Typography.Text code>{shortHash(value)}</Typography.Text>,
    },
    { title: '创建时间', dataIndex: 'created_at', render: (value?: string) => formatDateTime(value) },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Button
          type="link"
          size="small"
          danger
          icon={<RollbackOutlined />}
          onClick={() => setRollbackVersion(record.version)}
        >
          回滚到此版本
        </Button>
      ),
    },
  ];

  const detail = saveQuery.data;

  return (
    <>
      <PageHeader
        title="存档详情"
        description={`存档 ID：${id ?? '-'}`}
        extra={
          <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/saves')}>
            返回列表
          </Button>
        }
      />

      {saveQuery.error ? <QueryError error={saveQuery.error} /> : null}

      <Card size="small" title="元数据" style={{ marginBottom: 16 }}>
        <Descriptions column={{ xs: 1, md: 2 }} size="small">
          <Descriptions.Item label="账号 ID">
            <Typography.Text copyable>{detail?.account_id ?? '-'}</Typography.Text>
          </Descriptions.Item>
          <Descriptions.Item label="槽位">{detail?.slot ?? '-'}</Descriptions.Item>
          <Descriptions.Item label="当前版本">
            {detail?.version !== undefined ? <Tag>v{detail.version}</Tag> : '-'}
          </Descriptions.Item>
          <Descriptions.Item label="大小">{formatBytes(detail?.size)}</Descriptions.Item>
          <Descriptions.Item label="哈希">
            <Typography.Text code>{shortHash(detail?.hash)}</Typography.Text>
          </Descriptions.Item>
          <Descriptions.Item label="建立时间">{formatDateTime(detail?.created_at)}</Descriptions.Item>
          <Descriptions.Item label="Playthrough ID">
            <Typography.Text copyable>{detail?.playthrough_id ?? '-'}</Typography.Text>
          </Descriptions.Item>
        </Descriptions>
      </Card>

      <Card size="small" title="历史版本">
        {versionsQuery.error ? <QueryError error={versionsQuery.error} /> : null}
        <Table<SaveVersion>
          rowKey={(record) => String(record.version)}
          columns={columns}
          dataSource={versionsQuery.data?.items ?? []}
          loading={versionsQuery.isLoading}
          pagination={false}
        />
      </Card>

      <Card size="small" title="原始数据" style={{ marginTop: 16 }}>
        <Space direction="vertical" style={{ width: '100%' }}>
          <JsonBlock value={detail} title="存档详情" />
          <JsonBlock value={versionsQuery.data?.items ?? []} title="历史版本" />
        </Space>
      </Card>

      <DangerConfirm
        open={rollbackVersion !== null}
        title="回滚存档"
        description={`将存档 ${id ?? ''} 回滚到版本 v${rollbackVersion ?? ''}，当前版本将被覆盖。`}
        confirmText={id ?? ''}
        confirmLabel="确认回滚"
        loading={rollback.isPending}
        onCancel={() => setRollbackVersion(null)}
        onConfirm={() => {
          if (rollbackVersion !== null) {
            rollback.mutate(rollbackVersion, { onSettled: () => setRollbackVersion(null) });
          }
        }}
      />
    </>
  );
}
