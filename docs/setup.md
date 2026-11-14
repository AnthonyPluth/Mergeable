# Relay setup

Steps only you can do. Run the relay commands from `relay/`.

## 1. GitHub Apps

**Mergeable** (the app's own sign-in): owner your account, installable only on it, Device Flow on, expiring user tokens on, webhook off. Permissions: Pull requests RW, Contents RW, Checks R, Commit statuses R, Metadata R. Note the client ID (needed for Task 12).

**Mergeable Notifier** (alerts): installable only on your account. Webhook URL `https://push.pluth.org/webhook` with a generated secret. Permissions: Pull requests R, Issues R, Checks R, Commit statuses R, Metadata R. Events: Pull request, Pull request review, Issue comment, Check suite, Status. Download its private key.

Install both on your personal account, all repositories.

## 2. Cloudflare

```sh
npx wrangler kv namespace create MERGEABLE     # paste the id into wrangler.toml
openssl pkcs8 -topk8 -nocrypt -in notifier.pem -out notifier.pkcs8.pem
npx wrangler secret put WEBHOOK_SECRET
npx wrangler secret put REGISTRATION_SECRET    # any long random string; the app uses it as a bearer token
npx wrangler secret put NOTIFIER_APP_ID
npx wrangler secret put NOTIFIER_PRIVATE_KEY < notifier.pkcs8.pem
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXX.p8
npx wrangler deploy
```

Route `push.pluth.org` to the Worker. `SELF_LOGIN` is in `wrangler.toml`.

## 3. APNs reachability check (Task 1)

Temporarily add a `/probe` route calling `sendPush` with a bogus 64-hex token and deploy. Expect `400 BadDeviceToken`. `403 InvalidProviderToken` means wrong key or team. A network or protocol error means Workers can't reach APNs; run the relay as a Node container behind Traefik instead. Remove the probe afterwards.

## 4. Verify

`curl https://push.pluth.org/health` → `ok`; Notifier's Recent Deliveries show 202.
