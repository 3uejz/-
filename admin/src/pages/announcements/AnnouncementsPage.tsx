import { useState } from 'react';
import {
  Button,
  Card,
  DatePicker,
  Form,
  Input,
  Modal,
  Popconfirm,
  Select,
  Space,
  Table,
  Tag,
  Typography,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { PlusOutlined } from '@ant-design/icons';
import dayjs, { type Dayjs } from 'dayjs';
import { PageHeader } from '../../components/PageHeader';
import { QueryError } from '../../components/JsonBlock';
import {
  useAnnouncements,
  useCreateAnnouncement,
  useDeleteAnnouncement,
  useUpdateAnnouncement,
} from '../../features/useAnnouncements';
import type { Announcement } from '../../api/announcements';
import { formatDateTime } from '../../utils/format';

const STATUS_META: Record<string, { color: string; label: string }> = {
  draft: { color: 'default', label: '草稿' },
  scheduled: { color: 'processing', label: '已排期' },
  published: { color: 'success', label: '已发布' },
  offline: { color: 'error', label: '已下线' },
};

interface AnnouncementForm {
  title: string;
  body?: string;
  audience?: 'all' | 'accounts';
  account_list?: string;
  status?: Announcement['status'];
  range?: [Dayjs | null, Dayjs | null];
}

/** 公告：列表、新建、编辑、删除。 */
export function AnnouncementsPage() {
  const { data, isLoading, error } = useAnnouncements();
  const createAnnouncement = useCreateAnnouncement();
  const updateAnnouncement = useUpdateAnnouncement();
  const deleteAnnouncement = useDeleteAnnouncement();

  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Announcement | null>(null);
  const [form] = Form.useForm<AnnouncementForm>();

  const openCreate = () => {
    setEditing(null);
    form.resetFields();
    form.setFieldsValue({ audience: 'all', status: 'draft' });
    setOpen(true);
  };

  const openEdit = (record: Announcement) => {
    setEditing(record);
    form.setFieldsValue({
      title: record.title,
      body: record.body,
      audience: record.audience ?? 'all',
      status: record.status ?? 'draft',
      account_list: record.account_list?.join('\n'),
      range:
        record.start_at || record.end_at
          ? [record.start_at ? dayjs(record.start_at) : null, record.end_at ? dayjs(record.end_at) : null]
          : undefined,
    });
    setOpen(true);
  };

  const submit = async () => {
    const values = await form.validateFields();
    const body: Announcement = {
      title: values.title,
      body: values.body,
      audience: values.audience,
      status: values.status,
      account_list: values.account_list
        ? values.account_list
            .split(/[\s,]+/)
            .map((item) => item.trim())
            .filter(Boolean)
        : undefined,
      start_at: values.range?.[0] ? values.range[0].toISOString() : null,
      end_at: values.range?.[1] ? values.range[1].toISOString() : null,
    };
    if (editing?.id) {
      await updateAnnouncement.mutateAsync({ id: editing.id, body });
    } else {
      await createAnnouncement.mutateAsync(body);
    }
    setOpen(false);
  };

  const columns: ColumnsType<Announcement> = [
    { title: '标题', dataIndex: 'title', render: (value: string) => <Typography.Text strong>{value}</Typography.Text> },
    {
      title: '目标人群',
      dataIndex: 'audience',
      render: (value?: string, record?: Announcement) => (
        <Tag>{value === 'accounts' ? `指定账号（${record?.account_list?.length ?? 0}）` : '全部'}</Tag>
      ),
    },
    {
      title: '状态',
      dataIndex: 'status',
      render: (value?: string) => {
        const meta = STATUS_META[value || 'draft'] ?? { color: 'default', label: value || '-' };
        return <Tag color={meta.color}>{meta.label}</Tag>;
      },
    },
    { title: '开始', dataIndex: 'start_at', render: (value?: string) => formatDateTime(value) },
    { title: '结束', dataIndex: 'end_at', render: (value?: string) => formatDateTime(value) },
    { title: '更新时间', dataIndex: 'updated_at', render: (value?: string) => formatDateTime(value) },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Space>
          <Button type="link" size="small" onClick={() => openEdit(record)}>
            编辑
          </Button>
          <Popconfirm
            title="确认删除该公告？"
            okText="删除"
            cancelText="取消"
            onConfirm={() => record.id && deleteAnnouncement.mutate(record.id)}
          >
            <Button type="link" size="small" danger>
              删除
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="公告"
        description="支持 Markdown 正文、目标人群与起止时间。"
        extra={
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            新建公告
          </Button>
        }
      />

      {error ? <QueryError error={error} /> : null}

      <Card size="small">
        <Table<Announcement>
          rowKey={(record) => record.id ?? record.title}
          columns={columns}
          dataSource={data?.items ?? []}
          loading={isLoading}
          pagination={false}
          scroll={{ x: 1000 }}
        />
      </Card>

      <Modal
        open={open}
        title={editing ? '编辑公告' : '新建公告'}
        okText="保存"
        cancelText="取消"
        confirmLoading={createAnnouncement.isPending || updateAnnouncement.isPending}
        onCancel={() => setOpen(false)}
        onOk={() => void submit()}
        width={640}
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Form.Item name="title" label="标题" rules={[{ required: true, message: '请输入标题' }]}>
            <Input placeholder="公告标题" />
          </Form.Item>
          <Form.Item name="body" label="正文（Markdown）">
            <Input.TextArea rows={6} placeholder="支持 Markdown 语法" />
          </Form.Item>
          <Space size="large" style={{ display: 'flex' }}>
            <Form.Item name="audience" label="目标人群">
              <Select
                style={{ width: 160 }}
                options={[
                  { value: 'all', label: '全部玩家' },
                  { value: 'accounts', label: '指定账号' },
                ]}
              />
            </Form.Item>
            <Form.Item name="status" label="状态">
              <Select
                style={{ width: 160 }}
                options={[
                  { value: 'draft', label: '草稿' },
                  { value: 'scheduled', label: '已排期' },
                  { value: 'published', label: '已发布' },
                  { value: 'offline', label: '已下线' },
                ]}
              />
            </Form.Item>
          </Space>
          <Form.Item name="account_list" label="指定账号（每行或逗号分隔）">
            <Input.TextArea rows={2} placeholder="账号 ID 列表" />
          </Form.Item>
          <Form.Item name="range" label="起止时间">
            <DatePicker.RangePicker showTime style={{ width: '100%' }} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}
