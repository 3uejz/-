import type { ReactNode } from 'react';
import { Alert, Input, Modal, Typography } from 'antd';
import { useState } from 'react';

interface DangerConfirmProps {
  open: boolean;
  title: string;
  description?: ReactNode;
  /** 需要用户原样输入的目标名称或 ID。 */
  confirmText: string;
  confirmLabel?: string;
  loading?: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}

/** 危险操作二次确认：必须原样输入目标名称/ID 才能提交。 */
export function DangerConfirm({
  open,
  title,
  description,
  confirmText,
  confirmLabel = '确认执行',
  loading,
  onCancel,
  onConfirm,
}: DangerConfirmProps) {
  const [typed, setTyped] = useState('');
  const matched = typed.trim() === confirmText;

  const handleCancel = () => {
    setTyped('');
    onCancel();
  };

  const handleConfirm = () => {
    if (!matched) return;
    setTyped('');
    onConfirm();
  };

  return (
    <Modal
      open={open}
      title={title}
      okText={confirmLabel}
      cancelText="取消"
      okButtonProps={{ danger: true, disabled: !matched, loading }}
      onOk={handleConfirm}
      onCancel={handleCancel}
      destroyOnClose
    >
      {description ? <div style={{ marginBottom: 12 }}>{description}</div> : null}
      <Alert
        type="warning"
        showIcon
        message="此操作不可撤销"
        description={
          <span>
            请输入 <Typography.Text code>{confirmText}</Typography.Text> 以确认。
          </span>
        }
        style={{ marginBottom: 12 }}
      />
      <Input
        value={typed}
        onChange={(event) => setTyped(event.target.value)}
        placeholder={confirmText}
        autoFocus
      />
    </Modal>
  );
}
