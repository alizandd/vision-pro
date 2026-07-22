---
name: app-deploy
description: The team's standard way to containerize and deploy web applications on Docker + Nginx across stacks (Laravel/PHP, Node.js, Python) for develop and production. Always use this skill whenever the conversation involves deploying an app, containerizing a service, Nginx config, or setting up develop/production environments — even if "deploy" isn't said explicitly.
---

# Deploying Web Apps on Docker + Nginx

This is the team's actual production topology, not a generic template. We run **shared multi-service Compose stacks per server** behind a **single edge reverse proxy — Nginx Proxy Manager (`jc21/nginx-proxy-manager`, GUI-managed)**, with all images pulled by tag from the private registry (a **Harbor** at `registry.qoo.studio`). **Three project shapes** are deployed on this same foundation — match whichever fits, deviate only with a recorded reason:
- **Shape A** — decoupled API + N standalone SPA frontends (e.g. `qoobox_v3`).
- **Shape B** — one coupled monolith image run as many roles (e.g. `team-flow`).
- **Shape C** — one app image, multi-tenant: a separate stack per customer (e.g. the `crm` box).

> **This is verified, not aspirational.** The whole model was audited read-only across four servers, the NPM edge, and the source repos on 2026-07-06 — the fleet map (prod `qoo.studio`, develop mirror `dev.qoo.studio`, dedicated `teamflow`, multi-tenant `crm`), exact registry/CI/deploy commands, NPM routing internals, and the open hardening findings live in [`references/fleet.md`](references/fleet.md). Read it before acting on any server-specific detail.

## Shared foundation (both shapes)

