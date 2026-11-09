# `.dmtools/review/` — repo-defined reviewers + prompt extensions

One `<name>.json` in this directory defines ONE specialized reviewer for this
repository. The factory's pool loader reads factory-built-in reviewers (base,
security — defined in dmtools-agents, not overridable here) PLUS every file here.
You never fork dmtools-agents to add a reviewer — drop a file, enable in
`.dmtools/config.js`, done.

## Minimal form — a reviewer is TWO required fields

There is no "minimal mode" and no reduced agent: every skill file defines a full
reviewer. What is minimal is the **authoring effort** — the loader fills every
unspecified field with its default, so the smallest complete definition is:

```json
{ "name": "a11y", "lens": ".dmtools/review/a11y.md" }
```

= a full accessibility reviewer: runs every round, enabled, filtered, non-required,
normal filter weight, may raise any tier incl. 🚨, any path. Byte-identical in
behavior to the fully explicit form of the same values. Write more fields only when
you want to deviate from a default.

The worked example below (`legal.json`) keeps only the fields that differ from
defaults.

Base schema = **universal fields only**, and almost nothing is mandatory:
**required = `name` + `lens` only** (`roleLine` derives from `name`). Defaults are
the safe general behavior; restrictions are explicit. Reviewer-specific fields
ride the opaque `options` object — the loader passes it through untouched; the
lens owns its interpretation. Booleans take the `is` prefix.

| field | default | meaning |
|---|---|---|
| `name` | **required** | reviewer id (used in census attribution + packet) |
| `lens` | **required** | path to this reviewer's instruction markdown (repo-authored — your judgment calls live here) |
| `roleLine` | derived from `name` | the persona line placed first in the prompt |
| `mayRaise` | all tiers (no limits — 🚨 included) | tiers this reviewer's specification allows; the citation discipline rides the base contract every reviewer gets, so 🚨 claims stay evidence-bound regardless of the lens |
| `filterWeight` | `"normal"` | `high` = the filter leg may not silently drop this reviewer's candidates (demote/drop needs a stated reason and surfaces in the packet) — specialist suggestions outrank code-improvement candidates |
| `isFiltered` | `true` | `false` = candidates bypass the filter leg entirely |
| `isRequired` | `false` (factory: base + security `true`) | **merge gate**: PR cannot merge without this reviewer's PASS marker on the CURRENT head; failed leg retries then escalates to the owner — never silent merge (per-repo configuration) |
| `rounds` | `["all"]` | **array of flags**: `["first"]` initial review only — **counts COMPLETED passes, not attempts: a failed leg (429/timeout) re-fires next round until its completion marker exists** (budget-bounded, then owner escalation) · `["hunks"]` only re-runs when new hunks touch `triggerPaths` · `["first", "hunks"]` = full pass up front + trigger-gated re-runs near merge · `["all"]` every round. `["all"]` vs `["first","hunks"]`: they differ only on (a) rounds whose new hunks miss `triggerPaths` and (b) rounds with no new hunks at all (no-code-change re-reviews) — `all` re-runs there, `first+hunks` skips (nothing new to find; the registry would dedup re-finds). With empty `triggerPaths` the two are identical except zero-hunk rounds. Composable flags, not string enums — new flags slot in later |
| `triggerPaths` | `[]` (any new hunk; security ships `[]` — no path limitation) | substrings gating the `hunks` re-runs |
| `options` | `{}` | per-reviewer extras, loader passes through (legal: `docsSources`, `isQuestionsOnlyWithoutDocs`; security: `referencePack`) |
| `model` | `null` | model override or factory default |
| `isEnabled` | `true` | `false` = disabled (stated in the review summary/packet every round — loud, not silent) |

## Extending base or security — append, never replace, never a new agent

Repo-specific rules for an EXISTING reviewer are **append files**: the loader
assembles `[roleLine → base contract → factory lens → repo append files → factory
few-shots + verdict rules]`, so the repo rule lands in the same reviewer context —
one census attribution, no self-duplicating threads. Wire them in
`.dmtools/config.js`:

```js
promptAppend: {
  base:    ['.dmtools/review/base.append.md'],
  security: ['.dmtools/review/security.append.md']
}
```

A NEW file in this directory is only for a NEW domain (different lens = different
specialist). Contract files (output schema, verdict rules, census rules, registry
protocol) are factory invariants: no repo can replace or remove them.

## Where defaults live, and how appends are decided

**Defaults are never copied into your repo.** Base + security skill files, lenses
and reference packs live in dmtools-agents, versioned with it and resolved like the
existing runner parent (`pr_review@latest`). A fresh repo gets base + security
(enabled) with an EMPTY `.dmtools/review/` — this directory holds only additions:
new-domain reviewers and per-reviewer tuning. A same-name file here (e.g.
`security.json`) tunes the factory reviewer's non-contract fields (`isEnabled`,
`rounds`, `triggerPaths`, `options`, `model`) — contract files and the lens stay
factory-owned.

