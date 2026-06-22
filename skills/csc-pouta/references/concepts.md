# Pouta concepts & CSC quirks

Source: CSC user guide (`cloud/pouta/`). Pouta runs **OpenStack**. cPouta
dashboard: `https://pouta.csc.fi`; ePouta dashboard: `https://epouta.csc.fi`.

## cPouta vs ePouta

| | cPouta | ePouta |
|---|---|---|
| Purpose | general public/community cloud | **sensitive data** processing |
| Provisioning | **self-service**, instant | request via servicedesk@csc.fi; CSC + your IT set it up (can take weeks) |
| Access | public internet via **floating IPs** | private **MPLS VPN** to your org's network; reach VMs on their **private IP** (no floating IP needed) |
| Dashboard | pouta.csc.fi | epouta.csc.fi (reachable only from approved IPs) |
| API/tooling | identical OpenStack API | identical OpenStack API |
| Extra flavors | — | high-memory `tb.3.*`, more GPU options |

ePouta is a "virtual private datacentre": its VMs share a network with servers
on your institution's premises as if co-located. **Assume cPouta unless the user
says ePouta.** Applying for ePouta: email servicedesk@csc.fi with the use case
(why it needs ePouta / sensitive data), confirmation no existing resource fits,
estimated resources (flavors, BUs, duration), and the admin machine IPs that
will manage VMs.

## CSC project = OpenStack tenant

A CSC **project** is the OpenStack project/tenant and the namespace for *all*
resources: VMs, volumes, networks, routers, floating IPs, images, keypairs,
quota and billing.

- **Every member of the project has full access** to every resource in it —
  anyone can create, modify or delete anything. (VM *login* is separate, gated
  by SSH keypairs.) A deletion is unrecoverable and affects everyone.
- Credentials/`clouds.yaml` entries are **scoped to one project**. To work in
  another project, use that project's credentials.
- **Default quotas** (raise via servicedesk@csc.fi): 8 instances, 8 cores,
  32 GB RAM, 2 floating IPs, 1 TB volume storage. Check live values:
  `openstack quota show` / `openstack limits show`.

## Flavors

Naming: `<family>.<size>` (e.g. `standard.small`, `hpc.6.14core`, `io.160GB`,
`gpu.1.1`). Pick by workload:

- **`standard.*`** — general use. CPU cores are **overcommitted** (not for
  sustained compute). Root disk on central (redundant) storage; can be
  live-migrated; best availability. Sizes ~`standard.tiny` (1 core, ~0.9 GiB) up
  to `standard.3xlarge` (8 cores, 62 GiB).
- **`hpc.*`** — compute-intensive. **No CPU overcommit.** Tied to hardware;
  lower availability, expect maintenance downtime. (`hpc.4` Intel, `hpc.5`/`hpc.6`
  AMD EPYC.)
- **`io.*`** — disk-intensive (databases, Spark/Hadoop). Large **ephemeral**
  SSD/NVMe disk, usually at `/dev/vdb`. Older `io.*` = RAID-0 (no redundancy),
  no power redundancy; newer `io.2.*` = RAID-1 + power redundancy. Can't migrate
  or resize across families.
- **`gpu.*`** — GPUs (P100 on cPouta `gpu.1.*`; V100/A100 also on ePouta).
  Request access via application or servicedesk@csc.fi.
- **`tb.3.*`** (ePouta only) — high memory (480–1470 GiB). No resize/migration;
  snapshot or recreate. Large ephemeral NVMe **not saved in snapshots**.

Use the BU calculator: https://research.csc.fi/resources/#buc

## Billing — what costs and what stops it

- Running VM: per-flavor Cloud BU/hour (1-hour increments).
- **A shut-off or suspended VM still bills** — its resources stay reserved.
- **Shelving** a VM frees the compute resources and **stops its billing**.
- Volumes bill per TiB/hour (Standard ~3.6 BU/TiB/h, Capacity ~1.8). Floating
  IPs bill ~0.2 BU/h **even when not associated**.
- A VM stuck in **error** state still bills — contact servicedesk if unrecoverable.

Cost-saving patterns: shelve idle VMs (not just stop); **boot from volume** so
you can delete the VM (cheap volume persists) and recreate later; automate
provisioning (Heat/Terraform/Ansible) to tear down and rebuild on demand.

## VM lifecycle

| State | Compute freed? | Still billing? | Notes |
|---|---|---|---|
| Active | no | yes | running |
| Shut off (stop) | no (reserved) | **yes** | powered off but reserved |
| Paused | no | yes | state in RAM on host; not for production |
| Suspended | no | yes | state saved on host; not recommended |
| **Shelved** | **yes** | **no** | filesystem/floating IP/network saved to central storage |
| Deleted/terminated | yes | no | **VM + ephemeral disk gone for good**; attached volumes survive |

- **Shelve** is the way to pause billing without deleting. Unshelve can be slow
  for `io.*`/`hpc.*` (data copied back from central storage), and may fail if the
  cloud is full. **Ephemeral disk on `io.*`/`tb.*` flavors is NOT preserved by
  shelving** — it's lost.
