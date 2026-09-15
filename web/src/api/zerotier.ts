import { fetchApi, postApi } from './client';

export interface ZeroTierNetwork {
  nwid: string;
  name: string;
  mac: string;
  status: string;
  type: string;
  dev: string;
  assigned_ip: string;
}

export interface ZeroTierStatus {
  status: string;
  installed: boolean;
  running: boolean;
  node_id: string;
  version: string;
  online_status: string;
  networks: ZeroTierNetwork[];
}

export interface ZeroTierPeer {
  address: string;
  path: string;
  latency: string;
  version: string;
  role: string;
}

export async function getZeroTierStatus(): Promise<ZeroTierStatus | null> {
  return await fetchApi<ZeroTierStatus>('zerotier_get');
}

export async function joinZeroTierNetwork(nwid: string) {
  return await postApi('zerotier_join', { nwid, network_id: nwid }, { nwid, network_id: nwid });
}

export async function leaveZeroTierNetwork(nwid: string) {
  return await postApi('zerotier_leave', { nwid, network_id: nwid }, { nwid, network_id: nwid });
}

export async function getZeroTierInfo(): Promise<{ status: string; peers: ZeroTierPeer[]; status_raw?: string } | null> {
  return await fetchApi('zerotier_info');
}
