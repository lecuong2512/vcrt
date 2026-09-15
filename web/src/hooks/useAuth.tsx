import { useState, useEffect, createContext, useContext, ReactNode, useCallback } from 'react';
import { getStoredToken, getStoredUser, clearSession } from '../api/client';
import { checkAuthApi, logoutApi } from '../api/auth';

interface AuthContextType {
  token: string;
  user: string;
  isAuthenticated: boolean;
  isLoading: boolean;
  setSession: (token: string, user: string) => void;
  logout: () => Promise<void>;
  checkSession: () => Promise<boolean>;
}

const AuthContext = createContext<AuthContextType>({
  token: '',
  user: 'admin',
  isAuthenticated: false,
  isLoading: true,
  setSession: () => {},
  logout: async () => {},
  checkSession: async () => false
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string>(getStoredToken);
  const [user, setUser] = useState<string>(getStoredUser);
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  const checkSession = useCallback(async (): Promise<boolean> => {
    const curToken = getStoredToken();
    if (!curToken) {
      setIsAuthenticated(false);
      setIsLoading(false);
      return false;
    }

    try {
      const res = await checkAuthApi();
      if (res && res.authenticated) {
        setIsAuthenticated(true);
        if (res.user) setUser(res.user);
        setIsLoading(false);
        return true;
      }
    } catch {
      // Ignored
    }

    clearSession();
    setIsAuthenticated(false);
    setIsLoading(false);
    return false;
  }, []);

  const setSession = useCallback((newToken: string, newUser: string) => {
    setToken(newToken);
    setUser(newUser);
    setIsAuthenticated(true);
  }, []);

  const logout = useCallback(async () => {
    try {
      await logoutApi();
    } finally {
      clearSession();
      setToken('');
      setIsAuthenticated(false);
    }
  }, []);

  useEffect(() => {
    checkSession();

    const handleUnauthorized = () => {
      logout();
    };

    window.addEventListener('vcrt:unauthorized', handleUnauthorized);
    return () => {
      window.removeEventListener('vcrt:unauthorized', handleUnauthorized);
    };
  }, [checkSession, logout]);

  return (
    <AuthContext.Provider
      value={{
        token,
        user,
        isAuthenticated,
        isLoading,
        setSession,
        logout,
        checkSession
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
