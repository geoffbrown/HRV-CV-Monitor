import type { VercelRequest, VercelResponse } from '@vercel/node';
import { hardenResponse } from './_whoop';

// GET /api/health
// Cheap readiness check: confirms the function is live and reports whether the
// WHOOP client credentials are present as environment variables. Never returns
// the secret values themselves — only whether they are set.
export default function handler(req: VercelRequest, res: VercelResponse) {
  hardenResponse(res);

  return res.status(200).json({
    ok: true,
    hasClientId: Boolean(process.env.WHOOP_CLIENT_ID),
    hasClientSecret: Boolean(process.env.WHOOP_CLIENT_SECRET),
  });
}
