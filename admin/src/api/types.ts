/** 与后端共用的基础类型，字段以 openapi.yaml / common.schema.json 为准。 */

/** 统一错误体。 */
export interface ApiErrorBody {
  code: string;
  message: string;
  details?: Record<string, unknown>;
  request_id?: string;
}

/** 认证令牌对。 */
export interface AuthTokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  account_id?: string;
}

/** 账号（admin 视图）。 */
export interface Account {
  id: string;
  username: string;
  role: string;
  disabled: boolean;
  created_at: string;
}

/** 游标分页包装。 */
export interface CursorPage<T> {
  items: T[];
  next_cursor?: string | null;
}

/** 列表包装。 */
export interface ListResponse<T> {
  items: T[];
}

/** 允许查询参数中出现的基础类型。 */
export type QueryValue = string | number | boolean | null | undefined;

export type QueryParams = Record<string, QueryValue>;
