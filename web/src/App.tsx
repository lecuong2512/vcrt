import { Component, ErrorInfo, ReactNode, useState, lazy, Suspense } from 'react';
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

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('VCRT Runtime Error caught by ErrorBoundary:', error, errorInfo);
  }

  handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen w-screen flex flex-col items-center justify-center p-6 text-center" style={{ backgroundColor: 'var(--bg-page)', color: 'var(--text-main)' }}>
          <div className="w-16 h-16 rounded-2xl bg-rose-50 dark:bg-rose-950/60 border border-rose-200 dark:border-rose-900 flex items-center justify-center text-3xl mb-4 shadow-sm">
            ⚠️
          </div>
          <h2 className="text-lg font-bold text-slate-900 dark:text-slate-100 mb-2">
            Đã xảy ra sự cố hiển thị trên giao diện
          </h2>
          <p className="text-xs text-slate-500 dark:text-slate-400 max-w-md mb-4 font-mono break-words bg-slate-100 dark:bg-slate-800/80 p-3 rounded-xl border border-slate-200 dark:border-slate-700">
            {this.state.error?.message || 'Lỗi không xác định'}
          </p>
          <div className="flex items-center gap-3">
            <button
              onClick={this.handleReload}
              className="vcrt-btn vcrt-btn-primary text-xs py-2 px-4 shadow-sm cursor-pointer"
            >
              🔄 Tải lại trang
            </button>
            <button
              onClick={() => this.setState({ hasError: false, error: null })}
              className="vcrt-btn vcrt-btn-secondary text-xs py-2 px-4 shadow-sm cursor-pointer"
            >
              Thử lại
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

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
    <ErrorBoundary>
      <Layout currentTab={currentTab} onSelectTab={setCurrentTab}>
        <Suspense fallback={<ScreenLoader />}>
          {currentTab === 'dashboard' && <DashboardScreen />}
          {currentTab === 'clients' && <ClientsScreen />}
          {currentTab === 'wifi' && <WiFiScreen />}
          {currentTab === 'nextdns' && <NextDNSScreen />}
          {currentTab === 'settings' && <SettingsScreen />}
        </Suspense>
      </Layout>
    </ErrorBoundary>
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
