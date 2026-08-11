# csc-skills — how these skills are built and maintained

Working notes for whoever (Agent or human) produces or updates skills in this
repo. For install/layout aimed at *consumers*, see `README.md`; this file is
about *authoring*.

## What this repo is

An Agent Skills collection packaged as a Claude Code plugin marketplace and a
Codex skills-only plugin. Each skill is a directory under `skills/<name>/` and
is exposed to repository-aware harnesses through symbolic links under
`.agents/skills/`. Skills are loaded on demand when their `description` matches
the task, so the bundle stays cheap no matter how many skills it holds. Claude
Code installation is `csc-skills@csc-skills`; layout and the "add a skill"
mechanics are in `README.md`.

## Source of truth for CSC facts

The canonical source is CSC's **public user guide**:

- Repo: <https://github.com/CSCfi/csc-user-guide> (default branch `master`)
- Rendered: <https://docs.csc.fi>

Fetch a fresh local copy with **`scripts/sync-upstream.sh`** — it shallow-clones
(or updates) the repo into `.upstream/csc-user-guide/`, which is gitignored (a
research cache, never committed). Authoring and review read from there.

Which upstream docs back which skill:

| Skill | Upstream docs (under `.upstream/csc-user-guide/`) |
|---|---|
| `csc-allas` | `docs/data/Allas/` |
| `csc-pouta` | `docs/cloud/pouta/` (plus `docs/accounts/` for CSC-project/quota facts) |
| `csc-rahti` | `docs/cloud/rahti/` (plus `docs/accounts/` for CSC-project/quota facts) |
| `csc-roihu` | `docs/computing/` (esp. `systems-roihu.md`, `roihu-disk.md`, `running/`, `connecting/`, `usage-policy.md`, `lustre.md`, `hpc-billing.md`) plus `docs/support/tutorials/roihu*.md`; also two external repos: <https://github.com/CSCfi/certificate-helper-tool> (SSH certs) and <https://github.com/csc-training/csc-env-eff> (HPC practices) |

Rules:
- **Prefer the upstream docs over memory.** If they're silent on a detail, say
  so rather than inventing CSC-specific behaviour.
- **Verify capability claims against official docs** before relying on them
  (e.g. plugin-manifest features, S3 conditional-write support on Allas). Don't
  assert a service supports something without a source or a test.

## Anatomy of a skill

Three files, mirroring a "router + two halves" shape:

- **`SKILL.md`** — YAML frontmatter (`name`, `description`) then the body.
  - The **`description` is the trigger**: phrase it the way users phrase
    requests, and pack in the key nouns/verbs (service name, operations,
    product names like `a3s.fi`, `clouds.yaml`). It also states the safety
    posture in one line.
  - The **body is a router**: *Operating rules* first (always-in-context
    safety/defaults), then a *Quick start* for the common requests, then
    *pointers* telling the model which reference file to load when. Keep only
    always-needed material inline; push detail to references (progressive
    disclosure).
- **`references/concepts.md`** — the mechanics + CSC quirks. The "advise" half.
- **`references/code-patterns.md`** — ready-to-adapt code/commands. The
  "generate" half.

## Defaults & conventions

- **Prefer the long-term / CSC-recommended path, and say why** — Allas → **S3**
  (Swift is being deprecated); Pouta → **application credentials + clouds.yaml**
  (no CSC password, project-scoped, revocable). Always state the exception
  conditions (e.g. stick with Swift for a bucket already written via Swift).
- **Never hard-code, echo, log, or commit credentials/secrets.** (The `.gitignore`
  already excludes `clouds.yaml`, `*-openrc.sh`, etc.)
- **Cost/rate tables are indicative only.** Caveat them, and point at the live
  source (the BU calculator; `openstack flavor list`) for anything
  budget-critical. Rates and endpoints drift — these are the first things to
  re-check on a review.

## Safety model (the important part)

These skills **write code the user runs**; they are not a license to take
irreversible actions on the user's infrastructure. Posture by operation class:

- **Read-only inspection** — fine to run on request (lists, `show`, `info`,
  usage/quota).
