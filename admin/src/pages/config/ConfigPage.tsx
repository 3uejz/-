import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  Button,
  Card,
  Col,
  Descriptions,
  Empty,
  Input,
  Row,
  Space,
  Table,
  Tabs,
  Tag,
  Typography,
  message,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { SaveOutlined, SyncOutlined, UndoOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { DangerConfirm } from '../../components/DangerConfirm';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import { useConfig, useConfigVersions, usePutConfig, useRollbackConfig } from '../../features/useConfig';
import type { ConfigVersion } from '../../api/config';
import { formatDateTime } from '../../utils/format';

type FlatEntry = { path: string; value: unknown };

/** 把配置对象摊平成点分键 → 值；数组视为叶子值。 */
function flatten(input: Record<string, unknown>, prefix = ''): FlatEntry[] {
  const entries: FlatEntry[] = [];
  for (const [key, value] of Object.entries(input)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
      entries.push(...flatten(value as Record<string, unknown>, path));
    } else {
      entries.push({ path, value });
    }
  }
  return entries;
}

/** 按点分路径写回配置对象（浅拷贝，避免直接改原对象）。 */
function setByPath(source: Record<string, unknown>, path: string, value: unknown): Record<string, unknown> {
  const clone: Record<string, unknown> = JSON.parse(JSON.stringify(source ?? {}));
  const segments = path.split('.');
  let cursor: Record<string, unknown> = clone;
  for (let i = 0; i < segments.length - 1; i += 1) {
    const segment = segments[i];
    if (typeof cursor[segment] !== 'object' || cursor[segment] === null) {
      cursor[segment] = {};
    }
    cursor = cursor[segment] as Record<string, unknown>;
  }
  cursor[segments[segments.length - 1]] = value;
  return clone;
}

function rawToInput(value: unknown): string {
  if (value === null) return 'null';
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

function inputToRaw(text: string): unknown {
  const trimmed = text.trim();
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (trimmed === 'null') return null;
  if (trimmed !== '' && !Number.isNaN(Number(trimmed))) return Number(trimmed);
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return text;
    }
  }
  return text;
}

