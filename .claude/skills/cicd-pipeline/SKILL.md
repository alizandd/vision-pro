---
name: cicd-pipeline
description: The team's standard approach to building a CI/CD pipeline for projects — test, build, and automated deploy to develop/production. Always use this skill whenever the conversation involves CI/CD, a pipeline, deploy automation, GitHub Actions, GitLab CI, or automated test/build.
---

# CI/CD Pipeline

This is the team's real pipeline shape, not a generic skeleton. **Each app has its own repo and its own `cicd.yml` that builds one image and deploys one service into the server's shared Compose stack** (see `app-deploy`). The runner is **self-hosted**; images go to the private registry `registry.qoo.studio`; deploy is an SSH step that re-pins a tag and brings the single service up.

## Pipeline shape (per app repo)

```
push/tag/PR ──▶ build job (self-hosted) ──▶ deploy job (self-hosted, skipped on PR)
                 checkout (+ LFS)              SSH to target server
                 build image                   pin IMAGE_TAG in .env
                 push to registry              docker compose up -d <service>
                 cosign sign                   run post-deploy ACMD, tail logs
```

### Triggers
```yaml
on:
  push:
    branches: ["main", "develop"]
    tags: ['v*.*.*']
  pull_request:
    branches: ["main", "develop"]
```
- **PRs build but never push or deploy** (`push:` and the deploy job are gated on `github.event_name != 'pull_request'`) — validates the build without touching servers.
- **`develop` → develop server, `main` → production server.** Both auto-deploy on push.

### Per-app config block (top of the workflow)
Every workflow parameterizes itself with `env:` so the body is identical across apps:
```yaml
env:
  REGISTRY: registry.qoo.studio
  IMAGE_NAME: qoo/<app-image>            # e.g. qoo/qoobox_server_v3, qoo/highrise_v5_kempinski_front
  DOCKER_USER: cicd
  DOCKER_SERVICE: <service>              # the service name in the server Compose (e.g. back, kempinski-front)
  IMAGE_TAG_VAR: <SERVICE>_IMAGE_TAG     # the .env key this app pins (e.g. BACK_IMAGE_TAG)
  SERVER:      ${{ github.ref == 'refs/heads/main' && 'qoo.studio' || github.ref == 'refs/heads/develop' && 'dev.qoo.studio' }}
  SERVER_PATH: ${{ github.ref == 'refs/heads/main' && '/opt/qoobox_v3' || '/opt/develop_qoobox_v3' }}
  ACMD: "php artisan migrate --force"    # API; for a frontend use a no-op like "echo DONE"
```
- `DOCKER_SERVICE` + `IMAGE_TAG_VAR` are what bind this repo to **one** service in the shared stack.
- `ACMD` is the post-deploy command run **inside** the container: `migrate --force` for the API, a harmless `echo DONE` for static frontends (nothing to migrate).

## Build job (self-hosted runner)
1. **Checkout.** For 3D/asset-heavy frontends, install & enable **Git LFS** and pull objects first (see LFS section).
2. **License/secret → file** if the build needs it (e.g. private composer `auth.json` from a base64 secret via `secret-to-file-action`).
3. **`docker/setup-buildx-action`** for BuildKit.
4. **Registry login** to `registry.qoo.studio` with the `cicd` user + `DOCKER_PASSWORD` secret.
5. **`docker/metadata-action`** to derive tags:
   ```yaml
   tags: |
     type=ref,event=branch
     type=ref,event=pr
     type=semver,pattern={{version}}
     type=semver,pattern={{major}}.{{minor}}
     type=sha            # ← sha-<short> is what deploy pins
   ```
6. **`docker/build-push-action`** — `push: ${{ github.event_name != 'pull_request' }}`.
7. **`cosign sign`** the pushed digest (signing skipped on PRs) for image provenance.

## Deploy job (self-hosted runner)
`needs: build`, gated `if: github.event_name != 'pull_request'`.
1. Resolve the short SHA (`benjlevesque/short-sha`) — this is the tag the build pushed via `type=sha`.
2. Write the deploy SSH key from a secret to `~/.ssh/id_rsa` (chmod 600).
3. SSH to `$SERVER` and run, in the stack dir `$SERVER_PATH`:
   ```bash
   echo ${IMAGE_TAG_VAR}=sha-${SHA} >> .env \
     && docker compose up -d ${DOCKER_SERVICE} \
     && docker compose ps \
     && docker compose exec ${DOCKER_SERVICE} "$ACMD" \
     && docker compose logs --tail 25 ${DOCKER_SERVICE}
   ```
   i.e. **pin this app's image tag in the shared `.env`, recreate just its service, run the post-deploy command, tail logs.** Other services in the stack are untouched.

