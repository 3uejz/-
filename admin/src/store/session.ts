import { create } from 'zustand';
import { persist } from 'zustand/middleware';

/** 当前登录管理员的账号信息。 */
export interface AdminUser {
  id: string;
  username: string;
  role: string;
  disabled: boolean;
  created_at: string;
}

/** 会话状态：令牌持久化到 localStorage，刷新页面后仍保持登录。 */
interface SessionState {
  accessToken: string | null;
  refreshToken: string | null;
  /** access 有效期（秒）。 */
  expiresIn: number | null;
  accountId: string | null;
  user: AdminUser | null;
  setTokens: (accessToken: string, refreshToken: string, expiresIn?: number, accountId?: string | null) => void;
  setUser: (user: AdminUser | null) => void;
  /** 清空会话（登出或令牌失效）。 */
  clear: () => void;
}

export const useSessionStore = create<SessionState>()(
  persist(
    (set) => ({
      accessToken: null,
      refreshToken: null,
      expiresIn: null,
      accountId: null,
      user: null,
      setTokens: (accessToken, refreshToken, expiresIn, accountId) =>
        set((state) => ({
          accessToken,
          refreshToken,
          expiresIn: expiresIn ?? state.expiresIn,
          accountId: accountId ?? state.accountId,
        })),
      setUser: (user) => set({ user }),
      clear: () => set({ accessToken: null, refreshToken: null, expiresIn: null, accountId: null, user: null }),
    }),
    {
      name: 'life-admin-session',
      partialize: (state) => ({
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
        expiresIn: state.expiresIn,
        accountId: state.accountId,
        user: state.user,
      }),
    },
  ),
);
