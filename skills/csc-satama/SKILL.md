---
name: csc-satama
description: >
  Use Satama, CSC's Harbor-based container image registry (satama.csc.fi),
  correctly and safely. Invoke for docker/podman login, tag, push or pull
  against satama.csc.fi; personal CLI secrets and robot accounts
  (`robot@<project>+<name>`); Satama project settings (public/private
  visibility, quota, Trivy vulnerability scanning, SBOM generation, CVE
  allowlist, tag immutability, tag retention, deployment security with
  cosign/Notation signing); project members, roles and audit logs; storage
  billing in Cloud BU; or errors such as "unauthorized", "denied: requested
  access" or a push blocked by tag immutability. Pushes new tags and creates
  robot accounts and policies after disclosing cost and public exposure;
  writes reviewable steps instead of running tag overwrites, deletions or
  retention rules.
---

# CSC Satama (container image registry)

Satama is a **Harbor** deployment at **`satama.csc.fi`** (registry and web UI
share the hostname). Standard Harbor mechanics apply. This skill carries only
what is CSC-specific or where a model's default answer is wrong.

## Operating rules (read first)

1. **Safety tiers, the same non-clobbering test as the other CSC skills:**

   - **Read-only**, always OK: pull, list images, browse the web UI, view
     scan/SBOM reports, list members or robot accounts, read logs.
   - **Creating new, non-clobbering resources**, OK after disclosure: pushing
     to a **tag that does not exist yet**, creating a robot account, adding a
     label, a CVE-allowlist entry or a tag-immutability rule (immutability
     only blocks future overwrites and deletes nothing). Disclose storage
     cost (1 Cloud BU per GiB-hour, see `concepts.md`) and, for a **public**
     project, that anonymous users can then pull.
   - **Avoid-zone**, write reviewable steps and run only on explicit
     confirmation:
     - **Pushing to an existing tag is create-or-REPLACE.** Harbor silently
       repoints the tag unless an immutability rule blocks it (same reasoning
       as an Allas object `PUT`). Check whether the tag exists first.
     - **Deleting a tag or image**: not user-recoverable, and anything still
       deployed from that tag breaks.
     - **Enabling or editing a tag-retention rule**: a standing, scheduled
       auto-delete with no further confirmation prompt. State plainly what it
       will delete and how often before it is turned on.
     - Changing a member's role, deleting or re-scoping a robot account,
       refreshing a robot secret (the old one stops working at once), or
       flipping a project from private to public: live-resource
       modifications, same treatment.

2. **Role changes are temporary.** Everyone with access to the CSC project
   starts as **Project Admin**, and a periodic sync can silently revert role
   edits made in **Members**. Never promise a role change will stick.

3. **CLI credentials.** Log in with a personal **CLI secret** (User Profile
   in the web UI) or a **robot account**, never the web UI password. Robot
   usernames are **`robot@<project>+<name>`**, not Harbor's default
   `robot$<project>+<name>`. Secrets are shown once. On `unauthorized`,
   regenerate the CLI secret (or check the robot account's expiry) and log
   in again.

4. **No `csc_project:` accounting field, unlike Rahti and Pouta.** A Satama
   project appears once the Satama service is activated for the CSC project
   (MyCSC service-access page), and billing follows from that link. A missing
   project means the service is not enabled yet, or the roughly 15-minute
   sync after first login has not run.

5. **Avoid `latest` for production-bound images**; upstream warns about it
   explicitly. Use versions, release identifiers or commit SHAs.

## Quick start: common requests

- **"Push my image to Satama."** Tag as
  `satama.csc.fi/<project>/<image>:<tag>`, log in (rule 3), push. Warn if
  the tag already exists (rule 1). See `code-patterns.md`.
- **"Set up CI to push automatically."** A robot account scoped to that
  project with push (and pull if needed). Never a personal CLI secret in a
  shared pipeline.
- **"Make my project public."** Anonymous users can then pull, never push.
  Recommend keeping production or sensitive images private (the default).
- **"Block vulnerable or unsigned images."** Deployment Security in the
  project's Configuration tab: a cosign/Notation signature requirement and a
  severity threshold, where **Low** is the *most* restrictive choice.
- **"Clean up old tags" / "set up automatic cleanup".** Both avoid-zone
  (rule 1): write out exactly which tags or which rule, then get
  confirmation.
- **`unauthorized`, `denied: requested access`, push rejected by tag
  policy.** See the troubleshooting table in `concepts.md`.

## Reference material

- `references/concepts.md`: access and roles, billing and quota, CLI
  credentials, CSC-specific configuration notes, what upstream is silent
  on, and a troubleshooting table.
- `references/code-patterns.md`: login/tag/push commands for CLI secret and
  robot account, robot-account creation, and the avoid-zone operations as
  reviewable steps.

Prefer these notes over memory for CSC specifics. Where they are silent, say
so rather than inventing CSC behaviour.