## Variant: multi-image / multi-process app (Shape B)
A coupled monolith (e.g. TeamFlow — see `app-deploy` Shape B) builds **two images from one repo** (the PHP `APP_IMAGE` + the nginx `FRONT_IMAGE`) and recreates **several services** that share the PHP image.
- **Build** both images in the same workflow (two `build-push` steps, or one multi-stage build targeting both `app` and `web` stages), tagged with the same `sha-<short>`. Pass `VITE_REVERB_*` as build args so the realtime client params are baked into the web bundle.
- **Deploy** pins **both** tags to the same SHA and recreates the dependent services together:
  ```bash
  echo APP_IMAGE_TAG=sha-${SHA}   >> .env
  echo FRONT_IMAGE_TAG=sha-${SHA} >> .env
  docker compose up -d app queue reverb scheduler web
  ```
  The `app` service's entrypoint runs migrations (gated by `RUN_MIGRATIONS`), so `ACMD` can stay a no-op here — don't also run `migrate` from CI, or you race the entrypoint.
- Keep tags in lockstep: app and web are built from one commit and must deploy together, or the assets and backend drift.

## Git LFS for 3D / large assets
Three.js model binaries (`.glb`/`.bin`) are stored in **Git LFS**. If CI doesn't resolve LFS, the checkout leaves ~130-byte pointer files and nginx serves those — the model 404s at runtime (`GLTFLoader: "Failed to load"`). Make the build **fail loud** instead:
```bash
git lfs install --local --force && git lfs pull
SIZE=$(stat -c%s "$MODEL_BIN" 2>/dev/null || stat -f%z "$MODEL_BIN")
if [ "$SIZE" -lt 1000000 ]; then
  echo "::error::$MODEL_BIN is still an LFS pointer ($SIZE bytes). LFS smudge failed."; exit 1
fi
```
A broken deploy should fail the build, never ship pointer files. (See `threejs-3d`.)

## Principles
- **Fail-fast**: cheap stages first (lint/test), then build, then deploy.
- **Cache** composer/npm/Docker layers on the self-hosted runner for speed.
- **Secrets in the CI store** (`DOCKER_PASSWORD`, `SSH_PRIVATE_KEY`, license secrets), never in the repo.
- **Versioned, signed images**: every build is `sha-<short>` tagged and cosign-signed → deterministic deploy + rollback.
- **One service per pipeline**: a repo's deploy only ever recreates its own `DOCKER_SERVICE`.

## Lint / Test (add ahead of build)
The current workflows go straight to build — add a fail-fast quality gate before it:
- PHP API: Larastan/PHPStan + `php artisan test` on a throwaway test DB.
- Frontends: ESLint + typecheck + `npm test` / build-as-test.
Run on PRs too, so a red build blocks merge before anything reaches a server.

## Rollback
- Re-run the deploy step pinning the **previous** `sha-<short>` (re-pin `.env` + `docker compose up -d <service>`) — no rebuild, since the old image is still in the registry. Reassess `migrate:rollback` if the bad deploy migrated.

## Hardening backlog (surface to the lead)
- **Pin third-party actions to commit SHAs**, not floating tags — supply-chain hygiene on a self-hosted runner that touches prod. Keep the version tag in a trailing comment so the pin stays readable, and let Dependabot move the SHA.
- **Least-privilege `GITHUB_TOKEN`**: set `permissions:` read-only at workflow level and grant write only on the job that needs it. Never expose privileged credentials to a job that runs untrusted PR code.
- **Deterministic installs**: `npm ci` (not `npm install`) and `composer install` from the committed lockfile, with **install scripts off** by default — 2026's npm/Packagist compromises executed on install (see the registry supply-chain section in `security`). Allow-list the rare package that needs a script.
- **Prefer OIDC over stored cloud credentials** for any cloud provider step — short-lived, run-scoped tokens instead of long-lived secrets.
- `.env` grows on every deploy (append-only; last value wins so it functions). Prefer an idempotent set-key or a dedicated tag-override file.
- `StrictHostKeyChecking=no` trades TOFU safety for convenience — pre-seed `known_hosts` for the deploy targets instead.
- Don't disable signing on protected branches; verify signatures at deploy time if/when feasible.
- Consider a manual approval gate (GitHub Environments + required reviewer) on the **production** deploy, while `develop` stays fully automatic.
