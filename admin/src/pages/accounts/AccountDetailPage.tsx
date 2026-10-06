import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button, Card, Descriptions, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { ArrowLeftOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { DangerConfirm } from '../../components/DangerConfirm';
import { QueryError } from '../../components/JsonBlock';
import { useAccount, useDevices, useRevokeDevice, useToggleAccount } from '../../features/useAccounts';
import type { DeviceInfo } from '../../api/accounts';
import { formatDateTime } from '../../utils/format';

/** 账号详情：基本信息、设备列表、封禁/解封、吊销设备。 */
export function AccountDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const accountQuery = useAccount(id);
  const devicesQuery = useDevices(id);
  const revokeDevice = useRevokeDevice(id);
  const toggleAccount = useToggleAccount();
  const [pendingDevice, setPendingDevice] = useState<DeviceInfo | null>(null);

  const account = accountQuery.data?.account;

  const columns: ColumnsType<DeviceInfo> = [
    {
      title: '设备 ID',
      dataIndex: 'device_id',
      render: (value: string) => <Typography.Text copyable>{value}</Typography.Text>,
    },
    { title: '创建时间', dataIndex: 'created_at', render: (value: string) => formatDateTime(value) },
    { title: '过期时间', dataIndex: 'expires_at', render: (value: string) => formatDateTime(value) },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Button type="link" danger size="small" onClick={() => setPendingDevice(record)}>
          吊销
        </Button>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="账号详情"
        description={account ? `账号：${account.username}` : '加载中...'}
        extra={
          <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/accounts')}>
            返回列表
          </Button>
        }
      />

      {accountQuery.error ? <QueryError error={accountQuery.error} /> : null}

      <Card size="small" title="基本信息" style={{ marginBottom: 16 }}>
        <Descriptions column={{ xs: 1, md: 2 }} size="small">
          <Descriptions.Item label="账号 ID">
            <Typography.Text copyable>{account?.id ?? '-'}</Typography.Text>
          </Descriptions.Item>
          <Descriptions.Item label="用户名">{account?.username ?? '-'}</Descriptions.Item>
          <Descriptions.Item label="角色">
            <Tag color={account?.role === 'admin' ? 'blue' : 'default'}>{account?.role ?? '-'}</Tag>
          </Descriptions.Item>
          <Descriptions.Item label="状态">
            <Tag color={account?.disabled ? 'red' : 'green'}>{account?.disabled ? '已封禁' : '正常'}</Tag>
          </Descriptions.Item>
          <Descriptions.Item label="创建时间">{formatDateTime(account?.created_at)}</Descriptions.Item>
          <Descriptions.Item label="存档数">{accountQuery.data?.save_count ?? '-'}</Descriptions.Item>
          <Descriptions.Item label="设备数">{accountQuery.data?.device_count ?? '-'}</Descriptions.Item>
        </Descriptions>
        <Space style={{ marginTop: 12 }}>
          {account?.disabled ? (
            <Button onClick={() => toggleAccount.mutate({ id: id as string, disabled: true })}>
              解封账号
            </Button>
          ) : (
            <Button
              danger
              onClick={() => toggleAccount.mutate({ id: id as string, disabled: false })}
            >
              封禁账号
            </Button>
          )}
          <Link to="/accounts">返回列表</Link>
        </Space>
      </Card>

      <Card size="small" title="设备列表">
        {devicesQuery.error ? <QueryError error={devicesQuery.error} /> : null}
        <Table<DeviceInfo>
          rowKey="device_id"
          columns={columns}
          dataSource={devicesQuery.data?.items ?? []}
          loading={devicesQuery.isLoading}
          pagination={false}
        />
      </Card>

      <DangerConfirm
        open={Boolean(pendingDevice)}
        title="吊销设备"
        description={`吊销设备 ${pendingDevice?.device_id ?? ''} 的 refresh，该设备需重新登录。`}
        confirmText={pendingDevice?.device_id ?? ''}
        confirmLabel="确认吊销"
        loading={revokeDevice.isPending}
        onCancel={() => setPendingDevice(null)}
        onConfirm={() => {
          if (pendingDevice) {
            revokeDevice.mutate(pendingDevice.device_id, { onSettled: () => setPendingDevice(null) });
          }
        }}
      />
    </>
  );
}
