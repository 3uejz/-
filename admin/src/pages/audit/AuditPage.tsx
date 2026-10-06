import { useState } from 'react';
import { Button, Card, Form, Input, Select, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { DownloadOutlined, ReloadOutlined, SearchOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import { useAuditLogs } from '../../features/useAudit';
import type { AuditEntry, AuditQuery } from '../../api/audit';
import { formatDateTime, shortHash } from '../../utils/format';
import { downloadJSON, timestampedName } from '../../utils/download';

/** 审计日志：只读列表，支持导出。 */
export function AuditPage() {
  const [filters, setFilters] = useState<AuditQuery>({ limit: 50 });
  const { data, isLoading, isFetching, error, refetch } = useAuditLogs(filters);
  const [form] = Form.useForm<Omit<AuditQuery, 'limit'>>();

  const columns: ColumnsType<AuditEntry> = [
    { title: '时间', dataIndex: 'created_at', render: (value?: string) => formatDateTime(value) },
    { title: '动作', dataIndex: 'action', render: (value?: string) => <Tag color="blue">{value || '-'}</Tag> },
    {
      title: '操作者',
      dataIndex: 'actor_account_id',
      render: (value?: string) => <Typography.Text copyable>{shortHash(value, 8, 4)}</Typography.Text>,
    },
    { title: '目标类型', dataIndex: 'target_type', render: (value?: string) => value || '-' },
    { title: '目标 ID', dataIndex: 'target_id', render: (value?: string) => <Typography.Text copyable>{value || '-'}</Typography.Text> },
    {
      title: '结果',
      dataIndex: 'result',
      render: (value?: string) => <Tag color={value === 'error' ? 'red' : 'green'}>{value === 'error' ? '失败' : '成功'}</Tag>,
    },
    { title: '来源 IP', dataIndex: 'ip', render: (value?: string) => value || '-' },
  ];

  const items = data?.items ?? [];

  return (
    <>
      <PageHeader
        title="审计日志"
        description="只读，仅追加；所有写操作自动记录。"
        extra={
          <Space>
            <Button
              icon={<DownloadOutlined />}
              disabled={items.length === 0}
              onClick={() => downloadJSON(items, timestampedName('audit-logs', 'json'))}
            >
              导出当前结果
            </Button>
            <Button icon={<ReloadOutlined />} onClick={() => void refetch()} loading={isFetching}>
              刷新
            </Button>
          </Space>
        }
      />

      <Card size="small" style={{ marginBottom: 16 }}>
        <Form
          form={form}
          layout="inline"
          onFinish={(values) => setFilters({ ...values, limit: filters.limit })}
        >
          <Form.Item name="action" label="动作">
            <Input allowClear placeholder="如 account.disable" prefix={<SearchOutlined />} />
          </Form.Item>
          <Form.Item name="actor" label="操作者">
            <Input allowClear placeholder="账号 ID" />
          </Form.Item>
          <Form.Item name="target" label="目标">
            <Input allowClear placeholder="目标 ID" />
          </Form.Item>
          <Form.Item name="limit" label="数量" initialValue={100}>
            <Select
              style={{ width: 110 }}
              onChange={(value) => setFilters((prev) => ({ ...prev, limit: value }))}
              options={[
                { value: 50, label: '50' },
                { value: 100, label: '100' },
                { value: 200, label: '200' },
                { value: 500, label: '500' },
              ]}
            />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit">
              查询
            </Button>
          </Form.Item>
        </Form>
      </Card>

      {error ? <QueryError error={error} /> : null}

      <Card size="small">
        <Table<AuditEntry>
          rowKey={(record) => record.id ?? `${record.action}-${record.created_at}`}
          columns={columns}
          dataSource={items}
          loading={isLoading || isFetching}
          pagination={{ pageSize: 20 }}
          scroll={{ x: 1000 }}
          expandable={{
            expandedRowRender: (record) => (
              <Space direction="vertical" style={{ width: '100%' }}>
                <JsonBlock value={record.before ?? {}} title="变更前" />
                <JsonBlock value={record.after ?? {}} title="变更后" />
                <Typography.Text type="secondary">UA：{record.user_agent || '-'}</Typography.Text>
              </Space>
            ),
          }}
        />
      </Card>
    </>
  );
}
