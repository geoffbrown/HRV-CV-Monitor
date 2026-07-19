# HRV-CV Monitor — Auth Broker

A tiny serverless backend that holds the WHOOP **client secret** so the macOS app
can be shared without embedding the secret in its binary.

The app performs the WHOOP login (PKCE) itself and receives an authorization
`code`. It then posts that code here; this broker adds the client credentials,
calls WHOOP's token endpoint, and returns the tokens. The secret never leaves the
server.

```
app  ──POST /api/token   {code, code_verifier, redirect_uri}──▶  broker ──▶ WHOOP
app  ──POST /api/refresh {refresh_token}────────────────────▶  broker ──▶ WHOOP
```

## Endpoints

| Method | Path           | Body                                      | Returns                     |
|--------|----------------|-------------------------------------------|-----------------------------|
| POST   | `/api/token`   | `{ code, code_verifier, redirect_uri }`   | WHOOP token JSON (passthrough) |
| POST   | `/api/refresh` | `{ refresh_token }`                       | WHOOP token JSON (passthrough) |

WHOOP's status codes and error bodies are forwarded unchanged, so the app still
sees real OAuth errors.

## Deploy to Vercel

1. Install the CLI and log in: `npm i -g vercel && vercel login`
2. From this `broker/` folder: `vercel` (first run links/creates the project)
3. Set the secret as environment variables (both Preview and Production):
   ```
   vercel env add WHOOP_CLIENT_ID
   vercel env add WHOOP_CLIENT_SECRET
   ```
   (or add them in the Vercel dashboard → Project → Settings → Environment Variables)
4. Deploy production: `vercel --prod`
5. Copy the resulting base URL, e.g. `https://hrvcv-auth-broker.vercel.app`

## Point the app at the broker

In `HRV-CV Monitor/WHOOPService.swift`, set:

```swift
static let brokerBaseURL = "https://hrvcv-auth-broker.vercel.app/api"
```

With that set, the app stops using the embedded `clientSecret` entirely — you can
delete `Secrets.swift` from shared builds. Leave `brokerBaseURL` empty for local
development against the embedded secret.

## Local testing

```
vercel dev            # serves the functions at http://localhost:3000
curl -X POST http://localhost:3000/api/refresh \
  -H 'Content-Type: application/json' \
  -d '{"refresh_token":"<a real refresh token>"}'
```

## Notes

- These endpoints are unauthenticated. Abuse is limited (a caller still needs a
  valid WHOOP auth code or refresh token for *your* WHOOP app), but if you expect
  meaningful traffic, add Vercel rate limiting / a shared header check.
- The broker never logs request bodies, so codes/tokens aren't written to logs.
