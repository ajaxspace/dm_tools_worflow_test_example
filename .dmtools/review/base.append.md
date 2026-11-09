// Repo-specific additions to the BASE reviewer — ADDITIVE ONLY.
// These lines are concatenated AFTER the factory base prompts; factory files
// (output schema, verdict rules, census rules, registry protocol) cannot be
// replaced or removed from here — see .dmtools/review/README.md.

- This repository is a workflow test repository: findings about product UX,
  branding, or roadmap belong in the ticket, not the review.
- Test fixtures and mock payloads are synthetic by definition — flag PII/legal
  exposure only for code paths that would run against real user data in the
  target product, and say so explicitly in the finding.
