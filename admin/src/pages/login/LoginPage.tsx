import { useState } from 'react';
import { Alert, Button, Card, Form, Input, Typography } from 'antd';
import { LockOutlined, UserOutlined } from '@ant-design/icons';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { useLogin } from '../../features/useSession';
import { useSessionStore } from '../../store/session';
import { errorMessage } from '../../utils/error';

interface LoginForm {
  username: string;
  password: string;
}

/** 登录页：复用账号体系，登录后校验管理员身份。 */
export function LoginPage() {
  const token = useSessionStore((s) => s.accessToken);
  const login = useLogin();
  const navigate = useNavigate();
  const location = useLocation();
  const [error, setError] = useState<string | undefined>();

  if (token) {
    return <Navigate to="/" replace />;
  }

  const from = (location.state as { from?: string } | null)?.from || '/';

  const onFinish = async (values: LoginForm) => {
    setError(undefined);
    try {
      await login.mutateAsync(values);
      navigate(from, { replace: true });
    } catch (err) {
      setError(errorMessage(err));
    }
  };

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
      }}
    >
      <Card style={{ width: 380 }}>
        <div style={{ textAlign: 'center', marginBottom: 24 }}>
          <Typography.Title level={3} style={{ marginBottom: 4 }}>
            浮生录 管理后台
          </Typography.Title>
          <Typography.Text type="secondary">仅管理员可访问</Typography.Text>
        </div>
        {error ? <Alert type="error" showIcon message={error} style={{ marginBottom: 16 }} /> : null}
        <Form<LoginForm> layout="vertical" onFinish={onFinish} autoComplete="off">
          <Form.Item name="username" label="账号" rules={[{ required: true, message: '请输入账号' }]}>
            <Input prefix={<UserOutlined />} placeholder="账号" autoFocus />
          </Form.Item>
          <Form.Item name="password" label="密码" rules={[{ required: true, message: '请输入密码' }]}>
            <Input.Password prefix={<LockOutlined />} placeholder="密码" />
          </Form.Item>
          <Form.Item style={{ marginBottom: 0 }}>
            <Button type="primary" htmlType="submit" block loading={login.isPending}>
              登录
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}
