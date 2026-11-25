# Local agent packs

Committed, byte-identical copies of the upstream IstiN/dmtools-agents release
zips that the machine-loop runners in `.dmtools/runners/` consume. They let
this repo run its LEG packs (bug/story development, pr review, pr rework)
from LOCAL files instead of resolving `<agent>@latest` against the
DMTOOLS_PACK_REGISTRY — which is what enables future custom modifications of
agent behavior without forking the upstream release machinery.

| Pack | Version | Upstream source |
|---|---|---|
| `bug_development-0.1.369.zip` | 0.1.369 | release `agents-rel-20261124-152823` |
| `story_development-0.1.369.zip` | 0.1.369 | release `agents-rel-20261124-152823` |
| `pr_review-0.1.370.zip` | 0.1.370 | release `agents-rel-20261124-152823` |
| `pr_rework-0.1.369.zip` | 0.1.369 | release `agents-rel-20261124-152823` |

Each `<agent>-<version>.zip` ships with a `<name>.sha256` sidecar recorded at
download time. The committed zips are 1:1 upstream artifacts — verify with:

    shasum -a 256 -c .dmtools/packs/<agent>-<version>.zip.sha256

## How the runners resolve these

The pack resolver (epam/dmtools-dart `lib/src/pack/agent_pack_resolver.dart`)
accepts three `parent.path` forms:

1. `<agent>@<version|latest>` — registry lookup via `DMTOOLS_PACK_REGISTRY`
2. `https://…/<agent>-<version>.zip` — direct HTTPS download
3. a **local `.zip` file path** — `File(base).existsSync()`, resolved against
   the process CWD (the repo root when dmtools runs here)

The runners now use form 3 with repo-relative paths (e.g.
`.dmtools/packs/bug_development-0.1.369.zip`). Local paths bypass the
registry entirely; no network is touched at pack-resolve time. The resolver
still verifies the zip internally: it reads the embedded `manifest.json`,
unpacks, and checks every manifest-listed file's sha256 and mode, with a
64 MiB per-entry cap. (The sibling `.sha256` sidecar is only fetched for
HTTP-downloaded packs; for local zips it is kept purely as a provenance /
integrity record — verify manually as shown above.)

Prompts referenced as `pack:instructions/…` in the runners resolve against
the unpacked pack, so a custom zip must carry any dir it references (the
compiler `--include` flags below do that).

**What stays upstream:** the SM engine pack (`sm_github`) and the frozen
workflows (IstiN/dmtools-agentic-workflows) still resolve from upstream
releases — only the LEG packs above are pinned locally. Do not repoint the
frozen workflows' pack source.

## Custom pack procedure (modify an agent, rebuild, ship)

Prereqs: `dmtools` CLI installed (compile subcommand comes from
epam/dmtools-dart), a checkout of the agent sources (upstream
IstiN/dmtools-agents, or your fork of it), and the `instructions/` +
`prompts/` dirs present in that checkout.

1. **Edit the agent sources** in your dmtools-agents checkout — e.g.
   `bug_development.json`, `instructions/bug_development/*.md`,
   `prompts/…`. Keep the entry JSON's shape (`entry`, prompts, verdict
   rules) intact unless you also update the runner params here.

2. **Pick a version that cannot collide with a shipped upstream version.**
   The release ledger is append-only: re-publishing different content under
   an already-shipped version is what upstream guards against
   (gh-812). Use the next free version (`versions.json` in the agents
   checkout maps agent → current version) or an explicit local scheme.
   For a single-agent local build just pass `--version`:

       cd <dmtools-agents-checkout>
       dmtools compile bug_development.json \
         --agent-root . \
         --version 0.1.370 \
         --out dist \
         --include instructions \
         --include prompts

   This is exactly what upstream's `ci/release_packs.mjs` runs per agent
   (release workflow `agent-pack-release.yml`); `dmtools compile` is the
   single implementation of the pack format (dm.ai#595). It writes
   `dist/<agent>-<version>.zip` with an embedded `manifest.json`
   (per-file sha256 + mode inventory, `sourceCommit`, `defaultEntry`) and
   the `.sha256` sidecar.

   To rebuild SEVERAL agents with the ledger versions:
   `node ci/release_packs.mjs --agents=bug_development,pr_review --out dist --dry-run`
   (dry-run builds + validates without publishing anything).

3. **Validate the zip against its manifest** (compile already self-verifies,
   but check the artifact you are about to commit):

       unzip -l dist/<agent>-<version>.zip           # manifest.json + entry json present
       shasum -a 256 -c dist/<agent>-<version>.zip.sha256

4. **Copy the zip + sidecar into this dir, names untouched**
   (`<agent>-<version>.zip` — the runner path and the manifest must agree):

       cp dist/<agent>-<version>.zip* <this-repo>/.dmtools/packs/

5. **Bump the runner(s)**: edit `parent.path` in the affected
   `.dmtools/runners/fa-*.json` to the new `.dmtools/packs/<agent>-<version>.zip`.

6. **Commit on a branch** (zip + sidecar + runner diff together — one PR per
   pack swap keeps the audit trail readable). Never push to `main` directly;
   open a PR so the machine loop's own CI exercises the new pack.

### Gotchas

- Paths are resolved against the **repo root** (CWD contract) — keep them
  repo-relative exactly as the current ones are.
- `pack:` references in the runner configs (e.g.
  `pack:instructions/common/github_comment_format.md`) must exist inside the
  new zip; dropping an `--include` dir breaks the leg at launch.
- Keep `.sha256` sidecars for every zip: they are the diff evidence that a
  custom zip differs from (or matches) upstream, and the first thing CI
  debugging will check.
- If you want an agent change to flow back upstream, mirror it in a PR to
  IstiN/dmtools-agents and drop the local pack once the upstream release
  ships it (flip `parent.path` back to `<agent>@latest`).
