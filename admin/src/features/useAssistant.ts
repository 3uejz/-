import { useMutation, useQuery } from '@tanstack/react-query';
import { assistantDraft, assistantQuery, getAssistantStatus } from '../api/assistant';

export function useAssistantStatus() {
  return useQuery({
    queryKey: ['admin', 'assistant-status'],
    queryFn: getAssistantStatus,
    retry: false,
  });
}

export function useAssistantQuery() {
  return useMutation({
    mutationFn: (text: string) => assistantQuery(text),
  });
}

export function useAssistantDraft() {
  return useMutation({
    mutationFn: (prompt: string) => assistantDraft(prompt),
  });
}
