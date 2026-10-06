import { create } from 'zustand';
import { persist } from 'zustand/middleware';

/** 主题模式：亮色、暗色，或跟随系统。 */
export type ThemeMode = 'light' | 'dark' | 'system';

interface ThemeState {
  mode: ThemeMode;
  setMode: (mode: ThemeMode) => void;
  /** 在亮/暗之间切换；跟随系统时按当前系统外观取反。 */
  toggle: (systemDark: boolean) => void;
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set, get) => ({
      mode: 'system',
      setMode: (mode) => set({ mode }),
      toggle: (systemDark) => {
        const current = get().mode;
        const effectiveDark = current === 'system' ? systemDark : current === 'dark';
        set({ mode: effectiveDark ? 'light' : 'dark' });
      },
    }),
    { name: 'life-admin-theme' },
  ),
);

/** 把 主题模式 + 系统是否为暗色 解析为最终是否暗色。 */
export function resolveDark(mode: ThemeMode, systemDark: boolean): boolean {
  if (mode === 'system') return systemDark;
  return mode === 'dark';
}
