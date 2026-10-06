import { theme, type ThemeConfig } from 'antd';

/** 根据明暗模式构造 AntD 主题 token。 */
export function buildTheme(dark: boolean): ThemeConfig {
  return {
    algorithm: dark ? theme.darkAlgorithm : theme.defaultAlgorithm,
    token: {
      colorPrimary: '#1677ff',
      borderRadius: 6,
      fontSize: 14,
    },
    components: {
      Layout: {
        headerBg: dark ? '#141414' : '#ffffff',
        siderBg: dark ? '#141414' : '#ffffff',
        bodyBg: dark ? '#000000' : '#f5f5f5',
      },
    },
  };
}
