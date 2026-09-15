import { useState, lazy, Suspense } from 'react';
import { ThemeProvider } from './hooks/useTheme';
import { AuthProvider, useAuth } from './hooks/useAuth';
import { ToastProvider } from './components/Toast';
import { Layout, TabType } from './components/Layout';
import LoginScreen from './screens/LoginScreen';

const DashboardScreen = lazy(() => import('./screens/DashboardScreen'));
const ClientsScreen = lazy(() => import('./screens/ClientsScreen'));
const WiFiScreen = lazy(() => import('./screens/WiFiScreen'));
const NextDNSScreen = lazy(() => import('./screens/NextDNSScreen'));
const SettingsScreen = lazy(() => import('./screens/SettingsScreen'));

function ScreenLoader() {
  return (
    <div className="flex items-center justify-center p-16 text-slate-400 text-xs gap-2">
      <span className="animate-spin text-lg">⏳</span>
      <span>Đang tải màn hình...</span>
    </div>
  );
}

function MainApp() {
  const { isAuthenticated, isLoading } = useAuth();
  const [currentTab, setCurrentTab] = useState<TabType>('dashboard');

  if (isLoading) {
    return (
      <div className="min-h-screen w-screen flex items-center justify-center" style={{ backgroundColor: 'var(--bg-page)', color: 'var(--text-main)' }}>
        <div className="flex flex-col items-center gap-3">
          <span className="text-3xl animate-bounce">⚡</span>
          <span className="text-xs font-mono tracking-wider text-blue-400">VCRT OS v2.0</span>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <LoginScreen />;
  }

  return (
    <Layout currentTab={currentTab} onSelectTab={setCurrentTab}>
      <Suspense fallback={<ScreenLoader />}>
        {currentTab === 'dashboard' && <DashboardScreen />}
        {currentTab === 'clients' && <ClientsScreen />}
        {currentTab === 'wifi' && <WiFiScreen />}
        {currentTab === 'nextdns' && <NextDNSScreen />}
        {currentTab === 'settings' && <SettingsScreen />}
      </Suspense>
    </Layout>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <ToastProvider>
          <MainApp />
        </ToastProvider>
      </AuthProvider>
    </ThemeProvider>
  );
}