- **Creating new resources** — allowed **when the create cannot silently
  destroy or overwrite anything**, and **always with clear disclosure of
  consequences** (cost in BU; network exposure). The discriminator is "is this
  create idempotent / non-clobbering?":
  - *Pouta*: general resource creation (VMs, volumes, security groups, floating
    IPs, keypairs) is OK after disclosing cost and exposure.
  - *Allas*: **bucket** creation is OK (a name clash just returns `409`, harmless),
    but an **object upload is create-or-REPLACE** — S3 `PUT` clobbers an existing
    key silently — so Allas stays conservative and writes a script for uploads
    rather than running them. (The safe way to make an upload a true "create" is
    a collision-proof key or a conditional `If-None-Match: *` PUT — left as
    future work.)
- **Modifying or deleting existing resources/data** — the **avoid-zone**. Write
  a **reviewable script**, state plainly what it does and the sharp edges
  (irreversibility, data loss, and that a CSC project is shared so the blast
  radius is everyone), and only run after explicit confirmation. Never
  bulk-delete or tear down on your own initiative.

Keep this model consistent across skills. If a skill needs to deviate, document
the reason inline (as Allas does for object overwrites).

## Producing a new skill

1. **Pick the service and find its upstream docs dir** (see the table above; if
   it's a new service, locate it under `.upstream/csc-user-guide/docs/`).
2. **Sync upstream:** run `scripts/sync-upstream.sh`.
3. **Research by fan-out.** When supported by the current harness, launch
   parallel exploration agents over the upstream docs, grouped by topic
   (concepts/billing, auth/CLI, networking/security, storage, …). Tell each to
   **preserve exact commands/URLs verbatim** and flag CSC quirks/warnings. Read
   the few most central files yourself. This keeps the research out of your
   main context while staying faithful to the source.
4. **Draft the three files** per the anatomy above.
5. **Wire it in:** new dir under `skills/`; add the relative symlink
   `.agents/skills/<name> -> ../../skills/<name>`; add a bullet to the README
   "Available skills"; add a row to the skill↔docs table above; refresh the
   plugin/marketplace `description`s if the repo's scope line changed. (Both
   plugin manifests auto-discover `skills/`, so no manifest edit is needed for
   the skill itself.)
6. **Validate** both plugin manifests, the skill symlinks, and **commit**.

## Reviewing skills against upstream

Run this on demand (e.g. ask your agent: *"review csc-pouta against
upstream"*). It is a **procedure for the agent to follow**, not a script:

1. **Sync upstream:** `scripts/sync-upstream.sh` (gets the latest docs into
   `.upstream/`).
2. **Re-extract current facts.** Fan out exploration agents over the skill's
   mapped upstream docs (see the table) and pull out, verbatim, the facts the
   skill encodes: commands, endpoint URLs/ports, auth flow, flavor/image names,
   billing/quota numbers, default protocol/auth choices, and any deprecations.
3. **Diff against the skill.** Compare those facts to the skill's `SKILL.md` and
   `references/*`. Pay special attention to the drift-prone items: **rate/billing
   tables, endpoint URLs, flavor/image names, default quotas, and
   deprecation/recommendation changes** (e.g. a protocol being retired).
4. **Emit a drift report — don't edit yet.** For each notable claim, mark it
   *accurate* / *changed (old → new)* / *removed upstream* / *newly available
   upstream*, and list anything in the skill no longer supported by the docs.
5. **Apply fixes** the user approves. When a fact or rule changes, **sync every
   place it's mirrored**: the frontmatter `description`, the quick-start bullets,
   the README blurb, and the `code-patterns.md` intro. (Grep the skill for the
   old phrasing.)
6. **Validate** JSON manifests and **commit**.

## Git / distribution

- Marketplace name = plugin name = `csc-skills` → `csc-skills@csc-skills`.
- The Codex plugin manifest is `.codex-plugin/plugin.json`; its `skills` path
  points to the same canonical `skills/` directory.
- `AGENTS.md` links to this file, and `.agents/skills/*` links to `skills/*`;
  do not replace those links with copied content.
- Remote: CSC GitLab (`origin`,
  `ssh://git@gitlab.ci.csc.fi:10022/soda/csc-skills.git`).
- End commit messages with the Claude `Co-Authored-By:` trailer.
