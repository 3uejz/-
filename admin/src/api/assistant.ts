import { apiFetch } from './client';

/** 运营助手状态。 */
export interface AssistantStatus {
  enabled: boolean;
  ready: boolean;
  message?: string;
}

/** 助手查询/草稿的结果结构较自由，按任意对象处理。 */
export type AssistantResult = Record<string, unknown> | string;

export function getAssistantStatus() {
  return apiFetch<AssistantStatus>('/admin/assistant/status');
}

export function assistantQuery(text: string) {
  return apiFetch<AssistantResult>('/admin/assistant/query', {
    method: 'POST',
    body: { query: text },
  });
}

export function assistantDraft(prompt: string) {
  return apiFetch<AssistantResult>('/admin/assistant/draft', {
    method: 'POST',
    body: { prompt },
  });
}
