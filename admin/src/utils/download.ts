/** 文件下载工具（导出遥测、审计等）。 */

export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export function downloadJSON(data: unknown, filename: string): void {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json;charset=utf-8' });
  downloadBlob(blob, filename);
}

export function downloadText(text: string, filename: string, mime = 'text/plain;charset=utf-8'): void {
  downloadBlob(new Blob([text], { type: mime }), filename);
}

/** 从 fetch Response 生成下载；Content-Type 缺失时用回退值。 */
export async function downloadResponse(
  res: Response,
  filename: string,
  fallbackType = 'application/octet-stream',
): Promise<void> {
  const blob = await res.blob();
  const typed = blob.type ? blob : new Blob([blob], { type: fallbackType });
  downloadBlob(typed, filename);
}

/** 生成带时间戳的导出文件名。 */
export function timestampedName(prefix: string, ext: string): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const stamp =
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
    `-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  return `${prefix}-${stamp}.${ext}`;
}
