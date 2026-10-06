import { message } from 'antd';
import { useSessionStore } from '../store/session';
import type { ApiErrorBody, QueryParams } from './types';

/** API 基址：与 openapi.yaml 的 servers.url 对应。 */
export const API_BASE = '/api/v1';

/** 统一的接口错误，携带后端稳定错误码与 request_id。 */
export class ApiError extends Error {
  status: number;
  code: string;
  details?: Record<string, unknown>;
  requestId?: string;

  constructor(status: number, body?: ApiErrorBody) {
    super(body?.message || `请求失败（HTTP ${status}）`);
    this.name = 'ApiError';
    this.status = status;
    this.code = body?.code || `HTTP_${status}`;
    this.details = body?.details;
    this.requestId = body?.request_id;
  }
}

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  query?: QueryParams;
  headers?: Record<string, string>;
  /** 跳过 access token 注入（登录、刷新等公开接口）。 */
  skipAuth?: boolean;
  /** 直接返回原始 Response（用于下载导出）。 */
  raw?: boolean;
}

function buildQuery(query?: QueryParams): string {
  if (!query) return '';
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === '') continue;
    params.append(key, String(value));
  }
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

async function buildError(res: Response): Promise<ApiError> {
  let body: ApiErrorBody | undefined;
  try {
    body = (await res.json()) as ApiErrorBody;
  } catch {
    body = undefined;
  }
  return new ApiError(res.status, body);
}

function goToLogin(): void {
  const loginPath = '/admin/login';
  if (window.location.pathname !== loginPath) {
    window.location.assign(loginPath);
  }
}

/** 单飞刷新：并发 401 时只发起一次 refresh。 */
let refreshPromise: Promise<boolean> | null = null;

async function doRefresh(): Promise<boolean> {
  const { refreshToken, setTokens, clear } = useSessionStore.getState();
  if (!refreshToken) return false;
  try {
    const res = await fetch(`${API_BASE}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
    if (!res.ok) {
      clear();
      return false;
    }
    const data = (await res.json()) as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
      account_id?: string;
    };
    setTokens(data.access_token, data.refresh_token, data.expires_in, data.account_id);
    return true;
  } catch {
    clear();
    return false;
  }
}

async function ensureRefresh(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = doRefresh().finally(() => {
      refreshPromise = null;
    });
  }
  return refreshPromise;
}

/** 统一请求封装：基址 /api/v1，自动 Bearer，401 轮换重试，403 登出。 */
export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const attempt = async (): Promise<Response> => {
    const headers: Record<string, string> = { ...options.headers };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    if (!options.skipAuth) {
      const token = useSessionStore.getState().accessToken;
      if (token) headers['Authorization'] = `Bearer ${token}`;
    }
    return fetch(`${API_BASE}${path}${buildQuery(options.query)}`, {
      method: options.method ?? 'GET',
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    });
  };

  let res = await attempt();

  // 401：用 refresh 轮换后重试一次；失败则登出并跳登录页。
  if (res.status === 401 && !options.skipAuth) {
    const refreshed = await ensureRefresh();
    if (refreshed) {
      res = await attempt();
    } else {
      useSessionStore.getState().clear();
      goToLogin();
      throw await buildError(res);
    }
  }

  // 403：无后台权限，提示并登出。
  if (res.status === 403) {
    const err = await buildError(res);
    useSessionStore.getState().clear();
    message.error(err.message || '无后台权限');
    goToLogin();
    throw err;
  }

  if (!res.ok) {
    throw await buildError(res);
  }

  if (options.raw) {
    return res as unknown as T;
  }
  if (res.status === 204) {
    return undefined as T;
  }
  const text = await res.text();
  if (!text) return undefined as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    return text as unknown as T;
  }
}
