---
name: observability
description: The team's standard for observability and operational readiness — structured logging, metrics, distributed tracing, dashboards, alerting/SLOs, incident response, and backups/disaster recovery. Always use this skill whenever instrumenting a service, setting up logging/metrics/tracing, defining alerts or SLOs, planning monitoring/dashboards, responding to an incident, or designing backup/restore. Owned by devops; pairs with `app-deploy`, `cicd-pipeline`, and `security`.
---

# Observability & operational readiness

Goal: when something breaks in production you can **see it, alert on it, find the cause fast, and recover** — and you knew about degradation before users did. Owned by **devops**; instrumentation is written with backend/frontend. A service isn't "production-ready" until it's observable and recoverable.

## The three signals (instrument all three)
- **Logs** — structured **JSON** with a correlation/request ID, level, and context; **never log secrets/PII**. Ship to **Loki** via the team's centralized `json-file` logging (already Loki-ready in the house stack — see `app-deploy`).
- **Metrics** — RAG/RED + USE: **R**ate, **E**rrors, **D**uration per endpoint/service; resource **U**tilization/**S**aturation/**E**rrors. Expose **Prometheus** metrics.
- **Traces** — distributed tracing across service boundaries with **OpenTelemetry**, stored in **Tempo**, so a slow/failed request can be followed end-to-end.
- **Standardize on OpenTelemetry** for instrumentation and the **Grafana LGTM stack** (Loki / Grafana / Tempo / Prometheus/Mimir) for storage + visualization. Auto-instrument where available; add spans/labels for the domain-meaningful operations.

## Dashboards & alerting
- A per-service Grafana dashboard: request rate, error rate, latency (p50/p95/p99), saturation, and key business metrics. One overview + drill-downs.
- **Alert on symptoms users feel** (error rate, latency, availability), not just causes (CPU). Every alert must be **actionable** and tied to an owner + a runbook link — no noisy/un-actionable alerts.
- **SLOs**: define an SLI (e.g. % requests < 300ms, success rate) and an SLO target + error budget; alert on burn rate. Prioritize work by SLO impact.

## Incident response
- Detect (alert) → triage (severity, scope, who's affected) → mitigate (stop the bleeding: rollback via `git-workflow`, scale, feature-flag off) → resolve → **blameless post-mortem** with action items.
- Keep a **runbook per service**: how to check health, common failures + fixes, dashboards/log queries, escalation, rollback steps. Link runbooks from alerts.
- Roll back fast (the house deploy pins an image tag in the server `.env` — re-pin the previous `sha-` and `compose up -d`); fix forward only when safe.

## Backups & disaster recovery
- Automated, **tested** backups of databases and durable state; know your **RPO/RTO**. A backup you've never restored is not a backup — periodically rehearse restore.
- Store backups off the primary host, encrypted; document the restore procedure in the deploy README. Cover data, secrets/config, and the recreate-from-scratch path.

## Security & cost
- Observability data can leak secrets/PII — scrub at the source; restrict dashboard/log access (`security`). Watch CVEs in the observability stack like any dependency.
- Control cardinality and retention (high-cardinality labels and infinite retention are the usual cost blowups); sample traces sensibly.

## Output
Instrumentation (logs/metrics/traces) wired to the LGTM stack, a per-service dashboard + actionable alerts/SLOs, a runbook, and a tested backup/restore procedure — each significant choice explained in a sentence. Flag what backend/frontend must instrument, via the tech-lead.
