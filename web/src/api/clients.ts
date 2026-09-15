import { fetchApi, postApi } from './client';

export interface ClientDevice {
  id: string;
  name: string;
  ip: string;
  mac: string;
  band: string;
  rssi: number;
  rxMbps?: number;
  txMbps?: number;
  connectedTime?: string;
  online?: boolean;
  blocked: boolean;
  softBlocked: boolean;
  blockRemain?: number;
  blockDuration?: number;
  icon?: string;
}

export async function getClients(): Promise<{ clients: ClientDevice[] } | null> {
  return await fetchApi<{ clients: ClientDevice[] }>('clients');
}

export async function softBlockDevice(mac: string, minutes: number, name?: string, ip?: string) {
  return await postApi('soft_block', { mac, minutes, name, ip }, { mac, minutes });
}

export async function hardBlockDevice(mac: string, minutes: number, name?: string, ip?: string) {
  return await postApi('hard_block', { mac, minutes, name, ip }, { mac, minutes });
}

export async function unblockDevice(mac: string) {
  return await postApi('unblock', { mac }, { mac });
}
