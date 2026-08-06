# Playbooks

A playbook is a written diagnostic procedure for a recurring kind of question — "why did
organic traffic drop", "why did a page stop ranking", "is this a tracking bug or a real
decline" — captured once so every analysis session doesn't reinvent the approach from
scratch. Claude Code reads these on demand; point it at one when the situation matches.

## Structure

Every playbook follows the same five sections:

- **Context** — when this playbook applies. What symptom or question triggers it.
- **Questions** — what you're actually trying to establish, stated as questions, before
  you touch any tool. This keeps the investigation aimed at a conclusion instead of a
  pile of numbers.
- **Queries** — the specific MCP calls to make, with the parameters that matter (date
  ranges, dimensions, filters). Concrete enough to run, not just "check GSC".
- **Interpretation** — how to read what comes back: which hypotheses each result
  supports or rules out, and in what order to rule them out. Order matters — cheap,
  high-probability explanations (broken tracking, bot traffic, seasonality) should be
  eliminated before expensive ones (ranking loss, algorithm updates).
- **Output** — what gets delivered at the end: usually a short note in the tenant's
  `analysis/` folder stating the supported hypothesis, the evidence for it, and what
  would falsify it.

## Adding a playbook

1. Copy `organic-traffic-drop.md` as a starting template.
2. Rename it to the question it answers (kebab-case, e.g. `new-page-not-indexing.md`).
3. Replace the content section by section, keeping the same five headings.
4. Keep it free of client data — placeholders only (`example.com`, generic page paths,
   round numbers). A playbook is shared across tenants; anything specific to one client
   belongs in that tenant's own `CLAUDE.md` or `analysis/` folder, not here.
