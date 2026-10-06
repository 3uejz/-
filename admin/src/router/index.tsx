import { Route, Routes } from 'react-router-dom';
import { AppLayout } from '../components/AppLayout';
import { RequireAuth } from './Guard';
import { LoginPage } from '../pages/login/LoginPage';
import { ForbiddenPage } from '../pages/ForbiddenPage';
import { NotFoundPage } from '../pages/NotFoundPage';
import { DashboardPage } from '../pages/dashboard/DashboardPage';
import { AccountsPage } from '../pages/accounts/AccountsPage';
import { AccountDetailPage } from '../pages/accounts/AccountDetailPage';
import { SavesPage } from '../pages/saves/SavesPage';
import { SaveDetailPage } from '../pages/saves/SaveDetailPage';
import { ContentPage } from '../pages/content/ContentPage';
import { ConfigPage } from '../pages/config/ConfigPage';
import { AnnouncementsPage } from '../pages/announcements/AnnouncementsPage';
import { TelemetryPage } from '../pages/telemetry/TelemetryPage';
import { AuditPage } from '../pages/audit/AuditPage';
import { AssistantPage } from '../pages/assistant/AssistantPage';
import { SystemPage } from '../pages/system/SystemPage';

/** 路由表：登录页独立，其余均在带守卫的主框架内。 */
export function AppRouter() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/403" element={<ForbiddenPage />} />
      <Route element={<RequireAuth />}>
        <Route element={<AppLayout />}>
          <Route index element={<DashboardPage />} />
          <Route path="accounts" element={<AccountsPage />} />
          <Route path="accounts/:id" element={<AccountDetailPage />} />
          <Route path="saves" element={<SavesPage />} />
          <Route path="saves/:id" element={<SaveDetailPage />} />
          <Route path="content" element={<ContentPage />} />
          <Route path="config" element={<ConfigPage />} />
          <Route path="announcements" element={<AnnouncementsPage />} />
          <Route path="telemetry" element={<TelemetryPage />} />
          <Route path="audit" element={<AuditPage />} />
          <Route path="assistant" element={<AssistantPage />} />
          <Route path="system" element={<SystemPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Route>
    </Routes>
  );
}
