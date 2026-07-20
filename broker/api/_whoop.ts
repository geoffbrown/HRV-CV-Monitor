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

/**
 * Hardens responses for the only legitimate caller: the native macOS/iOS app,
 * which uses URLSession and ignores CORS entirely. We therefore grant NO
 * cross-origin access — a webpage in someone's browser cannot read these
 * responses. We deliberately send no `Access-Control-Allow-Origin` at all:
 * not `*`, and not `'null'` (the latter would actually grant access to
 * sandboxed / null-origin browser contexts).
 */
export function hardenResponse(res: VercelResponse): void {
  res.setHeader('Vary', 'Origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}
