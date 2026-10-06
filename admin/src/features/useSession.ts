import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { adminMe, login, logout } from '../api/auth';
import { useSessionStore } from '../store/session';
import type { Account } from '../api/types';

/** 获取当前管理员信息；未登录时禁用。 */
export function useMe(enabled: boolean) {
  const setUser = useSessionStore((s) => s.setUser);
  return useQuery<Account>({
    queryKey: ['admin', 'me'],
    queryFn: async () => {
      const user = await adminMe();
      setUser(user);
      return user;
    },
    enabled,
    retry: false,
    staleTime: 5 * 60 * 1000,
  });
}

export interface LoginVariables {
  username: string;
  password: string;
}

/** 登录并校验管理员身份。 */
export function useLogin() {
  const setTokens = useSessionStore((s) => s.setTokens);
  const setUser = useSessionStore((s) => s.setUser);
  const clear = useSessionStore((s) => s.clear);

  return useMutation<Account, unknown, LoginVariables>({
    mutationFn: async ({ username, password }) => {
      const tokens = await login({ username, password });
      setTokens(tokens.access_token, tokens.refresh_token, tokens.expires_in, tokens.account_id ?? null);
      try {
        const me = await adminMe();
        setUser(me);
        return me;
      } catch (error) {
        clear();
        throw error;
      }
    },
  });
}

/** 登出：撤销当前 refresh 并清空本地会话。 */
export function useLogout() {
  const queryClient = useQueryClient();
  const clear = useSessionStore((s) => s.clear);
  return async () => {
    const refreshToken = useSessionStore.getState().refreshToken;
    try {
      if (refreshToken) await logout(refreshToken);
    } catch {
      // 登出失败不阻塞本地清理
    } finally {
      clear();
      queryClient.clear();
    }
  };
}
