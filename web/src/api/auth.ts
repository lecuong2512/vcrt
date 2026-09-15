import { fetchApi, postApi, setStoredToken, setStoredUser, clearSession } from './client';

export interface LoginResponse {
  status: string;
  authenticated: boolean;
  token?: string;
  user?: string;
  message?: string;
  retry_after?: number;
}

export async function loginApi(user: string, pass: string, remember = true): Promise<LoginResponse> {
  const res = await postApi<LoginResponse>('login', { user, pass });
  if (res && res.authenticated && res.token) {
    setStoredToken(res.token, remember);
    setStoredUser(res.user || user, remember);
  }
  return res;
}

export async function checkAuthApi(): Promise<{ status: string; authenticated: boolean; user?: string } | null> {
  return await fetchApi('auth_check');
}

export async function logoutApi(): Promise<void> {
  try {
    await fetchApi('logout');
  } finally {
    clearSession();
  }
}

export async function changePasswordApi(oldPass: string, newPass: string) {
  return await postApi<{ status: string; message: string }>('change_password', {
    old_pass: oldPass,
    new_pass: newPass
  });
}
