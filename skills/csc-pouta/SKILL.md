---
name: csc-pouta
description: >
  Use Pouta, CSC's OpenStack IaaS cloud, correctly and safely. Invoke when the
  user wants to launch/configure/manage virtual machines, volumes, snapshots,
  images, networks, security groups, floating IPs or SSH access on Pouta, set up
  OpenStack credentials (RC file / application credentials / clouds.yaml), use
  the openstack CLI or openstacksdk, write Heat / Terraform / Ansible
  automation for Pouta (it writes the IaC; it does not run it), send email from
  a VM (the
  smtp.pouta.csc.fi SMTP relay, SPF), or asks about Pouta concepts (cPouta vs
  ePouta, CSC projects/tenants, flavors, billing, VM lifecycle/shelving,
  ephemeral vs persistent storage). Covers cPouta (the common case) and answers
  ePouta (sensitive-data cloud) questions. Can create resources (with clear
  disclosure of cost and network exposure) but does NOT itself modify or delete
  existing resources — it writes reviewable code/scripts for those.
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

1. **Creating resources is fine — with clear disclosure. Modifying or deleting
   existing resources is the avoid-zone.** This skill can provision; it should
   not quietly change or tear down what already exists. Three tiers:

   - **Read-only inspection** — always OK to run on request:
     `openstack server/flavor/image/volume/network/security group list`,
     `server show`, `catalog list`, `quota show`, `limits show`.
   - **Creating new resources** — OK to run, *after* you state plainly what
     you're about to create and the user gives a go-ahead. Two things you must
     always disclose up front:
     - **Cost.** VMs, volumes and floating IPs bill (see `concepts.md`) — name
       the flavor/size and give a rough BU/h so the user isn't surprised.
     - **Network exposure.** When creating a security group or rule, say which
       ports open to which sources, and **never open SSH/22 (or anything) to
       `0.0.0.0/0` unless the user explicitly asks** — default to a restricted
       source CIDR.
     Examples: `server create`, `volume create`, `network`/`router create`,
     `security group create`, `keypair create`, allocating + associating a
     `floating ip`, attaching a *newly created* volume.
   - **Modifying or deleting existing resources** — do NOT run on your own;
     **write a reviewable script** and let the user run it. This covers anything
     that changes or removes something already there: `server
     delete/reboot/stop/start/shelve/resize`, `volume delete`, `volume set`
     (resize/retype), `server remove volume` (detach), reformatting a volume
     that holds data, editing/deleting security-group rules on a group in use,
     reassigning a floating IP, changing image sharing/properties.

   When asked to do something in the avoid-zone, state plainly and specifically
   what it does and call out the sharp edges before writing the script:
   - `server delete` / terminate — **irreversibly destroys the VM and its
     ephemeral disk** (attached persistent volumes survive). Unrecoverable.
   - `volume delete`, or `mkfs`/first-use formatting of an already-used volume —
     **destroys data**.
   - Detaching a volume without unmounting first — risks corruption.
   - `server resize` across flavor families — risky, can fail or lose data.
   - **Every project member shares full access**, so a deletion affects everyone.
   Only run such an operation if the user, after that, clearly confirms — and
   never a `server delete` / `volume delete` / bulk teardown on your own
   initiative.

   **A request for automation is a request for the artifact.** "Write me
   Ansible / Terraform / Heat / a script for X" means: write the file — the
   deliverable is the code, not its execution. (Asking for the *outcome* —
   "launch a VM" — is different; the tiers above apply.) Executing IaC or
   config-management tools (`ansible-playbook`, `terraform apply`,
   `openstack stack create/update`) is never a plain create even when the
   template only declares new resources: the effect depends on existing state,
   and configuring software on an existing VM is a modify. If the user
   explicitly asks you to run one, treat it as avoid-zone — show the dry-run
   (`terraform plan`, `ansible-playbook --check`) first and run only on
   confirmation.

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
  can be deleted to stop billing cheaply). Then — after stating the flavor, a
  rough BU/h, and which sources reach SSH — either run the `openstack server
  create` (rule 1 allows creation) or, if the user asked for code/IaC, generate
  the openstacksdk / Heat / Terraform / Ansible artifact from
  `references/code-patterns.md` and hand it over without executing it.
- **"Give it persistent storage."** Generate volume create + attach, and the
  one-time format/mount steps (with the "only on first use" warning).
- **"Open port N"** / firewall — generate the security-group rule, and default
  to a **restricted source CIDR**, not `0.0.0.0/0` (especially for SSH).
- **"Make it reachable."** Allocate + associate a floating IP (cPouta); for
  ePouta, it's the private VPN IP instead.
- **"Stop paying for it."** Recommend **shelve** (stops billing) over stop;
  or delete (with boot-from-volume so data survives).
- **"Send email from my VM."** Use CSC's relay — **`smtp.pouta.csc.fi:25`, no
  auth**, *not* `smtp.csc.fi` (that's CSC-internal). It authorises by source IP
  (so it won't work from a laptop) and needs a valid envelope `Sender`; don't run
  a mail server on the VM. Raise SPF/deliverability from `concepts.md`.
- **"What will this cost?"** Use the indicative BU/h rate table in
  `concepts.md` for a ballpark (VM + volumes + floating IPs, billed hourly),
  but point the user at the BU calculator (https://research.csc.fi/resources/#buc)
  for budgeting — the table is reference-only and rates can change.

## Reference material

Load the relevant file when you need detail:

- `references/concepts.md` — cPouta vs ePouta, CSC projects & quotas, flavor
  families & billing, the full VM lifecycle (active/stop/pause/suspend/shelve/
  delete and which states bill), networking (project network/router, floating
  IPs, security groups), the SMTP relay & mail deliverability, SSH keypairs &
  default image users, storage (ephemeral vs persistent volumes vs snapshots vs
  Allas), security best practices, and ePouta access.
- `references/code-patterns.md` — authentication (RC file, application
  credentials, `clouds.yaml`), installing/using the `openstack` CLI,
  openstacksdk (Python), and ready-to-adapt recipes: launch a VM, volumes,
  snapshots/images, security groups, floating IPs, lifecycle/shelve, teardown.

When advising on mechanics, prefer these notes over memory; if something here is
silent on a detail, say so rather than inventing CSC-specific behaviour.