/** 远程配置：表单视图 / JSON 视图 + 版本历史与回滚。 */
export function ConfigPage() {
  const configQuery = useConfig();
  const versionsQuery = useConfigVersions();
  const putConfig = usePutConfig();
  const rollbackConfig = useRollbackConfig();

  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [jsonText, setJsonText] = useState('{}');
  const [rollbackVersion, setRollbackVersion] = useState<number | null>(null);
  const loadedRef = useRef<string | null>(null);

  useEffect(() => {
    const data = configQuery.data;
    if (!data) return;
    const signature = `${data.version}:${data.revision}`;
    if (loadedRef.current === signature) return;
    loadedRef.current = signature;
    setDraft(data.values ?? {});
    setJsonText(JSON.stringify(data.values ?? {}, null, 2));
  }, [configQuery.data]);

  const entries = useMemo(() => flatten(draft), [draft]);
  const groups = useMemo(() => {
    const map = new Map<string, FlatEntry[]>();
    for (const entry of entries) {
      const top = entry.path.split('.')[0];
      if (!map.has(top)) map.set(top, []);
      map.get(top)!.push(entry);
    }
    return Array.from(map.entries());
  }, [entries]);

  const handleChange = (path: string, text: string) => {
    setDraft((prev) => setByPath(prev, path, inputToRaw(text)));
  };

  const handleSave = async () => {
    let values = draft;
    try {
      values = JSON.parse(jsonText) as Record<string, unknown>;
    } catch {
      message.error('JSON 视图内容不是合法 JSON，请先修复');
      return;
    }
    await putConfig.mutateAsync({ revision: configQuery.data?.revision ?? 0, values });
  };

  const versionColumns: ColumnsType<ConfigVersion> = [
    { title: '版本', dataIndex: 'version', render: (value: number) => <Tag>v{value}</Tag> },
    { title: 'revision', dataIndex: 'revision' },
    { title: '创建人', dataIndex: 'created_by', render: (value?: string) => value || '-' },
    { title: '创建时间', dataIndex: 'created_at', render: (value?: string) => formatDateTime(value) },
    {
      title: '操作',
      key: 'actions',
      render: (_value, record) => (
        <Button
          type="link"
          size="small"
          danger
          icon={<UndoOutlined />}
          onClick={() => setRollbackVersion(record.version)}
        >
          回滚到此版本
        </Button>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="远程配置"
        description="按点分键分组编辑，乐观锁防并发覆盖；每次发布生成新版本。"
        extra={
          <Button type="primary" icon={<SaveOutlined />} loading={putConfig.isPending} onClick={() => void handleSave()}>
            发布配置
          </Button>
        }
      />

      {configQuery.error ? <QueryError error={configQuery.error} /> : null}

      <Card size="small" style={{ marginBottom: 16 }}>
        <Descriptions column={{ xs: 1, md: 3 }} size="small">
          <Descriptions.Item label="当前版本">v{configQuery.data?.version ?? 0}</Descriptions.Item>
          <Descriptions.Item label="revision">{configQuery.data?.revision ?? 0}</Descriptions.Item>
          <Descriptions.Item label="更新时间">
            {formatDateTime(configQuery.data?.created_at)}
          </Descriptions.Item>
        </Descriptions>
      </Card>

      <Tabs
        items={[
          {
            key: 'form',
            label: '表单视图',
            children: (
              <Card size="small">
                {groups.length === 0 ? (
                  <Empty description="暂无配置项" />
                ) : (
                  <Row gutter={[16, 16]}>
                    {groups.map(([group, items]) => (
                      <Col xs={24} lg={12} key={group}>
                        <Card size="small" title={group} type="inner">
                          <Space direction="vertical" style={{ width: '100%' }}>
                            {items.map((item) => (
                              <div key={item.path}>
                                <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                                  {item.path}
                                </Typography.Text>
                                <Input
                                  value={rawToInput(item.value)}
                                  onChange={(event) => handleChange(item.path, event.target.value)}
                                />
                              </div>
                            ))}
                          </Space>
                        </Card>
                      </Col>
                    ))}
                  </Row>
                )}
              </Card>
            ),
          },
          {
            key: 'json',
            label: 'JSON 视图',
            children: (
              <Card size="small">
                <Input.TextArea
                  value={jsonText}
                  onChange={(event) => setJsonText(event.target.value)}
                  autoSize={{ minRows: 14 }}
                  spellCheck={false}
                />
                <Space style={{ marginTop: 12 }}>
                  <Button
                    icon={<SyncOutlined />}
                    onClick={() => setJsonText(JSON.stringify(draft, null, 2))}
                  >
                    用表单内容覆盖 JSON
                  </Button>
                  <Button
                    onClick={() => {
                      try {
                        setDraft(JSON.parse(jsonText) as Record<string, unknown>);
                        message.success('已按 JSON 更新表单内容');
                      } catch {
                        message.error('JSON 解析失败');
                      }
                    }}
                  >
                    解析 JSON 到表单
                  </Button>
                </Space>
              </Card>
            ),
          },
        ]}
      />

      <Card size="small" title="版本历史" style={{ marginTop: 16 }}>
        {versionsQuery.error ? <QueryError error={versionsQuery.error} /> : null}
        <Table<ConfigVersion>
          rowKey={(record) => String(record.version)}
          columns={versionColumns}
          dataSource={versionsQuery.data?.items ?? []}
          loading={versionsQuery.isLoading}
          pagination={false}
          expandable={{
            expandedRowRender: (record) => <JsonBlock value={record.values} title={`v${record.version} 配置`} />,
          }}
        />
      </Card>

      <Alert
        type="info"
        showIcon
        style={{ marginTop: 16 }}
        message="并发保护"
        description="若提示 revision 冲突，请刷新页面获取最新版本后再发布。"
      />

      <DangerConfirm
        open={rollbackVersion !== null}
        title="回滚配置"
        description={`将远程配置回滚到版本 v${rollbackVersion ?? ''}，当前版本会被覆盖。`}
        confirmText={`v${rollbackVersion ?? ''}`}
        confirmLabel="确认回滚"
        loading={rollbackConfig.isPending}
        onCancel={() => setRollbackVersion(null)}
        onConfirm={() => {
          if (rollbackVersion !== null) {
            rollbackConfig.mutate(rollbackVersion, { onSettled: () => setRollbackVersion(null) });
          }
        }}
      />
    </>
  );
}
