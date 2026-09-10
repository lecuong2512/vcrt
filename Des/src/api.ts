// API Bridge connecting VCRT Frontend to OpenWrt Backend (/cgi-bin/vcrt)

export const API_BASE = window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1"
  ? "http://192.168.10.1/cgi-bin/vcrt"
  : "/cgi-bin/vcrt";

export async function fetchApi(action: string, params: Record<string, string> = {}) {
  const token = localStorage.getItem("vcrt_token") || "";
  const allParams: Record<string, string> = { action, ...params };
  if (token && !allParams.token) allParams.token = token;
  const query = new URLSearchParams(allParams).toString();
  try {
    const res = await fetch(`${API_BASE}?${query}`, {
      method: "GET",
      headers: { "Accept": "application/json" },
      cache: "no-store",
      signal: AbortSignal.timeout(6000)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    return null;
  }
}

export async function postApi(action: string, params: Record<string, string> = {}, bodyData?: any) {
  const token = localStorage.getItem("vcrt_token") || "";
  const allParams: Record<string, string> = { action, ...params };
  if (token && !allParams.token) allParams.token = token;
  const query = new URLSearchParams(allParams).toString();
  try {
    const init: RequestInit = {
      method: "POST",
      headers: { "Accept": "application/json" },
      cache: "no-store",
      signal: AbortSignal.timeout(10000)
    };
    if (bodyData !== undefined) {
      init.headers = { ...init.headers, "Content-Type": "application/json" };
      init.body = typeof bodyData === "string" ? bodyData : JSON.stringify(bodyData);
    }
    const res = await fetch(`${API_BASE}?${query}`, init);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    return null;
  }
}

export async function loginApi(user: string, pass: string) {
  return await postApi("login", { user, pass }, { user, pass });
}

export async function checkAuthApi(token: string) {
  return await fetchApi("auth_check", { token });
}

export async function logoutApi(token: string) {
  return await fetchApi("logout", { token });
}

export async function changePasswordApi(oldPass: string, newPass: string) {
  return await postApi("change_password", {}, { old_pass: oldPass, new_pass: newPass });
}

export interface TelegramConfig {
  status: string;
  enabled: boolean;
  running: boolean;
  has_token: boolean;
  token_masked: string;
  chat_id: string;
  notif_wifi: boolean;
  notif_expire: boolean;
  notif_daily: boolean;
  daily_hour: number;
}

export async function getTelegramConfigApi(): Promise<TelegramConfig | null> {
  return await fetchApi("telegram_get");
}

export async function saveTelegramConfigApi(params: {
  bot_token?: string;
  chat_id: string;
  notif_wifi: boolean;
  notif_expire: boolean;
  notif_daily: boolean;
  daily_hour: number;
  bot_enabled: boolean;
}) {
  return await fetchApi("telegram_set", {
    bot_token: params.bot_token || "",
    chat_id: params.chat_id,
    notif_wifi: params.notif_wifi ? "1" : "0",
    notif_expire: params.notif_expire ? "1" : "0",
    notif_daily: params.notif_daily ? "1" : "0",
    daily_hour: String(params.daily_hour),
    bot_enabled: params.bot_enabled ? "1" : "0"
  });
}

export async function testTelegramBotApi(bot_token?: string, chat_id?: string) {
  const p: Record<string, string> = {};
  if (bot_token) p.bot_token = bot_token;
  if (chat_id) p.chat_id = chat_id;
  return await fetchApi("telegram_test", p);
}

export async function controlTelegramServiceApi(type: "start" | "stop" | "restart") {
  return await fetchApi("telegram_service", { type });
}