- **One Compose stack per server**, living in a server path, **not** in any app repo (e.g. production → `/opt/qoobox_v3` on `qoo.studio`, develop → `/opt/develop_qoobox_v3` on `dev.qoo.studio`).
- **A separate edge reverse proxy — Nginx Proxy Manager (`jc21/nginx-proxy-manager`)** — runs as its own single-container stack (`/opt/nginxproxymanager`, service `prx`), terminates TLS (Let's Encrypt, stored in its own `./letsencrypt` volume; SQLite config in `./data`), and routes each public domain to the right container by its **network alias**. It is the only thing bound to 80/81/443. **Adding/removing a public endpoint is a Proxy Host entry in the NPM admin UI (port 81), not an nginx config edit and not a change to the app stacks.**
- **A shared external proxy network** is the seam between the reverse proxy and every public-facing service. Its name comes from `${EXTERNAL_NETWORK}` and varies per server (`br0`, `prx`, …) — the Compose key stays `br0`, only the external `name:` changes. Each public service publishes a stable `*_NW_ALIAS`; the proxy targets that alias, so containers can be recreated/retagged without the proxy caring. **Only public-facing services join this network; workers and internal services stay on `default` only.** Services expose **no host ports** — all traffic arrives via the proxy network.
- **All images are pre-built and pulled by tag** from `registry.qoo.studio` (see Image & config model). The server never builds.

## Shape A — decoupled API + standalone frontends (e.g. qoobox)

```
   ┌──────────────┬──────────────┬──────────────┬───────────────┐
 back (API)     redis        front          admin-front     …N frontends
 Laravel+Octane            (static SPA       (static SPA      each its own image
 alias:*-back-prod          via nginx)        via nginx)       + alias + domain
```
- **API and frontends are fully separate images and repos.** The backend is API-only (Laravel + Octane/Swoole). Each frontend is a standalone SPA built to static files and served by its own small nginx — it talks to the API over the network, never shares a codebase or container with it.
- One stack holds `back`, `redis`, and every `*-front`. Each frontend is added/retagged independently.

## Shape B — coupled multi-process app (one image, many roles) (e.g. TeamFlow)

```
   web (nginx + baked assets)        reverb (websockets)     ← on proxy network
        │ depends_on app                  │
   ┌────┴───────┬──────────────┬──────────┴─────┬───────────┐
  app          queue         scheduler         redis        ← default network only
 (php-fpm,   (queue:work)   (schedule:work)
  migrates)
   └──────────── same PHP image, different command ──────────┘
```
- For a **monolith where front and server ship together** (Laravel + Inertia/Vue). One repo builds **two images**: a PHP image (`APP_IMAGE`) and an nginx `web` image (`FRONT_IMAGE`) with the Vite assets **baked in** (no shared asset volume).
- **The one PHP image is reused across four roles**, differing only by `command`: `app` (php-fpm), `queue` (`queue:work`), `reverb` (`reverb:start` websockets), `scheduler` (`schedule:work`). Build once, run as many process types.
- **Exactly one service owns migrations.** Only `app` gets `RUN_MIGRATIONS: "true"` (and `RUN_SEED` for first-boot demo data); its entrypoint waits for the DB, migrates, and caches config before starting. The other three reuse the image but must **not** migrate — otherwise concurrent migrations race on boot.
- **Only `web` and `reverb` join the proxy network** (each its own alias/domain — and the proxy must allow WebSocket upgrade for Reverb). `app`, `queue`, `scheduler`, `redis` stay internal on `default`.
- **Shared Laravel env via a `x-php-env` YAML anchor** injected into all PHP services, so app/queue/reverb/scheduler are guaranteed identical config. External services come from env: **S3** filesystem (`FILESYSTEM_DISK: s3` — so no shared user-upload volume needed), **SES** SMTP mail, **VAPID** web-push keys, Reverb app id/key/secret.
- **`APP_KEY` must be set in `.env` before first boot** — a missing key breaks encryption/sessions on startup.

## Shape C — one app image, multi-tenant (a stack per customer) (e.g. CRM)

```
 /opt/crm      /opt/crm-gl4d   /opt/crm-elitevent   …one stack per customer
 ┌──────────┐  ┌──────────┐    ┌──────────┐         each: same crm image,
 back+redis    back+redis      back+redis           own .env / domain / alias
 +scheduler    +scheduler      +scheduler
```
- For a **single product sold to many customers**, where each tenant needs isolated data and its own domain. **One image** (`registry.qoo.studio/qoo/crm`, a Laravel monolith serving both API and UI on `:8000`) is deployed **once per customer** as its own Compose stack in its own `/opt/<tenant>` dir with its own `.env-laravel`, domain, and network alias.
- Each stack = `back` (the app) + `redis` + `scheduler` (a `while true; artisan schedule:run; sleep 60` loop). `back` mounts `./.env-laravel` as `.env` plus persistent `app-storage`/`settings.json`/`logs`. Same registry, same append-tag-in-`.env` deploy, same NPM edge on `prx`.
- Tenant isolation is **stack-level, not in-app** — adding a customer = copy the stack dir, set that tenant's `.env`, add the NPM Proxy Host. Simpler than Shape B (no separate web/reverb per tenant).
- **Watch two drifts on the live `crm` box** (see `references/fleet.md`): it publishes host ports per tenant and some tenants still run a **mutable** tag (`crm:1.4`) instead of `sha-<short>`. New tenants should stay port-less and sha-pinned.

## Image & config model

- **Everything is a pre-built image from the private registry** `registry.qoo.studio` — a **Harbor** instance (itself behind the same NPM: `registry.qoo.studio → harbor:8080`). App images live under `registry.qoo.studio/qoo/<image>`; base images under `registry.qoo.studio/base/<image>`. The server never builds — CI (self-hosted runner) builds, **cosign-signs**, and pushes; the server only pulls a tag. CI logs in as the `cicd` user.
- **Tag pinned per service via env**, e.g. `image: registry.qoo.studio/qoo/${FRONT_IMAGE}:${FRONT_IMAGE_TAG:-latest}`. A deploy = write the new tag into the server `.env` and `docker compose up -d <service>` (see `cicd-pipeline`).
- **Everything from env, nothing hardcoded.** One `.env` per server holds, for each service: `*_IMAGE`, `*_IMAGE_TAG`, `*_CPU`, `*_MEM`, `*_NW_ALIAS`, `*_DOMAIN` (+ DB creds for `back`). Secrets (DB pass, registry creds) are filled from the server, never committed.
- **Resource limits per service** via `deploy.resources.limits` (`cpus`/`memory`), values from env — so one noisy frontend can't starve the API.
- **Centralized logging** via a shared YAML anchor (`x-logging`) on every service: `json-file` driver, Loki-ready (the `loki-url` option is wired but commented until the Loki endpoint is on).

### Shape A — frontend service pattern (every SPA frontend follows this)
```yaml
  <name>-front:
    image: registry.qoo.studio/qoo/${<NAME>_FRONT_IMAGE}:${<NAME>_FRONT_IMAGE_TAG:-latest}
    restart: always
    <<: *logging
    deploy:
      resources:
        limits:
          cpus: ${<NAME>_FRONT_CPU:-2}
          memory: ${<NAME>_FRONT_MEM:-2G}
    networks:
      default:                 # talk to back + redis
      br0:
        aliases:
          - ${<NAME>_FRONT_NW_ALIAS}   # reverse proxy targets this
```

The backend follows the same shape plus DB/Redis/PHP env and persistent volumes:
```yaml
  back:
    image: registry.qoo.studio/qoo/${BACK_IMAGE}:${BACK_IMAGE_TAG:-latest}
    env_file: [ ./.env-nova ]
    environment:
      - DB_HOST=${DB_HOST}            # DB is external to the stack (host/another box)
      - REDIS_HOST=redis             # the redis service in this stack
      - APP_URL=https://${BACK_DOMAIN}
      - PHP_UPLOAD_MAX_FILESIZE=500M  # tune PHP via env, not baked images
    volumes:
      - ./app-storage:/app/storage/app/public   # persist user uploads
      - ./auth-storage:/app/storage/app/auth
      - ./logs-storage:/app/storage/logs
    networks: { default: , br0: { aliases: [ "${BACK_NW_ALIAS}" ] } }

networks:
  default:
  br0:
    name: ${EXTERNAL_NETWORK:-br0}
    external: ${EXTERNAL_NWG_ENABLE:-false}
```

### Shape B — multi-process app pattern (one image, many roles)
One `x-php-env` anchor feeds every PHP service; the same `${APP_IMAGE}` runs under different commands. Only `web` and `reverb` are public.
```yaml
x-php-env: &php-env
  APP_KEY: ${APP_KEY}          # MUST be set before first boot
  DB_HOST: ${DB_HOST}
  REDIS_HOST: redis
  QUEUE_CONNECTION: redis
  FILESYSTEM_DISK: s3          # uploads go to S3 — no shared upload volume
  # ... SES mail, VAPID, Reverb app id/key/secret, PHP limits ...

services:
  web:                         # nginx + baked Vite assets — public
    image: registry.qoo.studio/qoo/${FRONT_IMAGE}:${FRONT_IMAGE_TAG:-latest}
    depends_on: [ app ]
    networks: { default: , br0: { aliases: [ "${FRONT_NW_ALIAS}" ] } }

  app:                         # php-fpm — owns migrations, internal only
    image: registry.qoo.studio/qoo/${APP_IMAGE}:${APP_IMAGE_TAG:-latest}
    environment:
      <<: *php-env
      RUN_MIGRATIONS: "true"   # ONLY this service migrates (entrypoint)
      RUN_SEED: "false"        # true once, on first boot, for demo data
    volumes: [ ./app-storage:/var/www/html/storage ]
    networks: [ default ]

  queue:                       # same image, different command — internal
    image: registry.qoo.studio/qoo/${APP_IMAGE}:${APP_IMAGE_TAG:-latest}
    environment: *php-env
    command: ["php","artisan","queue:work","--tries=3","--timeout=90"]
    networks: [ default ]

  reverb:                      # websockets — public (proxy must allow WS upgrade)
    image: registry.qoo.studio/qoo/${APP_IMAGE}:${APP_IMAGE_TAG:-latest}
    environment: *php-env
    command: ["php","artisan","reverb:start","--host=0.0.0.0","--port=8080"]
    networks: { default: , br0: { aliases: [ "${REVERB_NW_ALIAS}" ] } }

  scheduler:                   # cron loop — internal
    image: registry.qoo.studio/qoo/${APP_IMAGE}:${APP_IMAGE_TAG:-latest}
    environment: *php-env
    command: ["php","artisan","schedule:work"]
    networks: [ default ]
```

## Stack-specific notes

### PHP / Laravel — Shape A API (the `back` service, Octane)
- Built `FROM registry.qoo.studio/base/laravel:9-redis-phpdev-mongo-swoole` (Redis + Mongo + Swoole already in the base).
- `composer install --prefer-dist --optimize-autoloader --no-interaction`, then the run script is patched from `serve` → **`octane:start`** so it serves under Octane/Swoole. Also `storage:link` and `l5-swagger:generate` at build.
- **Stateful dirs are volumes**, never in the image: `storage/app/public`, `storage/app/auth`, `storage/logs`.
- DB is **outside** the stack (`DB_HOST` points at the host/another box); Redis is in-stack (`REDIS_HOST=redis`).
- Post-deploy command runs `php artisan migrate --force` (see `ACMD` in `cicd-pipeline`).

### PHP / Laravel — Shape B monolith (php-fpm image, four roles)
- **Multi-stage Dockerfile, two images out of one repo:** ① `node:20-alpine` builds Vite assets (Reverb client params baked via `VITE_REVERB_*` build args) → ② `composer:2` installs prod deps (`--no-dev --no-scripts --optimize-autoloader`) → ③ `php:8.3-fpm-alpine` runtime (adds `pdo_mysql/intl/gd/zip/bcmath/exif/pcntl/opcache` + `redis` via PECL, OPcache tuned) with code + vendor + built assets → ④ `nginx:alpine` `web` image with `public/` baked in.
- **Entrypoint gates startup**: waits for the DB, runs `migrate` + `config/route/view cache` **only when `RUN_MIGRATIONS=true`**, then hands off to the per-service `CMD`. Set that flag on the `app` service only.
- **One image, four roles** (`app` php-fpm, `queue` queue:work, `reverb` reverb:start, `scheduler` schedule:work) — see the Shape B compose pattern above. Scale workers by replicating the service, not rebuilding.
- **Uploads go to S3** (`FILESYSTEM_DISK: s3`), so the only volume is `storage/` for framework cache/logs/sessions shared across the PHP services. Mail via **SES SMTP**; push via **VAPID** keys — all from env.
- **Realtime = Laravel Reverb** on its own public alias; the reverse proxy must pass the WebSocket upgrade through to port 8080.

### Frontend SPAs (`*-front` services)
- Two-stage Dockerfile: **`node:22`** builder (`npm install` → `npm run build`) → `nginx` serving `/usr/share/nginx/html`, with the app's own `default.conf` copied to `/etc/nginx/conf.d/`. (Shape B's in-image frontend stage is still `node:20-alpine` — keep each repo's Dockerfile as its source of truth.)
- The image's internal nginx serves static assets + SPA fallback only; the **edge reverse proxy** handles TLS, the public domain, and routing — keep those concerns out of the app image.
- 3D-heavy frontends (Three.js) ship large model binaries via **Git LFS**; CI must resolve LFS before build or nginx serves pointer files (see `cicd-pipeline` and `threejs-3d`).

### Python
- Slim base; deps in a build stage; ASGI/WSGI server (uvicorn/gunicorn) with workers per CPU; expose a health endpoint. Same image/alias/limits pattern; same br0 wiring.

## Adding to the stack
**Shape A — a new SPA frontend:**
1. Give the app its own repo with a frontend Dockerfile + `default.conf` and its own `cicd.yml` (per `cicd-pipeline`).
2. Add a `<name>-front` service block to the server Compose (copy the Shape A pattern).
3. Add its env vars to the server `.env`: `*_FRONT_IMAGE`, `*_FRONT_IMAGE_TAG`, `*_FRONT_CPU`, `*_FRONT_MEM`, `*_FRONT_NW_ALIAS`, `*_FRONT_DOMAIN`.
4. Add a vhost on the **reverse proxy**: `*_FRONT_DOMAIN` → `*_FRONT_NW_ALIAS` over the proxy network, with TLS.
5. First deploy via the app's pipeline pins the image tag in `.env` and brings the one service up.

**Shape B — a new multi-process app:**
1. One repo, multi-stage Dockerfile emitting the PHP image + the `web` image; its own `cicd.yml` builds **both** (per `cicd-pipeline`).
2. Add the five-ish services (`web`, `app`, `queue`, `reverb`, `scheduler`) sharing the `x-php-env` anchor; mark only `app` with `RUN_MIGRATIONS: "true"`.
3. Add env: `APP_IMAGE/_TAG`, `FRONT_IMAGE/_TAG`, `APP_KEY` (required), DB creds, Redis/Reverb/S3/SES/VAPID values, `*_NW_ALIAS`/`*_DOMAIN` for `web` and `reverb`, limits.
4. Add **two** reverse-proxy vhosts: `FRONT_DOMAIN` → `FRONT_NW_ALIAS`, and the Reverb domain → `REVERB_NW_ALIAS` **with WebSocket upgrade** enabled.
5. Ensure `APP_KEY` is set before the first boot; first deploy pins both tags and brings the services up (the `app` entrypoint migrates).

## Reverse-proxy concerns (the edge stack — Nginx Proxy Manager)
- **The edge is Nginx Proxy Manager (`jc21/nginx-proxy-manager`), not a hand-written nginx.conf.** Vhosts are "Proxy Hosts" configured in the NPM admin UI on port 81; each maps a public domain → a container's network alias:port over the external (`prx`) network. Custom directives (timeouts, `client_max_body_size`, security headers, WebSocket upgrade) go in the per-host "Advanced" tab, not a repo file.
- Owns TLS/certs (Let's Encrypt, auto-renewed by NPM), HTTP→HTTPS redirect, security headers, gzip, static caching, sane timeouts, and `client_max_body_size` (lift it for the API — uploads are capped at 500M).
- Routes strictly by network alias over the proxy network — never by container name or host port. **Upstream port convention:** SPA fronts → `:80`, Laravel/Octane backs → `:8000`, Node backs → `:3000`/`3001`/`4001`.
- **Enable the "Websockets Support" toggle** on any Reverb/realtime Proxy Host (Shape B) so `wss://` connections survive the proxy.
- Is the only thing bound to 80/81/443; app services stay port-less and internal.
- The live routing table, `develop.*` toggling, and the current NPM hardening findings (admin on plain `:81`, `ssl_forced=0` hosts, config drift) are inventoried in [`references/fleet.md`](references/fleet.md).

## Rollback
- Images are tagged per commit (`sha-<short>`) and kept in the registry. **Rollback = re-pin the previous tag** in the server `.env` and `docker compose up -d <service>` — no rebuild.
- If a deploy included a migration, also assess `migrate:rollback`. **Back up the DB before production migrations.**

## DEPLOY.md (always write, per stack)
- Prerequisites (Docker/Compose version, br0 network exists, registry login, required env vars).
- How the shared stack + reverse proxy fit together (this topology).
- `develop` deploy and `production` deploy — step by step (which server path, which env).
- Add-a-service checklist (above).
- Rollback procedure + post-deploy checks (`docker compose ps`, health, `logs --tail`).

## The deploy command (what CI actually runs)
A deploy is one SSH from the CI runner into the server stack dir — no rebuild on the box. Verbatim from the pipelines (branch picks the path: `main`→`/opt/<project>`, `develop`→`/opt/develop_<project>`):
```bash
# Shape A (single service, migrate after):
echo BACK_IMAGE_TAG=sha-<sha> >> .env && docker compose up -d back \
  && docker compose exec back php artisan migrate --force
# Shape B (two images, pull + bring up all roles; app entrypoint migrates):
echo APP_IMAGE_TAG=sha-<sha>  >> .env && echo FRONT_IMAGE_TAG=sha-<sha> >> .env \
  && docker compose pull app web queue reverb scheduler \
  && docker compose up -d app web queue reverb scheduler
```
Full pipeline (buildx, cosign, `type=sha` tags, secrets) lives in `cicd-pipeline`.

## Known tradeoffs / hardening backlog (surface to the lead)
- `EXTERNAL_NWG_ENABLE` must be `true` in real deploys so the external network (`prx`) is treated as pre-existing; the `false` default is only safe for an isolated single-box bring-up.
- The deploy **appends** the image tag to `.env` (last value wins, so it works) but the file grows unboundedly — the team-flow pipeline already carries a **commented-out** `sed -i '/^APP_IMAGE_TAG=/d' .env` cleanup; prefer enabling that (or a dedicated tag-override file / idempotent set-key step).
- No host ports is correct; keep it that way — exposing a frontend/API port bypasses the proxy and TLS. (The `crm` box currently violates this — see below.)
- **Open audit findings** (committed secrets, hardcoded SMTP creds, NPM admin on plain `:81`, `ssl_forced=0` hosts, `crm` host-ports + mutable `1.4` tag, NPM config drift) are catalogued in [`references/fleet.md`](references/fleet.md) — treat that list as the live hardening backlog.