**Security default = no path limitation** (`triggerPaths: []`): a vulnerability does
not care which directory the hunk lives in — security runs on every round with any
new hunk. Narrowing is an owner override (quota pressure), never the factory
default.

**Appends are decided by the config key, not the file name**:
`promptAppend.<reviewerName>: [repo file paths]` — the key names the target
reviewer; file names in the array are free. Explicit and greppable beats convention
scanning. Consumer: the pool loader's prompt assembly (factory change, assumed
present per the pool rollout) — nothing reads `promptAppend` today.

## `rounds` in practice — why the lawyer wants `["first", "hunks"]`, not `["all"]`

A lawyer does not care about tests. Give him `triggerPaths` that name the product
surface (`lib/`, `src/`, plus domain keywords) and `["first", "hunks"]` — then a
review-driven rework lap that only fixes tests **does not wake him**, while `["all"]`
would re-run him on a synthetic-fixture diff: a wasted pass that mostly mints noise
(fake users, fake tokens — new fixtures = new claims, registry dedup or not).

Worked example — PR "add payment with consent", legal configured as in
`legal.json` (`["first", "hunks"]`, triggerPaths incl. `lib/`):

| round | what changed | `["all"]` | `["first", "hunks"]` |
|---|---|---|---|
| 1 — initial | `lib/pay.js`, `lib/consent.js`, `test/pay.test.js` | runs | **runs** (`first`) — full pass: consent gate before charge, telemetry disclosure, terms link |
| 2 — rework: tests only | `test/pay.test.js` expanded | runs — test fixtures with fake users/tokens → wasted pass, noise risk | **skipped** (no `lib/` hunk) |
| 3 — rework: product code | `lib/gdpr.js` (deletion endpoint) | runs | **runs** (`hunks` matched `lib/`) — verifies right-to-erasure |
| 4 — re-review, threads resolved by replies (no code change) | — | runs → re-finds the same things → registry dedups → pure waste | **skipped** (zero new hunks) |

Net: same legal coverage on the rounds that matter (1 and 3), two passes saved on
the rounds that cannot produce anything real. The contrast with the **security
reviewer** teaches the config philosophy: security ships `triggerPaths: []` because
a vulnerability does not care about paths — it runs on every hunk-bearing round
(1, 2, 3, 4-with-hunks; test-only diffs can hide hardcoded credentials too), while
the lawyer's surface is genuinely path-scoped. Each reviewer's
`rounds` + `triggerPaths` encode its domain; the factory default for any NEW
specialist is `["first", "hunks"]` + the narrowest honest triggerPaths.

Flip side to keep in mind: if your product code lives at the repo root (no `lib/`),
`triggerPaths` must be domain keywords only — and a test-only rework lap WILL match
keywords that appear in test names (`test/consent_flow.test.js` matches `consent`).
That is acceptable (the lens + base rules already say fixtures are synthetic), or
narrow with path-shaped entries and drop bare keywords.

## Hunk rounds — how a reviewer knows what is "new"

The machine computes the diff-of-diff (`git diff <lastReviewedHead>...HEAD`, head
read from the verdict/registry markers) into `pr_new_hunks.txt` — changed files +
hunk line ranges. The reviewer's input: `pr_new_hunks.txt` (what is new) + full
file contents (context) + the frozen-code rule. Enforcement is mechanical: an
inline finding must anchor to a line inside the new hunks — findings anchored on
unchanged code go to the advisory digest. Unknown head → fail-open to full pass.

## Every reviewer produces candidates — never a verdict

Regardless of reviewer count, there is ONE census and ONE machine-recomputed
verdict per review round. The filter leg merges base + specialist candidates
(dedup, `keep | demote | drop` — weighted reviewers cannot be silently dropped).

## Validation (free, deterministic — no agent)

Run `node .dmtools/review/validate-review-skills.js` from the repo root — it
checks every skill file here against the schema (universal fields, types, tier /
rounds flags, `is`-prefix booleans), that lens files exist and are non-empty, the
citation-discipline hint when `mayRaise` includes BLOCKING, duplicate reviewer
names, factory-reviewer tune-don't-redefine, enablement ↔ skill-file consistency,
and `promptAppend` targets/files. `✅ valid` / `❌ INVALID` exit codes — wire it
into repo CI next to the docs-coverage gate. (Factory-shipped in
dmtools-agents `scripts/`; this copy demonstrates the worked example.) It proves
the configuration is well-formed and loadable; whether a lens is any GOOD remains
the filter leg's (agent) job.

## Example in this directory

- `legal.json` + `legal.lens.md` — consent/privacy/terms reviewer
  (`rounds: first+hunks`, high filter weight, questions-only without docs).
- `base.append.md` — repo rules appended to the base reviewer.
- `security.append.md` — repo rules appended to the factory security reviewer.
