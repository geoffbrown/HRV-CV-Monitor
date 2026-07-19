import type { VercelResponse } from '@vercel/node';

export const WHOOP_TOKEN_URL = 'https://api.prod.whoop.com/oauth/oauth2/token';

/**
 * Exchanges a set of OAuth params with WHOOP's token endpoint, injecting the
 * client credentials from environment variables. Returns WHOOP's raw response
 * so the app sees real OAuth errors (invalid_grant, etc.) unchanged.
 */
export async function exchangeWithWhoop(
  params: Record<string, string>
): Promise<{ status: number; body: string }> {
  const client_id = process.env.WHOOP_CLIENT_ID;
  const client_secret = process.env.WHOOP_CLIENT_SECRET;
  if (!client_id || !client_secret) {
    return {
      status: 500,
      body: JSON.stringify({
        error: 'server_misconfigured',
        error_description: 'WHOOP_CLIENT_ID / WHOOP_CLIENT_SECRET are not set',
      }),
    };
  }

  const form = new URLSearchParams({ ...params, client_id, client_secret });
  const r = await fetch(WHOOP_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  return { status: r.status, body: await r.text() };
}

/** Permissive CORS (harmless for the native client; convenient for testing). */
export function applyCors(res: VercelResponse): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}
