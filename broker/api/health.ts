import type { VercelRequest, VercelResponse } from '@vercel/node';
import { applyCors } from './_whoop';

// GET /api/health
// A quick deploy check. Reports whether the function is live and whether the
// WHOOP credentials are configured — WITHOUT revealing their values (booleans
// only). Use this right after `vercel --prod` to confirm the env vars landed.
export default function handler(req: VercelRequest, res: VercelResponse) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  return res.status(200).json({
    ok: true,
    hasClientId: Boolean(process.env.WHOOP_CLIENT_ID),
    hasClientSecret: Boolean(process.env.WHOOP_CLIENT_SECRET),
  });
}
