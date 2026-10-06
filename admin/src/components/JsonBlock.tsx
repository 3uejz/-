import { Alert, Button, Collapse, Typography, message } from 'antd';
import { CopyOutlined } from '@ant-design/icons';
import type { ReactNode } from 'react';

interface JsonBlockProps {
  value: unknown;
  title?: string;
  defaultOpen?: boolean;
}

function stringify(value: unknown): string {
  try {
    return JSON.stringify(value ?? null, null, 2);
  } catch {
    return String(value);
  }
}

/** JSON 展示块，支持折叠与复制。 */
export function JsonBlock({ value, title = '原始数据', defaultOpen = false }: JsonBlockProps): ReactNode {
  const text = stringify(value);
  return (
    <Collapse
      defaultActiveKey={defaultOpen ? ['1'] : undefined}
      items={[
        {
          key: '1',
          label: `${title}（${text.length} 字符）`,
          extra: (
            <Button
              size="small"
              type="text"
              icon={<CopyOutlined />}
              onClick={(event) => {
                event.stopPropagation();
                void navigator.clipboard?.writeText(text);
                message.success('已复制');
              }}
            >
              复制
            </Button>
          ),
          children: (
            <Typography.Paragraph>
              <pre style={{ maxHeight: 360, overflow: 'auto', margin: 0, whiteSpace: 'pre-wrap' }}>{text}</pre>
            </Typography.Paragraph>
          ),
        },
      ]}
    />
  );
}

/** 查询错误提示。 */
export function QueryError({ error }: { error: unknown }) {
  const text = error instanceof Error ? error.message : '加载失败';
  return <Alert type="error" showIcon message="加载失败" description={text} />;
}
