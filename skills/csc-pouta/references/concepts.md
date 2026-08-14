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
`gpu.1.1gpu`). Pick by workload:

- **`standard.*`** — general use. CPU cores are **overcommitted** (not for
  sustained compute). Root disk on central (redundant) storage; can be
  live-migrated; best availability. Sizes ~`standard.tiny` (1 core, ~0.9 GiB) up
  to `standard.3xlarge` (8 cores, 62 GiB).
- **`hpc.*`** — compute-intensive. **No CPU overcommit.** Tied to hardware;
  lower availability, expect maintenance downtime. (`hpc.4` Intel, `hpc.5`/`hpc.6`
  AMD EPYC.) Note `hpc.4` on **cPouta has no redundant power** (a power fault can
  make it temporarily unreachable); on ePouta `hpc.4` is power-redundant.
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

Three resources bill, all in **Cloud Billing Units (BU)** and in **1-hour
increments**:

- **VMs** — per-flavor BU/h (table below). **A shut-off or suspended VM still
  bills** (resources stay reserved); a VM stuck in **error** also bills.
  **Shelving** frees the compute and **stops the VM's billing**.
- **Volumes** — **3.6 BU/TiB·h** (Standard) or **1.8** (Capacity), on the full
  allocated size, **whether or not attached**.
- **Floating IPs** — **0.2 BU/h each**, **even when not associated**. The
  project's default router is free; extra routers you attach to the external
  network bill as a floating IP.

### Indicative flavor rates (BU/h)

> These are reference figures for **ballpark estimates only** and can change —
> for budgeting, confirm with the **BU calculator**
> (https://research.csc.fi/resources/#buc) and your project's live balance, and
> check live flavor specs with `openstack flavor list`. Figures below are
> **cPouta**; ePouta differs (see notes). Memory values are approximate.

**Standard** (cPouta and ePouta identical):

| Flavor | Cores | RAM (GiB) | BU/h |
|---|---|---|---|
| standard.tiny | 1 | 0.9 | 0.26 |
| standard.small | 2 | 1.9 | 0.52 |
| standard.medium | 3 | 3.9 | 1.05 |
| standard.large | 4 | 7.8 | 2.10 |
| standard.xlarge | 6 | 15 | 4.20 |
| standard.xxlarge | 8 | 31 | 8.40 |
| standard.3xlarge | 8 | 62 | 16.80 |

**HPC** (cPouta): hpc.4.5core 6 · hpc.4.80core 100; hpc.5.16core 20 ·
hpc.5.128core 160; hpc.6.14core 23 · hpc.6.112core 180. *(ePouta runs a bit
higher, e.g. hpc.6.14core 25, hpc.4.80core 120.)*

**I/O** (cPouta): io.70GB 3.15 · io.160GB 6.30 · io.340GB 12.60 · io.700GB
25.20; io.2.80GB 6 · io.2.240GB 12 · io.2.550GB 24 · io.2.1200GB 48. *(ePouta
io.2.* slightly higher: 6.30 / 12.60 / 25 / 50.)*

**GPU** (cPouta): gpu.1.1gpu 60 · gpu.1.2gpu 120 · gpu.1.4gpu 240. *(ePouta adds
gpu.2.1gpu 100 (V100) and gpu.3.1gpu 150 (A100).)*

**High memory** (ePouta only): tb.3.480RAM 110 · tb.3.1470RAM 320.

### Estimating

Sum the VM/volume/floating-IP rates above over the hours in use; the calculator
converts BU↔€ and shows your balance. Cost-saving patterns: **shelve** idle VMs
(stop still bills); **boot from volume** so you can delete the VM (only the
cheaper volume persists) and recreate later; release floating IPs you aren't
using; automate provisioning (Heat/Terraform/Ansible) to tear down and rebuild
on demand.

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
- **Floating IPs** come from the `public` pool. Gotcha: the API will let you
  associate the *same* floating IP to multiple instances with no error — the
  last call wins; avoid.

### Security groups (firewall)

- **Don't modify the `default` group** (some init relies on it). Create a
  purpose-named group per service instead, documenting which ports/source IPs.
- **Restrict source CIDRs. Never open SSH/22 to `0.0.0.0/0`** — scope it to
  your office/VPN ranges.

## Sending email (SMTP relay)

CSC runs an SMTP relay (smarthost) for cloud workloads: **`smtp.pouta.csc.fi:25`,
no authentication.** Don't deploy your own mail server on a VM; use this.

- **It is not `smtp.csc.fi`** — that's CSC's internal mail server, not the cloud
  relay.
- Authorisation is by **source IP** (cPouta VMs, Rahti nodes), so **mail code
  can't be tested from a laptop** — only from inside the cloud.
- The envelope **`Sender`** must be a valid address (e.g. your university one);
  the relay validates it, and it's a different header from `From`.
- Egress is open by default, so no security-group rule is needed.
- Provided **as-is and still in evaluation** — behaviour may change.
- **High SMTP volume** (e.g. public mailing lists) must be coordinated with
  <servicedesk@csc.fi> first, as must use cases the relay doesn't cover.

Deliverability: if the sending domain publishes SPF, it needs CSC's include —
`"v=spf1 include:hosted-at.csc.fi ~all"`. Two caveats worth raising unprompted:
only the domain's DNS owners can make that change, and a **malformed SPF record
breaks mail for the whole domain** (silent discards) — so it isn't a change to
improvise. With a `csc.fi` envelope sender, csc.fi's own SPF/DKIM/DMARC apply.
When the user doesn't control their domain's DNS, an **external authenticated
SMTP server** (their email provider's) is usually the better answer than this
relay.

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

- Bastion pattern: give only one VM a floating IP and reach the rest on their
  private IPs. Creating a keypair in the dashboard lets you download the private
  key **once** — Pouta keeps no copy.

## Storage

- **Ephemeral disk** — local to the host, fast, but **not durable**: lost on
  delete/shelve/migrate and **never in snapshots**. Don't keep valuable data
  here. (On `io.*` usually `/dev/vdb`.)
- **Persistent volume (Cinder)** — types: **Standard** (faster, pricier) and
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

You are responsible for your VMs' security, and CSC expects the standard
hardening practices (minimum-exposure firewalling, key-only SSH, automatic
security updates). CSC-specific points: run **no mail server of your own** (use
the relay above), and don't bake keys into images — use the metadata service /
cloud-init.

## Known gotchas

- Same floating IP assignable to multiple VMs via API with no warning (last wins).
- Device names (`/dev/vdb`) aren't stable across rebuild/reboot — mount by UUID
  in `/etc/fstab` (use `nofail`).
- Instance snapshots can fail and leave the VM suspended → power off first.
- Snapshot-spawned VMs have no security group preset.
- EC2 API is not supported for VM management (EC2 creds work only for object
  storage).
- Non-ASCII chars (ä/ö) don't work in the web virtual console — use SSH.
- **The SMTP relay is `smtp.pouta.csc.fi`, not `smtp.csc.fi`** (CSC-internal),
  and it's IP-restricted — mail code can't be tested from a laptop.
