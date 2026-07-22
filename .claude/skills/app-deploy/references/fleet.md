# Fleet inventory & deploy-model audit (point-in-time)

> Snapshot from a **read-only** review on **2026-07-06** across the servers, the NPM
> edge, and the source repos. Counts and IPs drift; the **patterns** in `SKILL.md` are the
> durable part. Re-verify before acting on any specific here.

## Server map

| Role | Host (Termius name) | Address / key | What runs |
|---|---|---|---|
| **Production, multi-tenant** | `qoo.studio` | `qoo.studio` (ubuntu, AWS Lightsail `ip-172-26-14-237`) | ~75 stacks under `/opt/<project>`, ~260 containers — Shapes A + B side by side |
| **Develop/staging mirror** | `QOO DEV` (= `dev.qoo.studio`) | `3.98.235.210` / `Devserver.pem` | 81 containers, **every** stack is `/opt/develop_<project>` — the develop twin of prod. Branch `develop` deploys here |
| **Dedicated single app** | `teamflow` | `3.111.119.217` / `team-flow.pem` (AWS Mumbai `ip-172-26-6-99`, Ubuntu 24.04) | only `/opt/team-flow` (Shape B) + its own NPM |
| **Dedicated multi-tenant** | `Crm` | `15.223.120.244` / `CRM.pem` (Ubuntu 24.04) | one `crm` Laravel image, **one stack per customer** (Shape C) |

The deploy model is **reused verbatim across servers**: private registry → pin `sha-` tag in the
per-stack `.env` → `docker compose up`/`pull` → NPM edge on the `prx` network. A project either
shares the multi-tenant box or gets its own box with the identical recipe. `main`→`/opt/<project>`,
`develop`→`/opt/develop_<project>` (usually the develop mirror host).

## The private registry is Harbor
`registry.qoo.studio` is a **Harbor** instance, itself behind the same NPM
(`registry.qoo.studio → harbor:8080`). App images: `registry.qoo.studio/qoo/<image>`; base
images: `registry.qoo.studio/base/<image>`. CI logs in as user `cicd`. Images are
**cosign-signed** in CI (supply-chain provenance).

## NPM edge internals (from `/opt/nginxproxymanager/data/database.sqlite`, read-only)
Admin UI at `http://qoo.studio:81`. The `proxy_host` table is the whole routing map — at
snapshot: **233 proxy hosts, 163 enabled, 224 with a TLS cert, 62 with WebSocket upgrade**.
Every row is `domain(s) → http://<network-alias>:<port>`, routed by Compose network alias,
never container name/host port. One proxy host can serve several comma-separated domains.
`develop.*` hosts are pre-created but mostly disabled (`en=0`) on the prod NPM.

**Port convention seen across all hosts** (durable — worth honoring on new services):
- SPA frontends (`*-front-prod`) → `:80`
- Laravel/Octane backends (`*-back-prod`) → `:8000`
- Node backends → `:3000` / `:3001` / `:4001`
- Reverb / socket.io / realtime → have WebSocket upgrade on (`ws=1`)

Infra vhosts on the same NPM: `registry.qoo.studio→harbor:8080`, `portainer.qoo.studio→portainer:9000`,
`pma.qoo.studio→pma-internal:8443`, `support.qoo.studio→zammad-nginx:8080` (Zammad),
`matomo.qoo.studio`, `log.qoo.studio→log-service:8000`, `notification.qoo.studio`.

## Source-side confirmation (GitHub `Qoo-Studio/*`)
Three repos map 1:1 to the shapes and prove the model end to end:
- **`qoobox_server_v3`** (Shape A server): Laravel 10 + Nova + Octane; `Dockerfile FROM
  registry.qoo.studio/base/laravel:9-redis-phpdev-mongo-swoole`, patches `serve→octane:start`.
  `cicd.yml`: self-hosted runner → buildx → **cosign sign** → push `qoo/qoobox_server_v3`
  with `type=sha`. Deploy job SSHes to `qoo.studio` (main→`/opt/qoobox_v3`,
  develop→`/opt/develop_qoobox_v3`) and runs, literally:
  `echo BACK_IMAGE_TAG=sha-<sha> >> .env && docker compose up -d back && docker compose exec back php artisan migrate --force`.
- **`qoostudio_v4_viceroy_front-`** (Shape A front; note the trailing `-` in the repo name):
  Vue 3 SPA, two-stage **`node:22`**→`nginx` Dockerfile copying `default.conf` + `dist`.
  Heavy 3D libs (three.js, mapbox-gl, unity-webgl, sketchfab) → Git-LFS-heavy repo.
- **`team-flow`** (Shape B): 4-stage Dockerfile (`node:20-alpine` → `composer:2` →
  `php:8.3-fpm-alpine` app → `nginx:alpine` web); Reverb params baked via `VITE_REVERB_*`
  build args. CI builds **both** images via a matrix on Dockerfile `target:` and deploys to
  `teamflow.qoo.studio` with `echo APP_IMAGE_TAG/FRONT_IMAGE_TAG >> .env && docker compose pull && up -d app web queue reverb scheduler`.

The **append-to-`.env` growth** is literally in the CI (`echo TAG >> .env`) — team-flow's
workflow even carries a **commented-out** `sed -i '/^APP_IMAGE_TAG=/d' .env` (the idempotent
fix is known but not enabled). Version drift vs the skill: front build stage is now **node:22**.

## Audit findings / hardening backlog (surface to the lead — all observed read-only)
1. **Committed secrets in a repo**: `qoobox_server_v3` root has `docusign_private_key.pem`
   (a real RSA private key) + `docusign_public_key.pem`, plus `dump.rdb` and `.rnd`.
   Purge from history + rotate.
2. **Hardcoded SMTP creds in compose**: `/opt/team-flow/docker-compose.yml` inlines SES
   `MAIL_USERNAME`/`MAIL_PASSWORD` instead of pulling from `.env` — contradicts
   "nothing hardcoded". Rotate + move to env.
3. **NPM admin panel is plain HTTP on `:81`, publicly reachable** — put behind firewall/VPN
   or at least TLS.
4. **TLS not forced on many prod hosts** (`ssl_forced=0`) — http isn't redirected to https.
5. **Crm box deviates from the standard**: publishes host ports per tenant
   (`8001–8005 → 8000`, pma on `9092`) instead of routing only via the proxy, and some
   tenants still run the **mutable** tag `crm:1.4` instead of an immutable `sha-<short>`.
6. **NPM config drift**: duplicate/overlapping proxy hosts (two `pixelstrategiesinc.com`,
   two `amalfi.qoo.studio`, `panel.cast.qoo.studio` with and without a cert), one malformed
   domain entry, a couple pointing at raw IPs / `127.0.0.1`.
