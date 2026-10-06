import { useState } from 'react';
import { Alert, Button, Card, Col, Descriptions, Input, Row, Space, Tag, Typography } from 'antd';
import { RobotOutlined, SendOutlined } from '@ant-design/icons';
import { PageHeader } from '../../components/PageHeader';
import { JsonBlock, QueryError } from '../../components/JsonBlock';
import { useAssistantDraft, useAssistantQuery, useAssistantStatus } from '../../features/useAssistant';
import { ApiError } from '../../api/client';
import { errorMessage } from '../../utils/error';

function renderResult(result: unknown) {
  if (result === undefined || result === null) return '-';
  if (typeof result === 'string') return <Typography.Paragraph>{result}</Typography.Paragraph>;
  return <JsonBlock value={result} title="助手输出" defaultOpen />;
}

/** 运营助手（预留，默认关闭）：状态、查询、草稿生成。 */
export function AssistantPage() {
  const statusQuery = useAssistantStatus();
  const queryMutation = useAssistantQuery();
  const draftMutation = useAssistantDraft();

  const [queryText, setQueryText] = useState('');
  const [draftText, setDraftText] = useState('');
  const [queryError, setQueryError] = useState<string | undefined>();
  const [draftError, setDraftError] = useState<string | undefined>();

  const unavailable =
    statusQuery.data?.enabled === false ||
    (queryError?.includes('未启用') ?? false) ||
    (draftError?.includes('未启用') ?? false);

  const handle = async (
    runner: () => Promise<unknown>,
    setError: (value: string | undefined) => void,
  ) => {
    setError(undefined);
    try {
      await runner();
    } catch (err) {
      if (err instanceof ApiError && err.status === 503) {
        setError('运营助手未启用，请先在部署时启用本地模型。');
        return;
      }
      setError(errorMessage(err));
    }
  };

  return (
    <>
      <PageHeader
        title="运营助手"
        description="后台旁路能力：日志摘要、告警聚合、运营问答与内容草稿；不参与实时玩法。"
      />

      {statusQuery.error ? <QueryError error={statusQuery.error} /> : null}

      {unavailable ? (
        <Alert
          type="warning"
          showIcon
          message="运营助手未启用"
          description="当前版本默认关闭该功能，主功能不受影响。启用后可在部署配置中打开本地模型。"
          style={{ marginBottom: 16 }}
        />
      ) : null}

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={12}>
          <Card size="small" title="助手状态" extra={<RobotOutlined />}>
            <Descriptions column={1} size="small">
              <Descriptions.Item label="是否启用">
                <Tag color={statusQuery.data?.enabled ? 'green' : 'default'}>
                  {statusQuery.data?.enabled ? '已启用' : '未启用'}
                </Tag>
              </Descriptions.Item>
              <Descriptions.Item label="模型就绪">
                <Tag color={statusQuery.data?.ready ? 'green' : 'default'}>
                  {statusQuery.data?.ready ? '就绪' : '未就绪'}
                </Tag>
              </Descriptions.Item>
              <Descriptions.Item label="说明">{statusQuery.data?.message || '-'}</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card size="small" title="自然语言查询">
            <Space direction="vertical" style={{ width: '100%' }}>
              <Input.TextArea
                rows={3}
                placeholder="例如：汇总最近 7 日的异常告警"
                value={queryText}
                onChange={(event) => setQueryText(event.target.value)}
              />
              <Button
                type="primary"
                icon={<SendOutlined />}
                loading={queryMutation.isPending}
                onClick={() => void handle(() => queryMutation.mutateAsync(queryText), setQueryError)}
              >
                提交查询
              </Button>
              {queryError ? <Alert type="error" showIcon message={queryError} /> : null}
              {queryMutation.data !== undefined ? renderResult(queryMutation.data) : null}
            </Space>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card size="small" title="内容草稿生成">
            <Space direction="vertical" style={{ width: '100%' }}>
              <Input.TextArea
                rows={3}
                placeholder="例如：为新手生成一段介绍城镇的公告草稿"
                value={draftText}
                onChange={(event) => setDraftText(event.target.value)}
              />
              <Button
                type="primary"
                icon={<SendOutlined />}
                loading={draftMutation.isPending}
                onClick={() => void handle(() => draftMutation.mutateAsync(draftText), setDraftError)}
              >
                生成草稿
              </Button>
              {draftError ? <Alert type="error" showIcon message={draftError} /> : null}
              {draftMutation.data !== undefined ? renderResult(draftMutation.data) : null}
            </Space>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card size="small" title="状态原始数据">
            <JsonBlock value={statusQuery.data} title="assistant/status" />
          </Card>
        </Col>
      </Row>
    </>
  );
}