- **Resize** changes flavor; within a family is usually fine, **across families
  is risky** (different storage backends — can fail or lose data; test with an
  expendable VM first). Causes downtime; enters "verify resize" you must confirm.
- Snapshot consistency: **power the VM off before snapshotting** (a known bug can
  otherwise leave it suspended). VMs created from a snapshot have **no security
  group preset** — assign one at launch.

## Networking

- Each project has a **default network + router** (router bridges the external
  network to your private subnet). Without them you can't launch VMs / assign
  floating IPs.
- VMs have **no external access by default**. Reachability needs (a) a
  **security group** rule allowing the traffic and (b) a **floating IP**
  (cPouta) associated to the VM. CSC DNS nameservers for new subnets:
  `193.166.4.24`, `193.166.4.25`.
- **Floating IPs**: allocate from the `public` pool, then associate to the VM;
  it stays until released. Gotcha: the API will let you associate the *same*
  floating IP to multiple instances with no error — the last call wins; avoid.

### Security groups (firewall)

- OpenStack-layer firewall rule sets; a VM can have several, a group can be on
  several VMs; edits apply instantly and cost nothing.
- **Don't modify the `default` group** (some init relies on it). Create a
  purpose-named group per service instead, documenting which ports/source IPs.
- Egress is open by default; you mostly add **ingress** rules.
- **Restrict source CIDR.** Single host = `/32` (e.g. `198.51.100.7/32`); a
  subnet = `/24`/`/16`. **Never open SSH/22 to `0.0.0.0/0`** — scope it to your
  office/VPN ranges. Two firewalls exist: the security group *and* the VM's own
  iptables/netfilter.

## SSH keypairs & connecting

- Keypairs are **injected into the VM only at creation** via cloud-init. Adding
  a key in the dashboard afterwards does **not** reach a running VM (recover via
  rescue mode if locked out).
- Images allow **key-only** login (no passwords) and **no root login**. Use the
  image's default user:

| Image | Default user |
|---|---|
| Ubuntu (22.04 / 24.04) | `ubuntu` |
| AlmaLinux (8/9/10) | `almalinux` |
| CentOS Stream (9/10) | `cloud-user` |

- Connect: `ssh -i ~/.ssh/key.pem <user>@<floating-ip>`. A `~/.ssh/config` Host
  entry simplifies it. Bastion pattern: only one VM gets a floating IP; reach the
  rest on private IPs via agent forwarding (`ssh -A`), noting its security
  caveats. Creating a keypair in the dashboard lets you download the private key
  **once** — Pouta keeps no copy.

## Storage

- **Ephemeral disk** — local to the host, fast, but **not durable**: lost on
  delete/shelve/migrate and **never in snapshots**. Don't keep valuable data
  here. (On `io.*` usually `/dev/vdb`.)
- **Persistent volume (Cinder)** — network block storage, replicated, detachable
  and reattachable to other VMs. Types: **Standard** (faster, pricier) and
  **Capacity** (bulk/cold, cheaper). Min 1 GB. Survives VM deletion. Most types
  attach to one VM at a time (see multiattach below).
- **Object storage (Allas)** — for data shared across VMs/services or kept long
  term; see the separate `csc-allas` skill.
- **Snapshots** — *volume* snapshots capture a volume; *instance* snapshots
  capture the **root disk** as an image (exclude ephemeral; ~0 bytes if the VM
  boots from a volume). Power off before snapshotting. No quota on snapshot
  count but they consume storage quota.
- **Multiattach** (`standard.multiattach`) — one volume on several VMs at once.
  **Quota is 0 by default** (request via servicedesk). Requires a clustered
  filesystem (GFS2/OCFS2) — plain ext4/xfs corrupts. Non-trivial.

Data-loss watchpoints: format/mount a volume **only on first use** (re-running
`mkfs` wipes it); **unmount before detaching**; volume delete needs status
`Available`, no snapshots, not in a group.

## Security best practices (CSC emphasis)

You are responsible for your VMs' security. Minimum-exposure firewalling (open
only needed ports, to fewest IPs); SSH keys only (never password login); don't
bake keys into images (use the metadata service / cloud-init); disable unneeded
services; prefer HTTPS/SFTP/FTPS; enable automatic security updates
(`unattended-upgrades` on Ubuntu, `dnf-automatic` on recent RHEL-likes) and
schedule reboots for kernel updates; consider fail2ban/denyhosts; log to a
secure/remote location; snapshot for recovery. Recommended account model: root
(no SSH), one sudo admin user (key-only — the image's default user), and
per-service no-login accounts.

## Known gotchas

- Same floating IP assignable to multiple VMs via API with no warning (last wins).
- Device names (`/dev/vdb`) aren't stable across rebuild/reboot — mount by UUID
  in `/etc/fstab` (use `nofail`).
- Instance snapshots can fail and leave the VM suspended → power off first.
- Snapshot-spawned VMs have no security group preset.
- EC2 API is not supported for VM management (EC2 creds work only for object
  storage).
- Non-ASCII chars (ä/ö) don't work in the web virtual console — use SSH.
