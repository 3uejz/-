import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useSessionStore } from '../store/session';

/** 路由守卫：未登录一律跳转登录页，并记录来源路径。 */
export function RequireAuth() {
  const token = useSessionStore((s) => s.accessToken);
  const location = useLocation();

  if (!token) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }
  return <Outlet />;
}
