import { fetchApi, postApi } from './client';

export interface WifiBandConfig {
  ssid: string;
  pass: string;
  channel: string;
  power: string;
}

export interface WifiStatusResponse {
  wifi5?: WifiBandConfig;
  wifi24?: WifiBandConfig;
}

export interface ScannedNetwork {
  ssid: string;
  bssid: string;
  channel: string;
  signal: number;
  security: string;
  band: string;
}

export async function getWifiConfig(): Promise<WifiStatusResponse | null> {
  return await fetchApi<WifiStatusResponse>('wifi_get');
}

export async function applyWifiConfig(config: {
  ssid5: string;
  pass5: string;
  ch5: string;
  power5: string;
  ssid24: string;
  pass24: string;
  ch24: string;
  power24: string;
}) {
  return await postApi('wifi_apply', config, config);
}

export async function scanWifi(band: '2.4g' | '5g'): Promise<{ networks: ScannedNetwork[] } | null> {
  return await fetchApi('wifi_scan', { band });
}

export async function connectWifiUplink(params: {
  band: string;
  ssid: string;
  bssid: string;
  key: string;
  channel?: string;
}) {
  return await postApi('wifi_connect_uplink', params, params);
}

export async function rollbackWifiConfig() {
  return await postApi('wifi_rollback');
}

export async function confirmWifiConfig() {
  return await postApi('wifi_confirm');
}
