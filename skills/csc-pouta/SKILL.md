---
name: csc-pouta
description: >
  Use Pouta, CSC's OpenStack IaaS cloud, correctly and safely. Invoke when the
  user wants to launch/configure/manage virtual machines, volumes, snapshots,
  images, networks, security groups, floating IPs or SSH access on Pouta, set up
  OpenStack credentials (RC file / application credentials / clouds.yaml), use
  the openstack CLI or openstacksdk, or asks about Pouta concepts (cPouta vs
  ePouta, CSC projects/tenants, flavors, billing, VM lifecycle/shelving,
  ephemeral vs persistent storage). Covers cPouta (the common case) and answers
  ePouta (sensitive-data cloud) questions. Generates code/scripts but does NOT
  itself run resource-creating, state-changing, or destructive OpenStack
  operations.
---

# CSC Pouta (OpenStack IaaS)

Pouta is CSC's Infrastructure-as-a-Service cloud, built on **OpenStack**. You
rent virtual machines and attach storage, networking and access controls to
them. Two environments share the same OpenStack model:

- **cPouta** — the public, self-service cloud (dashboard `https://pouta.csc.fi`).
  VMs get internet-reachable floating IPs. **This is the default** — assume
  cPouta unless the user says ePouta.
- **ePouta** — a high-security cloud for **sensitive data**. Not self-service
  (access is requested and provisioned by CSC + your institution's IT over an
  MPLS VPN), no public floating IPs — you reach VMs over the private VPN.
  Same OpenStack API/tooling. Be able to answer ePouta questions; see
  `references/concepts.md`.

This skill helps you (a) write correct OpenStack code/scripts and (b) advise on
the mechanics, with the CSC-specific quirks built in.

## Operating rules (read first)

1. **Do not run resource-creating, state-changing, or destructive OpenStack
   operations yourself.** This skill *writes* code and scripts; the user runs
   them. Pouta resources **cost billing units** and several operations **destroy
   data**, so the bar is higher than read-only tooling.

   - **You may run, on request: read-only inspection** — e.g.
     `openstack server list`, `... flavor list`, `... image list`,
     `... volume list`, `... network list`, `... security group list`,
     `... server show <x>`, `... catalog list`, `... quota show`,
     `... limits show`.
   - **You must NOT independently run** anything that creates, modifies,
     reboots, resizes, deletes, or re-permissions resources:
     `server create/delete/reboot/resize/shelve/stop`, `volume
     create/delete/set`, `server add/remove volume`, `floating ip
     create/delete/...`, `security group rule create/delete`, image
     create/delete, etc.

   If the user explicitly asks you to perform one of those:
   - State plainly and specifically what it does — which resource, and call out
     **billing** and **data loss**. The sharp edges:
     - `server delete` / terminate — **irreversibly destroys the VM and its
       ephemeral disk** (attached persistent volumes survive). Unrecoverable.
     - `volume delete`, and `mkfs`/first-use formatting of an already-used
       volume — **destroys data**.
     - Detaching a volume without unmounting first — risks corruption.
     - `server resize` across flavor families — risky, can fail or lose data.
     - A security-group rule opening a port (especially SSH/22) to
       `0.0.0.0/0` — exposes the VM to the whole internet.
     - Remember **every project member shares full access** to all resources,
       so a deletion affects everyone.
   - Offer to **write a reviewable script** instead. Prefer that.
   - Only run it if the user, after that, clearly confirms — and never a
     `server delete` / `volume delete` / bulk teardown on your own initiative.

2. **A CSC project is the OpenStack tenant — the namespace for everything.** All
   VMs, volumes, networks, floating IPs, images, keypairs and quota belong to
   one project, and **every member of the project has full access** to them
   (create/modify/delete). VM *login* is separate, controlled by SSH keypairs.
   Credentials are scoped to **one project**; to act in another project you use
   that project's credentials / `clouds.yaml` entry. See
   `references/concepts.md`.

3. **Authenticate with application credentials + `clouds.yaml`, not the password
   RC file**, unless the user wants otherwise. App credentials are
   project-scoped, revocable, carry no CSC password, and suit automation. Never
   hard-code, echo, log, or commit credentials — and note the app-credential
   **secret is shown only once** at creation (revoke + recreate if lost). See
   `references/code-patterns.md`.

4. **Surface the cost/data-loss facts that bite people**, proactively:
   - A **shut-off or suspended VM still bills** (resources stay reserved). To
     stop billing without deleting, **shelve** it. Floating IPs bill even when
     unattached.
   - **Ephemeral disk is not durable** — it's lost on delete, shelve, migrate,
     and is excluded from snapshots. Keep nothing valuable there; use a
     **persistent volume** or Allas (see the `csc-allas` skill).
   - **SSH keypairs are injected only at VM creation.** Adding a key in the
     dashboard later does *not* update a running VM. Plan the key before launch.

## Quick start: common requests

- **"Launch a VM that does X."** Confirm: which **flavor** (family + size — see
  `concepts.md`; `standard.*` for general use, `hpc.*` no overcommit, `io.*`
  big local disk, `gpu.*` GPUs), which **image** (and its default login user —
  Ubuntu→`ubuntu`, AlmaLinux→`almalinux`, CentOS→`cloud-user`), which
  **keypair**, which **security group** (and which source IPs may reach SSH),
  and whether to **boot from a volume** (so the root disk persists and the VM
  can be deleted to stop billing cheaply). Then generate the
  `openstack server create` (or openstacksdk / Heat / Terraform) code from
  `references/code-patterns.md`.
- **"Give it persistent storage."** Generate volume create + attach, and the
  one-time format/mount steps (with the "only on first use" warning).
- **"Open port N"** / firewall — generate the security-group rule, and default
  to a **restricted source CIDR**, not `0.0.0.0/0` (especially for SSH).
- **"Make it reachable."** Allocate + associate a floating IP (cPouta); for
  ePouta, it's the private VPN IP instead.
- **"Stop paying for it."** Recommend **shelve** (stops billing) over stop;
  or delete (with boot-from-volume so data survives).
- **"What will this cost?"** Use the indicative BU/h rate table in
  `concepts.md` for a ballpark (VM + volumes + floating IPs, billed hourly),
  but point the user at the BU calculator (https://research.csc.fi/resources/#buc)
  for budgeting — the table is reference-only and rates can change.

## Reference material

Load the relevant file when you need detail:

- `references/concepts.md` — cPouta vs ePouta, CSC projects & quotas, flavor
  families & billing, the full VM lifecycle (active/stop/pause/suspend/shelve/
  delete and which states bill), networking (project network/router, floating
  IPs, security groups), SSH keypairs & default image users, storage
  (ephemeral vs persistent volumes vs snapshots vs Allas), security best
  practices, and ePouta access.
- `references/code-patterns.md` — authentication (RC file, application
  credentials, `clouds.yaml`), installing/using the `openstack` CLI,
  openstacksdk (Python), and ready-to-adapt recipes: launch a VM, volumes,
  snapshots/images, security groups, floating IPs, lifecycle/shelve, teardown.

When advising on mechanics, prefer these notes over memory; if something here is
silent on a detail, say so rather than inventing CSC-specific behaviour.
