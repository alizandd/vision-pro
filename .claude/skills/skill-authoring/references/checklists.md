# Skill-Authoring Checklists & Templates

Loaded on demand from [`../SKILL.md`](../SKILL.md). Source: Day 3 (Agent Skills),
Appendix A; security/eval from Day 4. See
[`docs/references/agent-engineering/`](../../../../docs/references/agent-engineering/README.md).

## Minimal SKILL.md template
Copy, adjust the placeholders, delete what you don't need.

```markdown
---
name: skill-name
description: |
  [What it does in one verb-led sentence.] Use this skill when the user
  [trigger phrase 1], [trigger phrase 2], or [trigger phrase 3].
  Do NOT use for [anti-trigger 1] or [anti-trigger 2] (that's `other-skill`).
---

# Skill Name

## When to use
- [Concrete scenario]

## When NOT to use
- [Out-of-scope scenario] → use `other-skill`

## Workflow
1. [Step]
2. See `references/advanced.md` for [edge case].

## Output format
- Use `assets/template.md` …

## Anti-patterns to avoid
- Don't […]
```

## Folder structure
```
skill_name/
├── SKILL.md        # Required: YAML frontmatter + the lean runbook
├── references/     # Optional: detail loaded on demand (this file is one)
├── scripts/        # Optional: deterministic helpers (run, don't paste as prose)
└── assets/         # Optional: templates/schemas used in output
```

## Naming
- Skill name: **kebab-case**; directory may be snake_case if it carries scripts.
- Prefer a clear noun phrase or gerund (`code-review`, `api-conventions`, `processing-pdfs`) — match the existing repo style.
- Avoid generic names (`helper`, `utils`, `tools`, `data`), vendor prefixes (`claude-*`, `gemini-*`), and internal jargon outsiders won't recognize.

## The description field
- State **what it does** AND **when to use it**; front-load trigger keywords.
- Include a **when-NOT-to-use** clause naming the adjacent skill that owns the excluded case.
- Describe actual behaviour, not aspirational. Be pushy if the model under-triggers.
- ≤ ~1024 chars in YAML; ~50 words of substance is typical.

## Eval coverage checklist — all four required
- [ ] **Trigger** — positive AND negative test phrases; ~90% routing accuracy.
- [ ] **Execution** — correct output across a representative range of inputs.
- [ ] **Regression** — adding it drops nothing in the existing library's routing.
- [ ] **Token budget** — co-loaded with 5–15 active skills, no degradation on unrelated turns.

Any failure → skill stays at the **draft tier**.

## Skill smells (revise if you see these)
- Over ~5,000 words → probably two skills, or reference material that belongs in `references/`.
- Two domain teams could plausibly own it → not yet decomposed; split along team boundaries.
- You can't write three test cases for it → description too vague / does too many things.
- It references no other resource → may just be a system-prompt line, not a skill.
- Description starts with "a helpful skill for…" → rewrite: name the trigger, inputs, output.

## Deployment checklist (before shipping / bumping VERSION)
- [ ] Frontmatter valid; description has what + when + when-NOT.
- [ ] Body lean; detail pushed to `references/`, deterministic work in `scripts/`.
- [ ] Eval coverage (the four above) satisfied for the skill's tier.
- [ ] Security clean: no secrets, no hard-coded paths, no untrusted deps (Day 4).
- [ ] For a new domain skill: specialist agent added, `CLAUDE.team.md` + `Conventions` list updated, `VERSION` bumped, ADR recorded.

## One-line mental model
System prompt = instinct. AGENTS/CLAUDE.md = project README. Tools/MCP = hands.
RAG = library. **Skills = the runbook the experienced colleague hands you on day one,
and that the agent never forgets.**
