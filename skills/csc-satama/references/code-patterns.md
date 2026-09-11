# Satama code patterns

Adapt to the user's task. Per SKILL.md rule 1: pushing a **new** tag, pulling,
and creating a robot account/label/policy rule are non-clobbering and may be
run after disclosure; **overwriting an existing tag, deleting a tag/image, or
enabling a tag-retention rule** is written as a **reviewable script**, not run
on your own initiative. Never hard-code, echo, log, or commit a CLI secret or
robot-account token.

Registry/UI hostname: `satama.csc.fi`. Image reference format:
`satama.csc.fi/<project>/<repository>:<tag>`.

---

## Log in

Personal CLI secret (generate at **User Profile** in the web UI; store it
securely — it can be revoked or regenerated at any time from the same page):

```bash
docker login satama.csc.fi -u <your-username>
# Password: <paste the CLI secret, not your MyCSC password>
```

Robot account (preferred for automation — see below for creation):

```bash
docker login satama.csc.fi -u 'robot@<project>+<name>'
# Password: <the robot account's secret>
```

`podman login` takes the same arguments as `docker login` throughout.

If login suddenly starts failing with `unauthorized`, the session behind the
CLI secret may have expired — log out/in at `satama.csc.fi`, then retry.

---

## Pull an image

Read-only — always fine to run:

```bash
docker pull satama.csc.fi/<project>/<repository>:<tag>
```

---

## Tag and push a new image (a true create)

```bash
docker build -t <image>:<version> .
docker tag <image>:<version> satama.csc.fi/<project>/<image>:<version>
docker push satama.csc.fi/<project>/<image>:<version>
```

Check the push landed: open the project's **Repositories** tab in the web UI,
or `docker pull` the same reference back.

**Before pushing, check whether `<project>/<image>:<version>` already
exists** (e.g. `docker pull` it, or check the UI) — if it does, this push
**overwrites the manifest that tag points to**, which is a modify, not a
create (SKILL.md rule 1). Prefer pushing under a new, unused tag
(`v1.2.1`, a commit SHA, a build number) instead of reusing one, especially
one anything is currently deployed from.

---

## Create a robot account (for CI/CD or any unattended push/pull)

Project Admin → project → **Robot Accounts** tab → **New Robot Account**:

1. Name + description (purpose).
2. Expiration date, or **never** — set one unless there's a reason not to.
3. Permissions: pick only what's needed (e.g. push+pull) rather than **all**.
4. **Finish** — Satama shows the generated username and secret **once**.
   Copy both immediately into a secret store (CI secret, `.netrc`, vault) —
   they cannot be redisplayed.

If the secret is lost, or needs rotating, it doesn't have to be recreated
from scratch: in **Robot Accounts**, select the account → **Action** →
**Refresh Secret** issues a new secret for the same account/username (the
old secret stops working) — update it wherever it's stored (CI secret,
`.netrc`, vault).

Resulting username has the fixed shape `robot@<project>+<name>`, e.g.:

```bash
docker login satama.csc.fi -u 'robot@test-project+ci-pusher'
```

In a CI pipeline, store the secret as a masked/protected variable and pass it
via stdin, never as a literal in the job definition:

```bash
echo "$SATAMA_ROBOT_SECRET" | docker login satama.csc.fi -u 'robot@test-project+ci-pusher' --password-stdin
```

---

## Deploying a Satama image on Rahti or Pouta

Once pushed, reference the same fully-qualified tag as the image source —
e.g. for Rahti: `oc new-app satama.csc.fi/<project>/<image>:<version>`.
If the project is **private**, the target platform's pull credentials need
access — for Rahti that means an image-pull secret built from a Satama robot
account:

```bash
oc create secret docker-registry satama-pull \
  --docker-server=satama.csc.fi \
  --docker-username='robot@<project>+<name>' \
  --docker-password='<robot secret>' \
  --docker-email=unused@example.com
oc secrets link default satama-pull --for=pull
```

(See the `csc-rahti` skill for the rest of the Rahti deploy flow.)

---

## Avoid-zone: modifying / deleting live resources (write, don't run)

Per rule 1, produce these as reviewable steps/scripts and state the effect
plainly before the user runs them.

- **Delete a tag** (UI-only — Harbor's registry API has a manifest-delete
  endpoint, but no CLI command deletes a *remote* tag): open the repository →
  check the tag(s) → **Remove Tag** → confirm **Delete** in the pop-up.
  State explicitly: the tag reference is gone immediately and is not
  user-recoverable; the underlying image data is garbage-collected later.
  Verify nothing still deploys from that tag first.

- **Enable/edit a tag-retention rule** (Policy tab → Add rule) — this is a
  **standing, recurring auto-delete**, not a one-off. Before turning one on,
  write out in plain terms exactly what it will delete and how often, e.g.:

  > Rule: keep the latest 10 tags in `<project>/<repository>`, delete the
  > rest. This runs automatically on Satama's schedule going forward —
  > every tag outside the newest 10 will eventually be deleted with no
  > confirmation prompt, including ones another deployment might still use.

  Only enable after the user confirms that framing.

- **Flip a project from private to public** — anonymous pull becomes
  possible immediately. Disclose this before making the change, same as any
  other public-exposure decision in these skills.

- **Change a member's role, or delete/re-scope a robot account** — a live
  permission change; state who/what loses or gains access before doing it,
  and remember role edits can be reverted by Satama's periodic sync anyway
  (`concepts.md`).

- **Refresh a robot account's secret** (Robot Accounts → select the account →
  **Action** → **Refresh Secret**) — issues a new secret and invalidates the
  old one immediately. Anything still authenticating with the old secret
  (a running CI job, a deployed pull-secret) breaks until it's updated with
  the new one. Confirm nothing is depending on the current secret first, or
  line up the update everywhere it's used.
