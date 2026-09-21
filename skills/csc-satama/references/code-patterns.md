# Satama code patterns

Per SKILL.md rule 1: pushing a **new** tag, pulling, and creating a robot
account, label or policy rule may be run after disclosure. **Overwriting an
existing tag, deleting a tag or image, enabling a tag-retention rule** and
other live-resource changes are written as reviewable steps, not run on your
own initiative. Never hard-code, echo, log or commit a CLI secret or robot
secret.

Registry and web UI hostname: `satama.csc.fi`. Image reference:
`satama.csc.fi/<project>/<repository>:<tag>`. `podman` takes the same
arguments as `docker` throughout.

## Log in

Personal CLI secret (web UI → your username → **User Profile** → **CLI
Secret**):

```bash
docker login satama.csc.fi -u <your-username>
# Password: the CLI secret, not your MyCSC password
```

Robot account. Note the `robot@` prefix; Harbor's default `robot$` does not
work on Satama:

```bash
echo "$SATAMA_ROBOT_SECRET" | docker login satama.csc.fi -u 'robot@<project>+<name>' --password-stdin
```

`unauthorized` while the web UI still shows you logged in means the CLI
secret has expired: log out of the web UI, log in again, generate a **new**
secret, and log in with that. The old secret will not start working again.

## Push a new tag

```bash
docker tag <image>:<version> satama.csc.fi/<project>/<image>:<version>
docker push satama.csc.fi/<project>/<image>:<version>
```

Before pushing, check that the tag does not already exist (the project's
**Repositories** tab, or try `docker pull` on the reference). If it does, the
push repoints the tag: a modify, not a create (SKILL.md rule 1). Prefer a
fresh tag (`v1.2.1`, a commit SHA, a build number). The **PUSH COMMAND**
button on the project page shows the exact commands for that project.

## Create a robot account

Project Admin → project → **Robot Accounts** → **New Robot Account**: name,
description, expiration (set one unless there is a reason not to), then only
the permissions needed (for example push and pull). Satama shows the
username (`robot@<project>+<name>`) and secret **once**; store the secret in
a masked CI variable or a vault immediately.

A lost or compromised secret does not need a new account: in **Robot
Accounts**, select the account → **Action** → **Refresh Secret** issues a new
secret for the same username, and the old one stops working. Update it
wherever it is stored (CI variable, `.netrc`, vault). This path is not in
the upstream docs; it comes from the Satama developers.

Deploying a **private** Satama image on Rahti or Pouta needs a pull credential
built from a robot account. The platform-side mechanics (image pull secrets
and so on) belong to the `csc-rahti` / `csc-pouta` skills; upstream Satama
docs do not cover them.

## Avoid-zone: write, don't run

State the effect plainly and get confirmation before any of these:

- **Delete a tag** (web UI: repository → tick the tag → **Remove Tag** →
  **Delete**). The reference is gone immediately and is not user-recoverable;
  the blobs are removed in a later storage cleanup. Check first that nothing
  still deploys from it.
- **Tag-retention rule** (**Policy** tab → Tag Retention → Add rule). A
  standing, scheduled auto-delete. Write it out in plain terms before
  enabling, for example: "keep the latest 10 tags in
  `<project>/<repository>` and delete the rest, on Satama's schedule, with no
  confirmation prompt, including tags another deployment may still use".
- **Private → public**: anonymous pull becomes possible immediately.
- **Role change, robot account deletion or re-scoping**: say who loses or
  gains what. Role edits may be reverted by the periodic sync anyway.
- **Refresh a robot secret** (**Robot Accounts** → select the account →
  **Action** → **Refresh Secret**): the old secret stops working at once, so
  every CI job or pull secret using it breaks until updated. Line up the
  update everywhere it is used first.
