import { useEffect } from 'react';
import { App as AntdApp, ConfigProvider } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { AppRouter } from './router';
import { buildTheme } from './theme';
import { resolveDark, useThemeStore } from './store/theme';
import { useSystemDark } from './utils/useSystemDark';

/** 应用根组件：解析主题并通过 ConfigProvider 注入 AntD。 */
export default function App() {
  const mode = useThemeStore((s) => s.mode);
  const systemDark = useSystemDark();
  const dark = resolveDark(mode, systemDark);

  useEffect(() => {
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  }, [dark]);

  return (
    <ConfigProvider locale={zhCN} theme={buildTheme(dark)}>
      <AntdApp>
        <AppRouter />
      </AntdApp>
    </ConfigProvider>
  );
}
