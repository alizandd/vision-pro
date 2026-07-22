---
name: security
description: The team's continuous security practice across the whole lifecycle — threat modeling at design, secure coding, security review, security checks in QA, and ongoing dependency/CVE monitoring after release. Always use this skill whenever designing, building, reviewing, or testing anything that handles user input, auth, data, secrets, or external surface — to prevent security problems from creeping in over time.
---

# Security (Continuous)

Security is not a one-time gate. It runs through every stage so problems don't accumulate over time.

## At design time — threat model
- Identify assets, entry points, trust boundaries, and who could attack what.
- Note authn/authz needs, data sensitivity, and the attack surface in the design doc/ADR.
- Choose secure defaults (least privilege, deny by default, fail closed).

## Secure coding (all stacks)
- **Input/output**: validate and sanitize all input server-side; encode/escape output to prevent XSS.
- **Injection**: parameterized queries / ORM bindings only — never string-built SQL. Same care for command/LDAP/template injection.
- **AuthN/AuthZ**: enforce on the server for every protected action; never trust the client. Check ownership, not just "logged in."
- **Secrets**: never hardcode or commit; use env/secret manager. Rotate-able.
- **Sessions/tokens**: secure, httpOnly, SameSite cookies or properly scoped tokens; short-lived + refresh where relevant; single-use, expiring reset tokens.
- **Crypto**: use vetted libraries; hash passwords with a strong adaptive algorithm (bcrypt/argon2); never roll your own.
- **Rate limiting & abuse**: on auth and sensitive endpoints; avoid user enumeration.
- **Errors/logging**: no sensitive data in errors or logs; generic messages externally.
- **Frontend**: CSP, avoid `dangerouslySetInnerHTML`/`v-html` with untrusted data, guard against CSRF.

## In review
- Treat security as a first-class review criterion, alongside correctness and extensibility.
- Check the OWASP Top 10 classes relevant to the change (access control, injection, auth, misconfig, SSRF, etc.).

## In QA (tester)
- Include security checks in acceptance: authz boundaries, invalid/expired tokens, rate limits, no enumeration, input fuzzing on key fields.
- File security defects with appropriate severity.

## After release — ongoing (devops-led)
- Monitor dependencies and base images for new CVEs; patch/upgrade on a cadence (and urgently for criticals).
- Keep TLS/config hardened; review access and secrets periodically.
- Re-evaluate when the threat landscape or dependencies change — the goal is that security does not degrade over time.

## AI / agent features (when the work uses an LLM or ships an agent)
Non-deterministic systems add a distinct attack surface — apply these on top of the above whenever a feature calls an LLM, runs model-generated code, or exposes an agent. See `docs/references/agent-engineering/` (Day 4).
- **Treat the prompt as source code.** System instructions and tool definitions are security-relevant; untrusted input (user text, retrieved docs, web pages, repos) can carry **prompt injection**. Don't let model output decide a privileged action unchecked.
- **Sandbox generated/executed code.** Run model-generated scripts in an ephemeral, network-isolated, low-privilege sandbox — never directly on the host with ambient credentials. Contain the blast radius.
- **Supply chain — guard against hallucinated packages ("slopsquatting").** LLMs invent plausible package names that attackers pre-register as malware. Verify every dependency an agent adds against a real, vetted source; pin versions; scan (SCA/SBOM) in CI before it reaches production. (See `cicd-pipeline`.)
- **Zero ambient authority / least privilege over time.** Give an agent a dedicated, scoped identity and short-lived, just-in-time credentials for the exact resources a task needs — not a broad standing key. Deny-by-default on file/secret/production access.
- **Human-in-the-loop for high-stakes, irreversible actions** (prod deploys, schema changes, payments, sending messages, IAM changes): require explicit human sign-off on a plain-language summary of what will happen — not a blind "approve." Beware approval fatigue from too many trivial gates.
- **Don't trust the client.** AI-built apps often push secrets, auth, or access flags to the frontend by default; keep them server-side (this reinforces the secure-coding rules above).
- **Observe the trajectory.** Log tool calls and reasoning steps for agent features so a drift/abuse (or a runaway loop — "denial of wallet") is detectable. Pairs with `observability`.

## Documentation
- Record security-relevant decisions as ADRs; note residual risks and follow-ups so they aren't forgotten.
