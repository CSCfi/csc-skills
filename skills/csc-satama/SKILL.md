---
name: csc-satama
description: >
  Use Satama, CSC's Harbor-based container image registry (satama.csc.fi),
  correctly and safely. Invoke for pushing/pulling/tagging container images
  with docker or podman; logging in with a personal CLI secret or a robot
  account (username `robot@<project>+<name>`); configuring a Satama project
  (public/private visibility, quota, vulnerability scanning via Trivy, SBOM
  generation, CVE allowlist, tag immutability, tag retention, deployment
  security / image signing with cosign or Notation); managing project
  members/roles or robot accounts; reading audit logs; or troubleshooting
  errors like "unauthorized", "denied: requested access", or a push blocked by
  tag immutability. Can create new resources (robot accounts, images under new
  tags, protective policies) with disclosure of billing (Cloud BU/GiBh) and
  public-visibility exposure, but treats overwriting a tag, deleting
  images/tags, and enabling tag-retention auto-deletion as the avoid-zone —
  writes reviewable steps/scripts for those instead of running them.
---

# CSC Satama (container image registry)

Satama is CSC's **container image registry**, built on **Harbor**
(<https://goharbor.io/>). It stores, scans and distributes OCI container
images for cloud and HPC workloads. Registry and web UI share one hostname:
**`satama.csc.fi`**.

This skill helps you (a) write correct `docker`/`podman` commands and Harbor
policy configuration and (b) advise on the mechanics, with CSC-specific
quirks built in.

## Operating rules (read first)

1. **Safety tiers — the same non-clobbering test as the other CSC skills:**

   - **Read-only** — always OK: `docker pull`, `docker images`, browsing the
     web UI, viewing vulnerability/SBOM reports, listing robot accounts or
     members, reading audit logs (**Logs** in the sidebar, or a project's
     **Log** tab).
   - **Creating new, non-clobbering resources** — OK after disclosing the
     effect: pushing an image under a **tag that doesn't exist yet**, creating
     a robot account, adding a project/global label, adding a CVE-allowlist
     entry, adding a tag-immutability rule (it only *blocks future overwrites*,
     it deletes nothing). Disclose storage cost (Cloud BU/GiBh — see
     `concepts.md`) and, for a **public** project, that anonymous users can
     then pull (never push) without authentication.
   - **Avoid-zone — write a reviewable script/steps, don't run on your own
     initiative:**
     - **Pushing to an existing tag is create-or-REPLACE**, not a create —
       Harbor overwrites the manifest a tag points to, silently, unless tag
       immutability blocks it (same reasoning as Allas object `PUT`). Warn
       before reusing a tag that's already deployed somewhere.
     - **Deleting a tag/image** (the UI "Remove Tag" flow) — irreversible from
       the user's side (the underlying blob is GC'd later); anything still
       running from that tag breaks.
     - **Enabling a tag-retention rule** — unlike immutability, this
       configures Satama to **automatically and repeatedly delete tags** on a
       schedule (e.g. "keep latest 10", "delete tags older than 30 days").
       Upstream itself warns tags removed this way are deleted automatically
       and permanently with no further confirmation and cannot be recovered —
       treat it as avoid-zone exactly like Rahti's `oc delete`/`oc scale`:
       state plainly what the rule will delete and how often before it's
       turned on.
     - Changing a member's role, deleting/re-scoping a robot account,
       **refreshing a robot account's secret** (invalidates the old one —
       anything still using it breaks immediately), or flipping a project
       from private to public are **modifications of a live resource** —
       same treatment.

2. **Project-member permission changes are temporary.** Anyone with project
   access starts as **Project Admin** by default, and admins can change roles
   in **Members** — but Satama runs a **periodic sync process that can
   silently revert manual role changes**. Don't promise a role change is
   durable; if it needs to stick, say so and suggest confirming after the next
   sync.

3. **Prefer a CLI secret or a robot account over a personal Web UI password**
   for `docker`/`podman login` — the UI password expires with the session and
   isn't meant for automation. **Robot accounts** (`robot@<project>+<name>`)
   are the CSC-recommended path for CI/CD and any unattended push/pull: scope
   them to the minimum actions needed, set an explicit expiration unless there's
   a reason not to, and copy the generated secret immediately — **Satama shows
   it once and cannot redisplay it.**

4. **No `csc_project:` accounting field to set, unlike Rahti/Pouta.** A Satama
   project exists once the Satama service is **activated for a CSC project**
   (apply via the CSC project's service-access page); billing then follows
   automatically from that link — there's nothing to type into a description.
   If a user can't see an expected project, the likely cause is the service
   isn't enabled yet on that CSC project, or (for a *newly* accessible one)
   it hasn't propagated — allow up to 15 minutes after first login.

5. **Avoid the `latest` tag for anything production-bound** — it's the
   classic Satama footgun the docs themselves warn about (it's mutable and
   reproducibility breaks). Use explicit versions, release identifiers, or
   commit SHAs.

## Quick start: common requests

- **"Push my image to Satama."** Build → tag as
  `satama.csc.fi/<project>/<image>:<tag>` → log in (CLI secret or robot
  account) → `docker push`. Warn if `<tag>` already exists in that repo
  (overwrite, rule 1). See `code-patterns.md`.
- **"Set up CI to push automatically."** Create a **robot account** scoped to
  just that project with push (and pull, if needed) permission; use it as
  `-u robot@<project>+<name>` in `docker login`. Never use a personal CLI
  secret in a shared pipeline.
- **"Make my project public."** Disclose: anonymous users can then `pull`
  (never `push`) without logging in. Recommend keeping production/sensitive
  images **private** (the default).
- **"Turn on vulnerability scanning / SBOM generation."** Both are
  Configuration-tab toggles ("Automatically scan images on push" /
  "Automatically generate SBOM on push"), or a one-off manual trigger per
  image — safe to enable, no data at risk.
- **"Block deployment of vulnerable or unsigned images."** Deployment
  Security lets you require **cosign/Notation** signatures and set a
  severity threshold that blocks running images at/above it — note the
  threshold is inverted from intuition: choosing **Low** is the *most*
  restrictive (blocks on any finding).
- **"Clean up old tags" / "set up automatic cleanup."** A one-off deletion or
  a standing retention rule are both avoid-zone (rule 1) — write out exactly
  which tags/rule and get confirmation first; point out the retention-policy
  alternative to manual deletion but flag it as a recurring auto-delete once
  enabled.
- **"I'm getting `unauthorized`/`denied: requested access`/a push rejected by
  tag immutability."** These are the known, common Satama errors — see the
  troubleshooting table in `concepts.md` before guessing.

## Reference material

- `references/concepts.md` — access & roles (incl. the permission-sync
  gotcha), billing & quota, project configuration surfaces (visibility,
  scanning, SBOM, CVE allowlist, deployment security, tag immutability/
  retention, labels), audit logs, and a troubleshooting table for the
  documented known issues.
- `references/code-patterns.md` — login/tag/push/pull commands (personal
  secret and robot account), robot-account creation, a Rahti/Pouta deploy
  hookup, and the avoid-zone operations (tag deletion, retention rules,
  visibility/role changes) written as reviewable steps.

When advising on mechanics, prefer these notes over memory; if something here
is silent on a detail, say so rather than inventing CSC-specific behaviour.
