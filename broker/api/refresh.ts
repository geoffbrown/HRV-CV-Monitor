import type { VercelRequest, VercelResponse } from '@vercel/node';
import { exchangeWithWhoop, applyCors } from './_whoop';

// POST /api/refresh
// Body: { refresh_token }
// Trades a refresh token for a fresh access token, adding the client secret server-side.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  const { refresh_token } = req.body ?? {};
  if (!refresh_token) {
    return res.status(400).json({
      error: 'invalid_request',
      error_description: 'refresh_token is required',
    });
  }

  const { status, body } = await exchangeWithWhoop({
    grant_type: 'refresh_token',
    refresh_token,
  });

  res.status(status).setHeader('Content-Type', 'application/json');
  return res.send(body);
}
