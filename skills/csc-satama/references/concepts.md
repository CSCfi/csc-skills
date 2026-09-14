# Satama concepts & CSC quirks

Source: CSC user guide (`cloud/satama/`). Satama is CSC's Harbor deployment
(<https://goharbor.io/>) — standard Harbor mechanics apply except where noted
below. Web UI and registry share one hostname: **`satama.csc.fi`**.

## Access & roles

- Requires a **CSC user account**, **MFA** at login, and a **CSC project with
  the Satama service enabled** (apply via the CSC project's service-access
  page; see `../../accounts/how-to-add-service-access-for-project.md` in the
  user guide). Logging in to `satama.csc.fi` for the first time auto-creates a
  Satama username. Only the **`library`** project is visible immediately;
  other enabled CSC projects appear **after up to ~15 minutes**. A CSC
  project shows up in Satama's UI as `project_XXXXXX`, where `XXXXXX` is the
  MyCSC project number.
- Anyone with access to a CSC project starts with **Project Admin** on its
  Satama project. Roles, least to most privileged: **Limited Guest** (pull
  only, no logs/members view) → **Guest** (read-only, retag+pull) →
  **Developer** (push+pull) → **Maintainer** (+ scan images, view
  replication jobs, delete images/Helm charts) → **Project Admin** (+ manage
  members/roles/settings, start scans). **Anonymous** users get read-only
  access to **public** projects only.
- **Manual role changes can be silently reverted.** Satama runs a periodic
  sync process that can override role edits made in the **Members** tab —
  don't treat a role change as permanently durable without checking it stuck.
- A user unable to push/scan/see something is almost always a **role**
  problem, not a bug — direct them to their project admin.

## Billing & quota

- **Storage only** is billed, at **1 Cloud BU per GiB·hour** (24 BU/GiB/day),
  metered in 1-hour increments. Ten GiB stored ≈ 10 Cloud BU/hour. Estimate
  with the BU calculator (<https://research.csc.fi/resources/#buc>); rates are
  indicative — see the general Billing docs for current numbers.
- **Default quota is 50 GB per (Satama) project.** Increases are **not
  self-service** — go through CSC Service Desk, case-by-case.
- No accounting label to set (contrast Rahti's `csc_project:` description
  field) — a Satama project's billing follows automatically from whichever
  CSC project had the service activated for it.

## Project configuration surface

All of the below live under a project's tabs in the web UI (**Configuration**
unless noted); changing them requires **Project Admin**.

- **Visibility** — Public/Private checkbox, **private by default**. Public =
  anyone with network access can pull without authentication; **anonymous
  push is never allowed** even on a public project. Keep production/sensitive
  images private.
- **Vulnerability scanning** — engine is **Trivy**. Toggle "Automatically
  scan images on push", or trigger manually per image (**Vulnerabilities**
  tab → scan button). Severities: Critical/High/Medium/Low, with affected
  packages and suggested fixes.
- **SBOM generation** — toggle "Automatically generate SBOM on push", or
  trigger manually per image; view from the image's details page. Upstream
  docs don't name a specific SBOM format (e.g. SPDX/CycloneDX) or an export
  path — don't assume one.
- **CVE allowlist** — suppresses specific CVEs from blocking, at **system**
  scope (global, Satama-admin-managed) or **project** scope (`ADD` a CVE ID,
  or `COPY FROM SYSTEM`), each entry with an expiration date or "Never
  expires". Meant for vulnerabilities that are temporarily unpatchable /
  not exploitable in context / functionally irrelevant — not a general
  scanning bypass; prefer an expiry over "never" unless there's a stated
  reason.
- **Deployment security** — two independent gates: require images be signed
  (**cosign** or **Notation**) before they can be deployed; and/or "Prevent
  vulnerable images from running" with a severity dropdown — **choosing the
  lowest severity (Low) is the most restrictive setting**, since it blocks on
  any finding at or above Low (i.e. everything). Upstream docs don't describe
  how this gate wires into an actual Rahti/Pouta deployment pipeline — don't
  invent integration mechanics that aren't documented.
- **Tag immutability** (**Policy** tab → Add rule) — marks matching tags so
  they **cannot be overwritten or modified** after creation. This is a
  protective, non-destructive control (it deletes nothing) — safe to add.
  Note this is also why a `docker push` can suddenly fail with "policy
  prevents tags from being modified" (see Known issues below).
- **Tag retention** (**Policy** tab → Add rule) — the *destructive*
  counterpart: define rules like "keep the latest 10 tags", "delete tags
  older than 30 days", or "keep tags matching `release-*`", and Satama
  **automatically deletes** whatever doesn't match, on an ongoing schedule.
  Upstream itself warns that tags removed this way are deleted
  **automatically and permanently, with no further confirmation, and cannot
  be recovered** — treat enabling/editing a retention rule as an avoid-zone
  action (SKILL.md rule 1).
- **Labels** — **Global** labels (usable by any project) can only be
  created/edited/deleted by **system administrators**; **Project** labels are
  managed by project admins (and system admins). A project admin asking for a
  new global label needs Service Desk / a system admin, not a self-service
  path.
- **Robot accounts** — see `code-patterns.md`; the CSC-recommended
  credential for CI/CD and any automation.
- **Repository descriptions** — a project admin can document a repository's
  purpose (base image, intended use, deployment notes): open the repository →
  **Info** tab → **Edit** → enter description → **Save**. Non-destructive,
  safe to do freely.
- **Webhooks** and **P2P Preheat** tabs also exist per project (notify
  external systems on registry events; speed up image distribution,
  respectively) — upstream gives no further configuration detail for either,
  so don't invent mechanics beyond "the tab exists."

## Audit logs

- System-wide: **Logs** in the left sidebar. Project-scoped: a project's
  **Log** tab. Logged events: login attempts, image push/pull, project
  create/delete, permission changes, configuration updates. **No retention
  period is documented upstream** — don't assert one.

## Known issues (documented upstream — check here before improvising a fix)

| Symptom | Likely cause | Fix |
|---|---|---|
| `unauthorized: authentication required` | Client isn't authenticated, or the session/CLI-secret expired | Re-run `docker login satama.csc.fi`; if using the web UI's session, log out/in there first to refresh, then re-authenticate the CLI |
| `denied: requested access to the resource is denied` on push | Not a project member, or role lacks push (e.g. Guest) | Ask the project admin for Developer role or above |
| Push fails after previously succeeding, referencing tag policy | **Tag immutability** rule matches that tag | Push under a new tag instead of reusing the old one |
| `docker login satama.csc.fi` fails outright | Wrong username/secret, expired credential, or connectivity | Re-check the registry hostname and credential validity |
| `repository does not exist` on pull | Wrong project/repository name, or the tag was never pushed | Verify the exact reference in the Satama web UI first |

## Best practices worth surfacing proactively

- Organize repositories by application/microservice/environment so images
  stay discoverable.
- Grant **Developer** (push) only to those who need it; leave others at
  **Guest** — limits accidental overwrites, on top of tag immutability.
- Use **robot accounts**, not personal credentials, for any automation.
- Use the **CLI secret**, not the web UI password, for `docker`/`podman
  login` — the UI session token expires independently and causes confusing
  "unauthorized" errors.
- Avoid the **`latest`** tag for production; use explicit versions, release
  IDs, or commit SHAs.
- Review vulnerability reports regularly; fix High/Critical findings before
  promoting an image to production.
- Remove unused tags (manually, or via a reviewed tag-retention rule) to
  control storage cost.
