import { fetchApi, postApi } from './client';

export interface TelegramConfig {
  status: string;
  enabled: boolean;
  running: boolean;
  has_token: boolean;
  token_masked: string;
  chat_id: string;
  auto_update?: boolean;
  notif_wifi: boolean;
  notif_expire: boolean;
  notif_daily: boolean;
  daily_hour: number;
}

export async function getTelegramConfig(): Promise<TelegramConfig | null> {
  return await fetchApi<TelegramConfig>('telegram_get');
}

export async function saveTelegramConfig(params: {
  bot_token?: string;
  chat_id: string;
  auto_update?: boolean;
  notif_wifi: boolean;
  notif_expire: boolean;
  notif_daily: boolean;
  daily_hour: number;
  bot_enabled: boolean;
}) {
  return await postApi('telegram_set', {
    bot_token: params.bot_token || '',
    chat_id: params.chat_id,
    auto_update: params.auto_update ? '1' : '0',
    notif_wifi: params.notif_wifi ? '1' : '0',
    notif_expire: params.notif_expire ? '1' : '0',
    notif_daily: params.notif_daily ? '1' : '0',
    daily_hour: String(params.daily_hour),
    bot_enabled: params.bot_enabled ? '1' : '0'
  });
}

export async function testTelegramBot(bot_token?: string, chat_id?: string) {
  const p: Record<string, string> = {};
  if (bot_token) p.bot_token = bot_token;
  if (chat_id) p.chat_id = chat_id;
  return await fetchApi('telegram_test', p);
}

export async function controlTelegramService(type: 'start' | 'stop' | 'restart') {
  return await fetchApi('telegram_service', { type });
}
