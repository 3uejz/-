import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import {
  disableAccount,
  enableAccount,
  getAccount,
  listAccounts,
  listDevices,
  revokeDevice,
  type ListAccountsQuery,
} from '../api/accounts';
import { errorMessage } from '../utils/error';

export function useAccounts(query: ListAccountsQuery) {
  return useQuery({
    queryKey: ['admin', 'accounts', query],
    queryFn: () => listAccounts(query),
  });
}

export function useAccount(id: string | undefined) {
  return useQuery({
    queryKey: ['admin', 'account', id],
    queryFn: () => getAccount(id as string),
    enabled: Boolean(id),
  });
}

export function useDevices(id: string | undefined) {
  return useQuery({
    queryKey: ['admin', 'devices', id],
    queryFn: () => listDevices(id as string),
    enabled: Boolean(id),
  });
}

/** 封禁/解封账号。 */
export function useToggleAccount() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, disabled }: { id: string; disabled: boolean }) =>
      disabled ? enableAccount(id) : disableAccount(id),
    onSuccess: (_data, vars) => {
      message.success(vars.disabled ? '账号已解封' : '账号已封禁');
      queryClient.invalidateQueries({ queryKey: ['admin', 'accounts'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'account'] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}

/** 吊销指定设备的 refresh。 */
export function useRevokeDevice(accountId: string | undefined) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (deviceId: string) => revokeDevice(accountId as string, deviceId),
    onSuccess: () => {
      message.success('设备已吊销');
      queryClient.invalidateQueries({ queryKey: ['admin', 'devices', accountId] });
    },
    onError: (error) => message.error(errorMessage(error)),
  });
}
