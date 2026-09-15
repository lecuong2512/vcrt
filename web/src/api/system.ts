import { fetchApi, postApi } from './client';

export interface HardwareFlash {
  chip_mb?: number;
  total_mb: number;
  overlay_total_mb?: number;
  overlay_used_mb?: number;
  overlay_avail_mb?: number;
  overlay_pct?: number;
  used_mb: number;
  avail_mb: number;
  used_pct: number;
}

export interface PortStatus {
  wan: { up: boolean; speed: string; label: string };
  lan1: { up: boolean; speed: string; label: string };
  lan2: { up: boolean; speed: string; label: string };
  usb: { connected: boolean; name: string; label: string };
}

export interface UplinkInfo {
  type: string;
  title: string;
  isp?: string;
  ssid?: string;
  bssid?: string;
  channel?: string;
  band?: string;
  signal_dbm?: number;
  signal_pct?: number;
  gateway?: string;
}

export interface TrafficHistoryItem {
  label: string;
  dl: number;
  ul: number;
}

export interface TrafficPeriodDetail {
  dl: string;
  ul: string;
  total: string;
  unit?: string;
  points: TrafficHistoryItem[];
}

export interface SystemStatus {
  status: string;
  device_name: string;
  os_version: string;
  kernel_version: string;
  cpu_temp?: number;
  cpu: number;
  ram_total: number;
  ram_used: number;
  ram_avail: number;
  uptime: string;
  wan_ip: string;
  dl_mbps: number;
  ul_mbps: number;
  flash: HardwareFlash;
  ports: PortStatus;
  uplink: UplinkInfo;
  peak_bandwidth?: { dl_mbps: number; ul_mbps: number };
  traffic?: { dl: string; ul: string };
  traffic_stats?: {
    today?: TrafficPeriodDetail | TrafficHistoryItem[];
    "7d"?: TrafficPeriodDetail | TrafficHistoryItem[];
    month?: TrafficPeriodDetail | TrafficHistoryItem[];
    quarter?: TrafficPeriodDetail | TrafficHistoryItem[];
    year?: TrafficPeriodDetail | TrafficHistoryItem[];
  };
  nextdns?: { active: boolean; node: string };
}

export interface ModemStatus {
  connected: boolean;
  model: string;
  operator: string;
  band: string;
  rsrp: number;
  sinr: number;
  messages: { id: number; from: string; time: string; body: string }[];
}

export async function getSystemStatus(): Promise<SystemStatus | null> {
  return await fetchApi<SystemStatus>('status');
}

export async function cleanRam(): Promise<{ status: string; mem_avail?: number }> {
  return await postApi('clean_ram');
}

export async function rebootRouter(): Promise<void> {
  await postApi('reboot');
}

export async function resetPeakBw(): Promise<void> {
  await postApi('reset_peak_bw');
}

export async function getModemStatus(): Promise<ModemStatus | null> {
  return await fetchApi<ModemStatus>('modem_get');
}
