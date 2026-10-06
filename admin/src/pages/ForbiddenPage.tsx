import { Button, Result } from 'antd';
import { useNavigate } from 'react-router-dom';
import { useSessionStore } from '../store/session';

/** 已登录但无后台权限时的展示页。 */
export function ForbiddenPage() {
  const navigate = useNavigate();
  const clear = useSessionStore((s) => s.clear);

  return (
    <Result
      status="403"
      title="403"
      subTitle="当前账号没有后台权限。"
      extra={
        <Button
          type="primary"
          onClick={() => {
            clear();
            navigate('/login', { replace: true });
          }}
        >
          返回登录
        </Button>
      }
    />
  );
}
