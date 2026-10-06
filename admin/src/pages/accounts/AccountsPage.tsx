import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Button,
  Card,
  Form,
  Input,
  Popconfirm,
  Select,
  Space,
  Table,
  Tag,
  Typography,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { ReloadOutlined, SearchOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { DangerConfirm } from '../../components/DangerConfirm';
import { QueryError } from '../../components/JsonBlock';
import { useAccounts, useToggleAccount } from '../../features/useAccounts';
import type { Account } from '../../api/types';
import { formatDateTime } from '../../utils/format';

interface SearchForm {
  q?: string;
  status?: 'active' | 'disabled';
}

/** 账号与设备：列表、搜索、分页、封禁/解封。 */
export function AccountsPage() {
  const [form] = Form.useForm<SearchForm>();
  const [filters, setFilters] = useState<SearchForm>({});
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [cursorStack, setCursorStack] = useState<Array<string | undefined>>([]);
  const [pendingDisable, setPendingDisable] = useState<Account | null>(null);

  const limit = 20;
  const query = useMemo(
    () => ({ limit, cursor, q: filters.q, status: filters.status }),
    [cursor, filters],
  );
  const { data, isLoading, isFetching, error, refetch } = useAccounts(query);
  const toggleAccount = useToggleAccount();

  const goNext = () => {
    if (!data?.next_cursor) return;
    setCursorStack((stack) => [...stack, cursor]);
    setCursor(data.next_cursor ?? undefined);
  };

  const goPrev = () => {
    setCursorStack((stack) => {
      if (stack.length === 0) return stack;
      const next = [...stack];
      const prev = next.pop();
      setCursor(prev);
      return next;
    });
  };

  const columns: ColumnsType<Account> = [
    {
      title: '账号',
      dataIndex: 'username',
      render: (_value, record) => <Link to={`/accounts/${record.id}`}>{record.username}</Link>,
    },
    {
      title: '账号 ID',
      dataIndex: 'id',
      render: (value: string) => <Typography.Text copyable>{value}</Typography.Text>,
    },
    {
      title: '角色',
      dataIndex: 'role',
      render: (value: string) => <Tag color={value === 'admin' ? 'blue' : 'default'}>{value || 'player'}</Tag>,
    },
    {
      title: '状态',
      dataIndex: 'disabled',
      render: (value: boolean) => (
        <Tag color={value ? 'red' : 'green'}>{value ? '已封禁' : '正常'}</Tag>
      ),
    },
    {
      title: '创建时间',
      dataIndex: 'created_at',
      render: (value: string) => formatDateTime(value),
    },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Space>
          <Link to={`/accounts/${record.id}`}>详情</Link>
          {record.disabled ? (
            <Popconfirm
              title="确认解封该账号？"
              okText="解封"
              cancelText="取消"
              onConfirm={() => toggleAccount.mutate({ id: record.id, disabled: true })}
            >
              <Button type="link" size="small">
                解封
              </Button>
            </Popconfirm>
          ) : (
            <Button type="link" size="small" danger onClick={() => setPendingDisable(record)}>
              封禁
            </Button>
          )}
        </Space>
      ),
    },
  ];

  return (
    <>
      <PageHeader title="账号与设备" description="查询账号、查看设备并执行封禁/解封。" />
      <Card size="small" style={{ marginBottom: 16 }}>
        <Form
          form={form}
          layout="inline"
          onFinish={(values) => {
            setFilters(values);
            setCursor(undefined);
            setCursorStack([]);
          }}
        >
          <Form.Item name="q" label="账号搜索">
            <Input allowClear placeholder="按用户名模糊搜索" prefix={<SearchOutlined />} />
          </Form.Item>
          <Form.Item name="status" label="状态">
            <Select
              allowClear
              placeholder="全部"
              style={{ width: 120 }}
              options={[
                { value: 'active', label: '正常' },
                { value: 'disabled', label: '已封禁' },
              ]}
            />
          </Form.Item>
          <Form.Item>
            <Space>
              <Button type="primary" htmlType="submit">
                查询
              </Button>
              <Button
                icon={<ReloadOutlined />}
                onClick={() => {
                  form.resetFields();
                  setFilters({});
                  setCursor(undefined);
                  setCursorStack([]);
                }}
              >
                重置
              </Button>
            </Space>
          </Form.Item>
        </Form>
      </Card>

      {error ? <QueryError error={error} /> : null}

      <Card size="small">
        <Table<Account>
          rowKey="id"
          columns={columns}
          dataSource={data?.items ?? []}
          loading={isLoading || isFetching}
          pagination={false}
          scroll={{ x: 900 }}
        />
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 16 }}>
          <Button disabled={cursorStack.length === 0} onClick={goPrev}>
            上一页
          </Button>
          <Button disabled={!data?.next_cursor} onClick={goNext}>
            下一页
          </Button>
          <Button icon={<ReloadOutlined />} onClick={() => void refetch()}>
            刷新
          </Button>
        </div>
      </Card>

      <DangerConfirm
        open={Boolean(pendingDisable)}
        title="封禁账号"
        description={`即将封禁账号 ${pendingDisable?.username ?? ''}，该账号将无法登录。`}
        confirmText={pendingDisable?.username ?? ''}
        confirmLabel="确认封禁"
        loading={toggleAccount.isPending}
        onCancel={() => setPendingDisable(null)}
        onConfirm={() => {
          if (pendingDisable) {
            toggleAccount.mutate(
              { id: pendingDisable.id, disabled: false },
              { onSettled: () => setPendingDisable(null) },
            );
          }
        }}
      />
    </>
  );
}
