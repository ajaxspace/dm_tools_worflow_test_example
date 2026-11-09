- Our machine identities (ai-teammate) hold only automation-scoped tokens; findings
  about secret scoping should check .dmtools/runners/*.json env blocks first —
  that is where credentials historically leaked in this organization.
- Workflow YAML changes are security-relevant in this repo even when the diff is
  small: check permissions blocks and untrusted-input interpolation on every
  .github/workflows/*.yml hunk.
