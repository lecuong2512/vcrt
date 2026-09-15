import { fetchApi } from './client';

export interface UpdateStatus {
  status: string;
  current_version: string;
  remote_version: string;
  has_update: boolean;
  auto_update: boolean;
  changelog?: string;
  sha256?: string;
}

export async function checkUpdate(): Promise<UpdateStatus | null> {
  return await fetchApi<UpdateStatus>('check_update');
}

export async function doUpdate(): Promise<{ status: string; message?: string } | null> {
  return await fetchApi('do_update');
}

export async function setAutoUpdate(enabled: boolean): Promise<{ status: string; auto_update: boolean } | null> {
  return await fetchApi('set_auto_update', { enabled: enabled ? '1' : '0' });
}
