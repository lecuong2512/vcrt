const BASE_URL =
  typeof window !== 'undefined' &&
  (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
    ? 'http://192.168.10.1/cgi-bin/vcrt'
    : '/cgi-bin/vcrt';

export function getStoredToken(): string {
  return localStorage.getItem('vcrt_token') || sessionStorage.getItem('vcrt_token') || '';
}

export function setStoredToken(token: string, remember: boolean = true) {
  if (remember) {
    localStorage.setItem('vcrt_token', token);
    sessionStorage.removeItem('vcrt_token');
  } else {
    sessionStorage.setItem('vcrt_token', token);
    localStorage.removeItem('vcrt_token');
  }
}

export function getStoredUser(): string {
  return localStorage.getItem('vcrt_user') || sessionStorage.getItem('vcrt_user') || 'admin';
}

export function setStoredUser(user: string, remember: boolean = true) {
  if (remember) {
    localStorage.setItem('vcrt_user', user);
  } else {
    sessionStorage.setItem('vcrt_user', user);
  }
}

export function clearSession() {
  localStorage.removeItem('vcrt_token');
  localStorage.removeItem('vcrt_user');
  sessionStorage.removeItem('vcrt_token');
  sessionStorage.removeItem('vcrt_user');
}

export async function fetchApi<T = any>(
  action: string,
  params: Record<string, string | number | boolean | undefined> = {}
): Promise<T | null> {
  const token = getStoredToken();
  const queryObj: Record<string, string> = { action };
  if (token) queryObj.token = token;

  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null) {
      queryObj[k] = String(v);
    }
  });

  const qs = new URLSearchParams(queryObj).toString();

  try {
    const res = await fetch(`${BASE_URL}?${qs}`, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {})
      },
      credentials: 'same-origin',
      cache: 'no-store',
      signal: AbortSignal.timeout(7000)
    });

    if (res.status === 401 && action !== 'login' && action !== 'auth_check') {
      clearSession();
      window.dispatchEvent(new CustomEvent('vcrt:unauthorized'));
      return null;
    }

    if (res.status === 429) {
      const data = await res.json().catch(() => null);
      throw new Error(data?.message || 'Quá nhiều yêu cầu, vui lòng thử lại sau.');
    }

    if (!res.ok) {
      const errData = await res.json().catch(() => null);
      throw new Error(errData?.message || `HTTP ${res.status}`);
    }

    return await res.json();
  } catch (err: any) {
    if (err.name !== 'AbortError') {
      console.warn(`[API ${action}]`, err.message);
    }
    return null;
  }
}

export async function postApi<T = any>(
  action: string,
  bodyData: Record<string, any> = {},
  params: Record<string, string | number | boolean | undefined> = {}
): Promise<T | null> {
  const token = getStoredToken();
  const queryObj: Record<string, string> = { action };
  if (token) queryObj.token = token;

  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null) {
      queryObj[k] = String(v);
    }
  });

  const qs = new URLSearchParams(queryObj).toString();
  const fullBody = { ...bodyData };
  if (token && !fullBody.token) fullBody.token = token;

  try {
    const res = await fetch(`${BASE_URL}?${qs}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {})
      },
      credentials: 'same-origin',
      cache: 'no-store',
      body: JSON.stringify(fullBody),
      signal: AbortSignal.timeout(10000)
    });

    if (res.status === 401 && action !== 'login') {
      clearSession();
      window.dispatchEvent(new CustomEvent('vcrt:unauthorized'));
      return null;
    }

    if (res.status === 429) {
      const data = await res.json().catch(() => null);
      throw new Error(data?.message || 'Quá nhiều yêu cầu, vui lòng thử lại sau.');
    }

    const data = await res.json().catch(() => null);
    return data;
  } catch (err: any) {
    if (err.name !== 'AbortError') {
      console.warn(`[POST ${action}]`, err.message);
    }
    throw err;
  }
}
