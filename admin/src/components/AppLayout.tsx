import { useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import {
  Avatar,
  Button,
  Dropdown,
  Layout,
  Menu,
  Result,
  Spin,
  Tag,
  Tooltip,
  Typography,
  theme,
} from 'antd';
import {
  AppstoreOutlined,
  BarChartOutlined,
  CloudServerOutlined,
  DashboardOutlined,
  FileSearchOutlined,
  HddOutlined,
  LogoutOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  MoonOutlined,
  NotificationOutlined,
  RobotOutlined,
  SettingOutlined,
  SunOutlined,
  TeamOutlined,
  UserOutlined,
} from '@ant-design/icons';
import { useSessionStore } from '../store/session';
import { resolveDark, useThemeStore } from '../store/theme';
import { useMe, useLogout } from '../features/useSession';
import { useSystemDark } from '../utils/useSystemDark';
import { ForbiddenPage } from '../pages/ForbiddenPage';

const { Header, Sider, Content } = Layout;

const MENU_ITEMS = [
  { key: '/', icon: <DashboardOutlined />, label: '仪表盘' },
  { key: '/accounts', icon: <TeamOutlined />, label: '账号与设备' },
  { key: '/saves', icon: <HddOutlined />, label: '存档运维' },
  { key: '/content', icon: <AppstoreOutlined />, label: '内容管理' },
  { key: '/config', icon: <SettingOutlined />, label: '远程配置' },
  { key: '/announcements', icon: <NotificationOutlined />, label: '公告' },
  { key: '/telemetry', icon: <BarChartOutlined />, label: '遥测与统计' },
  { key: '/audit', icon: <FileSearchOutlined />, label: '审计日志' },
  { key: '/assistant', icon: <RobotOutlined />, label: '运营助手' },
  { key: '/system', icon: <CloudServerOutlined />, label: '系统运维' },
];

function selectedKey(pathname: string): string {
  if (pathname.startsWith('/accounts')) return '/accounts';
  if (pathname.startsWith('/saves')) return '/saves';
  if (pathname.startsWith('/content')) return '/content';
  if (pathname.startsWith('/config')) return '/config';
  if (pathname.startsWith('/announcements')) return '/announcements';
  if (pathname.startsWith('/telemetry')) return '/telemetry';
  if (pathname.startsWith('/audit')) return '/audit';
  if (pathname.startsWith('/assistant')) return '/assistant';
  if (pathname.startsWith('/system')) return '/system';
  return '/';
}

/** 管理后台主框架：侧边导航 + 顶栏 + 内容区。 */
export function AppLayout() {
  const [collapsed, setCollapsed] = useState(false);
  const token = useSessionStore((s) => s.accessToken);
  const user = useSessionStore((s) => s.user);
  const mode = useThemeStore((s) => s.mode);
  const toggle = useThemeStore((s) => s.toggle);
  const systemDark = useSystemDark();
  const logout = useLogout();
  const navigate = useNavigate();
  const location = useLocation();
  const { token: antdToken } = theme.useToken();

  const meQuery = useMe(Boolean(token));

  const dark = resolveDark(mode, systemDark);

  const handleLogout = async () => {
    await logout();
    navigate('/login', { replace: true });
  };

  if (token && !user) {
    if (meQuery.isError) {
      return (
        <Result
          status="error"
          title="管理员身份校验失败"
          subTitle="请检查网络后重试，或重新登录。"
          extra={
            <Button type="primary" onClick={() => void handleLogout()}>
              返回登录
            </Button>
          }
        />
      );
    }
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>
        <Spin size="large" tip="正在校验管理员身份..." />
      </div>
    );
  }

  if (user && user.role !== 'admin') {
    return <ForbiddenPage />;
  }

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider collapsible collapsed={collapsed} trigger={null} theme={dark ? 'dark' : 'light'}>
        <div
          style={{
            height: 48,
            margin: 12,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontWeight: 600,
            color: antdToken.colorPrimary,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
          }}
        >
          {collapsed ? '浮生' : '浮生录 · 管理后台'}
        </div>
        <Menu
          mode="inline"
          theme={dark ? 'dark' : 'light'}
          selectedKeys={[selectedKey(location.pathname)]}
          items={MENU_ITEMS}
          onClick={({ key }) => navigate(key)}
        />
      </Sider>
      <Layout>
        <Header
          style={{
            padding: '0 16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            borderBottom: `1px solid ${antdToken.colorBorderSecondary}`,
          }}
        >
          <Button
            type="text"
            icon={collapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
            onClick={() => setCollapsed((value) => !value)}
          />
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <Tooltip title={dark ? '切换为亮色' : '切换为暗色'}>
              <Button
                type="text"
                icon={dark ? <SunOutlined /> : <MoonOutlined />}
                onClick={() => toggle(systemDark)}
              />
            </Tooltip>
            <Tag color="blue">{user?.role === 'admin' ? '管理员' : user?.role || '访客'}</Tag>
            <Dropdown
              menu={{
                items: [
                  { key: 'logout', icon: <LogoutOutlined />, label: '退出登录', onClick: () => void handleLogout() },
                ],
              }}
            >
              <Button type="text" icon={<Avatar size="small" icon={<UserOutlined />} />}>
                <Typography.Text>{user?.username || '未登录'}</Typography.Text>
              </Button>
            </Dropdown>
          </div>
        </Header>
        <Content style={{ padding: 16, overflow: 'auto' }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  );
}
