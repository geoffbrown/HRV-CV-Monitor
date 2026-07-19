import type { VercelRequest, VercelResponse } from '@vercel/node';
import { exchangeWithWhoop, applyCors } from './_whoop';

// POST /api/token
// Body: { code, code_verifier, redirect_uri }
// Exchanges an authorization code for tokens, adding the client secret server-side.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  const { code, code_verifier, redirect_uri } = req.body ?? {};
  if (!code || !code_verifier || !redirect_uri) {
    return res.status(400).json({
      error: 'invalid_request',
      error_description: 'code, code_verifier and redirect_uri are required',
    });
  }

  const { status, body } = await exchangeWithWhoop({
    grant_type: 'authorization_code',
    code,
    redirect_uri,
    code_verifier,
  });

  res.status(status).setHeader('Content-Type', 'application/json');
  return res.send(body);
}
