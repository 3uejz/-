import { apiFetch } from './client';
import type { Account, AuthTokens } from './types';

/** 登录：复用账号体系，成功后返回令牌对。 */
export function login(body: { username: string; password: string }) {
  return apiFetch<AuthTokens>('/auth/login', { method: 'POST', body, skipAuth: true });
}

/** 刷新令牌（轮换 refresh）。 */
export function refresh(refreshToken: string) {
  return apiFetch<AuthTokens>('/auth/refresh', {
    method: 'POST',
    body: { refresh_token: refreshToken },
    skipAuth: true,
  });
}

/** 登出并撤销当前 refresh。 */
export function logout(refreshToken: string) {
  return apiFetch<void>('/auth/logout', { method: 'POST', body: { refresh_token: refreshToken } });
}

/** 当前管理员信息（用于校验 is_admin）。 */
export function adminMe() {
  return apiFetch<Account>('/admin/me');
}
