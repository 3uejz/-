import { useState } from 'react';
import {
  Alert,
  Button,
  Card,
  Form,
  Input,
  InputNumber,
  Modal,
  Popconfirm,
  Select,
  Space,
  Table,
  Tabs,
  Tag,
  Typography,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { PlusOutlined, SafetyCertificateOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { DangerConfirm } from '../../components/DangerConfirm';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import {
  useContentPacks,
  useCreateRelease,
  useReleaseAction,
  useReleases,
  useUploadPack,
  useValidatePack,
} from '../../features/useContent';
import type { ContentPack, ContentRelease, ValidateReport } from '../../api/content';
import { errorMessage } from '../../utils/error';
import { formatBytes, formatDateTime, shortHash } from '../../utils/format';

const RELEASE_STATUS: Record<string, { color: string; label: string }> = {
  scheduled: { color: 'default', label: '已排期' },
  rolling: { color: 'processing', label: '放量中' },
  paused: { color: 'warning', label: '已暂停' },
  completed: { color: 'success', label: '已完成' },
  rolled_back: { color: 'error', label: '已回滚' },
};

/** 内容管理：内容包与灰度发布批次。 */
export function ContentPage() {
  const packsQuery = useContentPacks();
  const releasesQuery = useReleases();
  const uploadPack = useUploadPack();
  const validatePack = useValidatePack();
  const createRelease = useCreateRelease();
  const releaseAction = useReleaseAction();

  const [uploadOpen, setUploadOpen] = useState(false);
  const [releaseOpen, setReleaseOpen] = useState(false);
  const [validatingName, setValidatingName] = useState<string | undefined>();
  const [report, setReport] = useState<ValidateReport | null>(null);
  const [rollbackRelease, setRollbackRelease] = useState<ContentRelease | null>(null);

  const [uploadForm] = Form.useForm<ContentPack>();
  const [releaseForm] = Form.useForm();

  const packColumns: ColumnsType<ContentPack> = [
    { title: '名称', dataIndex: 'name' },
    { title: '类型', dataIndex: 'kind', render: (value: string) => <Tag>{value}</Tag> },
    { title: '版本', dataIndex: 'version' },
    {
      title: '哈希',
      dataIndex: 'hash',
      render: (value: string) => <Typography.Text code>{shortHash(value)}</Typography.Text>,
    },
    { title: '大小', dataIndex: 'size', render: (value: number) => formatBytes(value) },
    {
      title: '状态',
      dataIndex: 'status',
      render: (value?: string) => <Tag color="green">{value || 'published'}</Tag>,
    },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Button
          type="link"
          size="small"
          icon={<SafetyCertificateOutlined />}
          loading={validatingName === record.name && validatePack.isPending}
          onClick={async () => {
            setValidatingName(record.name);
            try {
              const result = await validatePack.mutateAsync(record.name);
              setReport(result);
            } catch (err) {
              setReport({ name: record.name, valid: false, issues: [errorMessage(err)] });
            } finally {
              setValidatingName(undefined);
            }
          }}
        >
          校验
        </Button>
      ),
    },
  ];

  const releaseColumns: ColumnsType<ContentRelease> = [
    { title: '内容包', dataIndex: 'pack_name' },
    { title: '版本', dataIndex: 'pack_version' },
    {
      title: '策略',
      dataIndex: 'strategy',
      render: (value?: string) => {
        const labels: Record<string, string> = { all: '全量', percent: '按比例', accounts: '按名单' };
        return <Tag>{labels[value || 'all'] || value || 'all'}</Tag>;
      },
    },
    {
      title: '放量',
      dataIndex: 'rollout_percent',
      render: (value?: number) => (value === undefined ? '-' : `${value}%`),
    },
    {
      title: '状态',
      dataIndex: 'status',
      render: (value?: string) => {
        const meta = RELEASE_STATUS[value || 'scheduled'] ?? { color: 'default', label: value || '-' };
        return <Tag color={meta.color}>{meta.label}</Tag>;
      },
    },
    { title: '更新时间', dataIndex: 'updated_at', render: (value?: string) => formatDateTime(value) },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => {
        const id = record.id ?? '';
        return (
          <Space>
            <Popconfirm
              title="确认暂停该发布批次？"
              onConfirm={() => releaseAction.mutate({ id, action: 'pause' })}
              okText="暂停"
              cancelText="取消"
            >
              <Button type="link" size="small" disabled={!id}>
                暂停
              </Button>
            </Popconfirm>
            <Popconfirm
              title="确认继续该发布批次？"
              onConfirm={() => releaseAction.mutate({ id, action: 'resume' })}
              okText="继续"
              cancelText="取消"
            >
              <Button type="link" size="small" disabled={!id}>
                继续
              </Button>
            </Popconfirm>
            <Button type="link" size="small" danger disabled={!id} onClick={() => setRollbackRelease(record)}>
              回滚
            </Button>
          </Space>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader title="内容管理" description="内容包上传与校验、灰度发布批次管理。" />

      {packsQuery.error ? <QueryError error={packsQuery.error} /> : null}
      {releasesQuery.error ? <QueryError error={releasesQuery.error} /> : null}

      <Tabs
        items={[
          {
            key: 'packs',
            label: '内容包',
            children: (
              <Card
                size="small"
                extra={
                  <Button type="primary" icon={<PlusOutlined />} onClick={() => setUploadOpen(true)}>
                    上传内容包
                  </Button>
                }
              >
                <Table<ContentPack>
                  rowKey="name"
                  columns={packColumns}
                  dataSource={packsQuery.data?.items ?? []}
                  loading={packsQuery.isLoading}
                  pagination={false}
                  scroll={{ x: 900 }}
                />
              </Card>
            ),
          },
          {
            key: 'releases',
            label: '发布批次',
            children: (
              <Card
                size="small"
                extra={
                  <Button type="primary" icon={<PlusOutlined />} onClick={() => setReleaseOpen(true)}>
                    创建发布批次
                  </Button>
                }
              >
                <Table<ContentRelease>
                  rowKey={(record) => record.id ?? `${record.pack_name}:${record.pack_version}`}
                  columns={releaseColumns}
                  dataSource={releasesQuery.data?.items ?? []}
                  loading={releasesQuery.isLoading}
                  pagination={false}
                  scroll={{ x: 1000 }}
                />
              </Card>
            ),
          },
        ]}
      />

      {/* 上传内容包 */}
      <Modal
        open={uploadOpen}
        title="上传内容包"
        okText="上传"
        cancelText="取消"
        confirmLoading={uploadPack.isPending}
        onCancel={() => setUploadOpen(false)}
        onOk={async () => {
          const values = await uploadForm.validateFields();
          await uploadPack.mutateAsync(values);
          uploadForm.resetFields();
          setUploadOpen(false);
        }}
        destroyOnClose
      >
        <Form form={uploadForm} layout="vertical" initialValues={{ kind: 'data' }}>
          <Form.Item name="name" label="名称" rules={[{ required: true, message: '请输入名称' }]}>
            <Input placeholder="如 core.base" />
          </Form.Item>
          <Form.Item name="kind" label="类型" rules={[{ required: true }]}>
            <Select
              options={[
                { value: 'core', label: 'core' },
                { value: 'data', label: 'data' },
                { value: 'art', label: 'art' },
                { value: 'audio', label: 'audio' },
              ]}
            />
          </Form.Item>
          <Form.Item name="version" label="版本" rules={[{ required: true, message: '请输入版本' }]}>
            <Input placeholder="如 1.0.0" />
          </Form.Item>
          <Form.Item
            name="hash"
            label="哈希"
            rules={[{ required: true, message: '请输入 sha256 哈希' }]}
          >
            <Input placeholder="sha256:..." />
          </Form.Item>
          <Form.Item name="size" label="大小（字节）" rules={[{ required: true, message: '请输入大小' }]}>
            <InputNumber min={0} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item name="url" label="下载地址" rules={[{ required: true, message: '请输入地址' }]}>
            <Input placeholder="https://... 或相对路径" />
          </Form.Item>
        </Form>
      </Modal>

      {/* 校验报告 */}
      <Modal
        open={report !== null}
        title={`校验报告：${report?.name ?? ''}`}
        footer={<Button onClick={() => setReport(null)}>关闭</Button>}
        onCancel={() => setReport(null)}
      >
        {report?.valid ? (
          <Alert type="success" showIcon message="校验通过" />
        ) : (
          <Alert
            type="error"
            showIcon
            message="校验未通过"
            description={
              <ul style={{ margin: 0, paddingLeft: 18 }}>
                {(report?.issues ?? ['未知问题']).map((issue) => (
                  <li key={issue}>{issue}</li>
                ))}
              </ul>
            }
          />
        )}
      </Modal>

      {/* 创建发布批次 */}
      <Modal
        open={releaseOpen}
        title="创建灰度发布批次"
        okText="创建"
        cancelText="取消"
        confirmLoading={createRelease.isPending}
        onCancel={() => setReleaseOpen(false)}
        onOk={async () => {
          const values = await releaseForm.validateFields();
          const payload: ContentRelease = {
            pack_name: values.pack_name,
            pack_version: values.pack_version,
            strategy: values.strategy,
            rollout_percent: values.rollout_percent,
            account_list: values.account_list
              ? String(values.account_list)
                  .split(/[\s,]+/)
                  .map((item) => item.trim())
                  .filter(Boolean)
              : undefined,
          };
          await createRelease.mutateAsync(payload);
          releaseForm.resetFields();
          setReleaseOpen(false);
        }}
        destroyOnClose
      >
        <Form form={releaseForm} layout="vertical" initialValues={{ strategy: 'percent', rollout_percent: 10 }}>
          <Form.Item name="pack_name" label="内容包名称" rules={[{ required: true, message: '请输入名称' }]}>
            <Input />
          </Form.Item>
          <Form.Item name="pack_version" label="版本" rules={[{ required: true, message: '请输入版本' }]}>
            <Input />
          </Form.Item>
          <Form.Item name="strategy" label="策略">
            <Select
              options={[
                { value: 'all', label: '全量发布' },
                { value: 'percent', label: '按百分比放量' },
                { value: 'accounts', label: '指定账号名单' },
              ]}
            />
          </Form.Item>
          <Form.Item name="rollout_percent" label="放量百分比">
            <InputNumber min={0} max={100} style={{ width: '100%' }} addonAfter="%" />
          </Form.Item>
          <Form.Item name="account_list" label="账号名单（按账号策略）">
            <Input.TextArea rows={3} placeholder="每行或用逗号分隔的账号 ID" />
          </Form.Item>
        </Form>
      </Modal>

      <DangerConfirm
        open={Boolean(rollbackRelease)}
        title="回滚发布批次"
        description={`将内容包 ${rollbackRelease?.pack_name ?? ''}@${rollbackRelease?.pack_version ?? ''} 的发布批次回滚。`}
        confirmText={rollbackRelease?.id ?? ''}
        confirmLabel="确认回滚"
        loading={releaseAction.isPending}
        onCancel={() => setRollbackRelease(null)}
        onConfirm={() => {
          if (rollbackRelease?.id) {
            releaseAction.mutate(
              { id: rollbackRelease.id, action: 'rollback' },
              { onSettled: () => setRollbackRelease(null) },
            );
          }
        }}
      />

      <Card size="small" title="原始发布批次数据" style={{ marginTop: 16 }}>
        <JsonBlock value={releasesQuery.data?.items ?? []} title="releases" />
      </Card>
    </>
  );
}
