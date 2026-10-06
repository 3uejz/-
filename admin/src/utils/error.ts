import { ApiError } from '../api/client';

/** 从任意异常中提取可展示的中文错误信息。 */
export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.requestId) {
      return `${error.message}（请求编号：${error.requestId}）`;
    }
    return error.message;
  }
  if (error instanceof Error) return error.message;
  return '请求失败，请稍后重试';
}

/** 提取 request_id，便于排查。 */
export function errorRequestId(error: unknown): string | undefined {
  return error instanceof ApiError ? error.requestId : undefined;
}

/** 提取稳定错误码。 */
export function errorCode(error: unknown): string | undefined {
  return error instanceof ApiError ? error.code : undefined;
}
