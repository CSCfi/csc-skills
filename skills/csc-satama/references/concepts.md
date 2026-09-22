# Satama concepts & CSC quirks

Source: CSC user guide, `docs/cloud/satama/` (rendered at
<https://docs.csc.fi/cloud/satama/>). Satama is a Harbor deployment at
`satama.csc.fi`; stock Harbor behaviour is assumed known and only the
CSC-specific facts and gotchas are recorded here.

## Access & roles

- Requires a CSC user account, **MFA**, and a CSC project with the **Satama
  service enabled** (apply via
  <https://docs.csc.fi/accounts/how-to-add-service-access-for-project/>).
  Web UI login is via HAKA or MyCSC.
- First login to `satama.csc.fi` creates the Satama user. Only the
  **`library`** project is visible at first; other enabled CSC projects
  appear after **up to about 15 minutes**. A CSC project shows up in
  Satama's UI as `project_XXXXXX`, where `XXXXXX` is the MyCSC project
  number, not under its MyCSC name.
- Everyone with access to the CSC project gets **Project Admin** on its
  Satama project by default. Harbor's standard role ladder applies (Limited
  Guest, Guest, Developer, Maintainer, Project Admin; pushing needs Developer
  or above).
- **A periodic sync can silently revert manual role changes** made in the
  Members tab. Treat any role edit as provisional and say so.

## Billing & quota

- **Storage only**, at **1 Cloud BU per GiB-hour** (24 BU per GiB per day),
  metered in one-hour increments. Indicative; use the BU calculator
  (<https://research.csc.fi/resources/#buc>) for anything budget-critical.
- **Default quota is 50 GB per Satama project.** Increases go through CSC
  Service Desk, case by case; not self-service.
- No accounting label to set (contrast Rahti's `csc_project:` field). Billing
  follows from the CSC project that activated the service.

## CLI credentials

- **Personal CLI secret**: click your username (top right) → **User Profile**
  → **CLI Secret** → **Generate New Secret**. Use it, never the web UI
  password, for `docker`/`podman login`.
- **Robot accounts** are named **`robot@<project>+<name>`**. CSC uses `robot@`
  in place of Harbor's default `robot$` prefix, so a username written from
  Harbor habit fails to log in. The secret is displayed once at creation.

## Project configuration: CSC-specific notes

Configuration is stock Harbor, under the project's tabs (Project Admin
needed). Beyond that:

- The scanner is **Trivy**. Signing options in Deployment Security are
  **cosign** and **Notation**. In "Prevent vulnerable images from running",
  selecting **Low** blocks on any finding, so it is the most restrictive
  setting.
- **Global labels** and the **system CVE allowlist** are managed by Satama
  administrators. A project admin needing either goes through Service Desk.
- Projects are **private by default**. Public allows anonymous pull, never
  anonymous push.

## What upstream is silent on (do not assert)

- SBOM format or export path.
- The tag-retention schedule (only that Satama "applies the policy according
  to the defined schedule").
- Audit-log retention period.
- How Satama images or Deployment Security wire into Rahti or Pouta
  deployments. Use the `csc-rahti` / `csc-pouta` skills for the platform side.
- Webhooks and P2P Preheat configuration, beyond the tabs existing.

## Troubleshooting (documented upstream)

| Symptom | Likely cause | Fix |
|---|---|---|
| `unauthorized: authentication required` | Not logged in, or the CLI secret was revoked/regenerated or the robot account expired | Regenerate the CLI secret (or check the robot account's expiry) and `docker login satama.csc.fi` again |
| `denied: requested access to the resource is denied` on push | Not a project member, or role below Developer | Ask a project admin for Developer or above |
| Push fails citing a tag policy | A tag-immutability rule matches the tag | Push under a new tag |
| `repository does not exist` on pull | Wrong project or repository name, or the tag was never pushed | Check the exact reference in the web UI |
