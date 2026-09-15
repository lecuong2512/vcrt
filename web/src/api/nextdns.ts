import { fetchApi, postApi } from './client';

export interface NextDNSStatus {
  active: boolean;
  profile_id?: string;
  has_apikey?: boolean;
  apikey_masked?: string;
  linked_ip?: string;
  node?: string;
}

export async function getNextDnsConfig(): Promise<NextDNSStatus | null> {
  return await fetchApi<NextDNSStatus>('nextdns_get');
}

export async function setNextDnsProfile(profileId: string) {
  return await postApi('nextdns_set', { profile_id: profileId }, { profile_id: profileId });
}

export async function disableNextDns() {
  return await postApi('nextdns_disable');
}

export async function setNextDnsApiKey(apiKey: string) {
  return await postApi('nextdns_apikey_set', { api_key: apiKey }, { api_key: apiKey });
}

export async function delNextDnsApiKey() {
  return await postApi('nextdns_apikey_del');
}

export async function proxyNextDnsApi(
  endpoint: string,
  method: 'GET' | 'POST' | 'PATCH' | 'DELETE' = 'GET',
  body?: any,
  profileId?: string
) {
  const params: Record<string, string> = {
    endpoint,
    method
  };
  if (profileId) params.profile_id = profileId;

  if (method === 'GET' && !body) {
    return await fetchApi('nextdns_proxy', params);
  }
  return await postApi('nextdns_proxy', body ? { body } : {}, params);
}

export async function syncNextDnsIp(): Promise<{ status: string; linked_ip?: string } | null> {
  return await fetchApi('nextdns_sync_ip');
}
