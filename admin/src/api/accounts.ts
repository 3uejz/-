import { apiFetch } from './client';
import type { Account, CursorPage, ListResponse } from './types';

/** 设备信息（脱敏，仅返回标识与时间）。 */
export interface DeviceInfo {
  device_id: string;
  created_at?: string;
  expires_at?: string;
}

/** 账号详情聚合视图。 */
export interface AccountDetail {
  account: Account;
  save_count?: number;
  device_count?: number;
}

export interface ListAccountsQuery {
  limit?: number;
  cursor?: string;
  q?: string;
  status?: 'active' | 'disabled';
}

export function listAccounts(query: ListAccountsQuery = {}) {
  return apiFetch<CursorPage<Account>>('/admin/accounts', { query: { ...query } });
}

export function getAccount(id: string) {
  return apiFetch<AccountDetail>(`/admin/accounts/${encodeURIComponent(id)}`);
}

export function disableAccount(id: string) {
  return apiFetch<Account>(`/admin/accounts/${encodeURIComponent(id)}/disable`, { method: 'POST' });
}

export function enableAccount(id: string) {
  return apiFetch<Account>(`/admin/accounts/${encodeURIComponent(id)}/enable`, { method: 'POST' });
}

export function listDevices(id: string) {
  return apiFetch<ListResponse<DeviceInfo>>(`/admin/accounts/${encodeURIComponent(id)}/devices`);
}

export function revokeDevice(id: string, deviceId: string) {
  return apiFetch<void>(
    `/admin/accounts/${encodeURIComponent(id)}/devices/${encodeURIComponent(deviceId)}/revoke`,
    { method: 'POST' },
  );
}
