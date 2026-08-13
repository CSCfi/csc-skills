# Pouta code patterns

Adapt to the user's task. Per SKILL.md rule 1: creating resources may be run
(after disclosing cost and network exposure); modifying or deleting existing
resources is written as a reviewable script, not run. Never hard-code or echo
credentials.

cPouta identity endpoint: `https://pouta.csc.fi:5001/v3` (Keystone v3),
region `regionOne`, user domain `Default`. For **ePouta**, use the values from
the RC file / application credential you download at `https://epouta.csc.fi`.

---

## Authentication

### Preferred: application credentials + clouds.yaml

Create in the dashboard: **Identity → Application Credentials → Create**. Give a
name, optionally an expiry; leave the secret blank to auto-generate. **The
secret is shown only once** — if lost, revoke and recreate. Don't tick
"unrestricted". Note: app-credential *access rules*, if set, block Allas access.

Download as `clouds.yaml` (lives at `~/.config/openstack/clouds.yaml`):

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://pouta.csc.fi:5001/v3
      application_credential_id: <id>
      application_credential_secret: <secret>
    regions:
      - regionOne
    interface: "public"
    identity_api_version: 3
    auth_type: "v3applicationcredential"
```

Select it per command with `--os-cloud openstack` or `export OS_CLOUD=openstack`.
Keep this file out of version control (`chmod 600`, add to `.gitignore`).

> Pitfall: app credentials **cannot request a scope**, so a stray `OS_*` var in
> the environment causes `HTTP 401 "Application credentials cannot request a
> scope"`. Clear them first: `for v in $(env | grep -o '^OS_[A-Z_]*'); do unset
> $v; done` (or open a clean shell), then rely on clouds.yaml / `OS_CLOUD`.

### Alternative: password RC file

Dashboard → **API Access → Download OpenStack RC File**, then:

```bash
source <project>-openrc.sh   # prompts for your CSC password (not Haka/Virtu)
```

Sets `OS_AUTH_URL`, `OS_USERNAME`, `OS_PASSWORD`, `OS_PROJECT_NAME`,
`OS_USER_DOMAIN_NAME=Default`, `OS_IDENTITY_API_VERSION=3`,
`OS_REGION_NAME=regionOne`. Fine interactively; prefer app credentials for
automation/scripts so no CSC password is involved.

### Install the CLI

```bash
python3 -m venv ~/osclient && source ~/osclient/bin/activate
pip install python-openstackclient        # provides the `openstack` command
# add openstacksdk for Python, python-heatclient for Heat, etc.
```

Sanity check (read-only): `openstack catalog list`, `openstack server list`.

---

## openstacksdk (Python)

```python
import openstack

conn = openstack.connect(cloud="openstack")   # reads ~/.config/openstack/clouds.yaml

# Read-only examples
for f in conn.compute.flavors():
    print(f.name, f.vcpus, f.ram)
for s in conn.compute.servers():
    print(s.name, s.status)
```

Launch a VM in Python (creation — OK to run after disclosing flavor/cost and
SSH exposure, per rule 1):

```python
import openstack
conn = openstack.connect(cloud="openstack")

image   = conn.compute.find_image("Ubuntu-24.04")
flavor  = conn.compute.find_flavor("standard.medium")
network = conn.network.find_network("project_2001234")   # your project network
keypair = "my-key"

server = conn.compute.create_server(
    name="web-01", image_id=image.id, flavor_id=flavor.id,
    networks=[{"uuid": network.id}], key_name=keypair,
    security_groups=[{"name": "web-sg"}],
)
server = conn.compute.wait_for_server(server)

# Allocate + associate a floating IP (cPouta)
fip = conn.network.create_ip(floating_network_id=conn.network.find_network("public").id)
conn.compute.add_floating_ip_to_server(server, fip.floating_ip_address)
print("ssh ubuntu@%s" % fip.floating_ip_address)
```

---

## openstack CLI recipes

Read-only discovery (safe to run):

```bash
openstack flavor list
openstack image list
openstack network list
openstack security group list
openstack keypair list
openstack server list
openstack quota show          # project quotas/usage
```

### Launch a VM

Pick image (and its login user — see concepts.md), flavor, network, keypair,
security group. **Boot from volume** is recommended for anything you want to
keep cheaply: the root disk becomes a persistent volume that survives deleting
the VM.

```bash
# Ephemeral root disk (lost when the VM is deleted)
openstack server create \
  --image Ubuntu-24.04 --flavor standard.medium \
  --network project_2001234 --key-name my-key \
  --security-group web-sg \
  web-01

# Boot from a new 50 GB volume (root disk persists; delete-on-terminate off)
openstack server create \
  --flavor standard.medium --network project_2001234 \
  --key-name my-key --security-group web-sg \
  --boot-from-volume 50 --image Ubuntu-24.04 \
  web-01
```

### Networking: floating IP + security group

```bash
# Floating IP (cPouta)
openstack floating ip create public
openstack server add floating ip web-01 <floating-ip>

# A security group that allows SSH only from a specific source, and HTTPS
openstack security group create web-sg --description "web + admin ssh"
openstack security group rule create --proto tcp --dst-port 22 \
  --remote-ip 198.51.100.0/24 web-sg          # SSH limited to your range
openstack security group rule create --proto tcp --dst-port 443 \
  --remote-ip 0.0.0.0/0 web-sg                # public HTTPS
```

> Default to a **restricted `--remote-ip`** for SSH. Opening 22 to `0.0.0.0/0`
> exposes the VM to internet-wide brute force.

### Connect

```bash
ssh -i ~/.ssh/my-key.pem ubuntu@<floating-ip>   # ePouta: use the private IP, no floating IP
```

### Persistent volume: create, attach, first-use format, mount

```bash
openstack volume create --size 100 --type standard data-vol
openstack server add volume web-01 data-vol
```

Then **inside the VM** (only on first use — re-running mkfs wipes the volume):

```bash
sudo parted -l                         # find the device, e.g. /dev/vdb
sudo mkfs.xfs /dev/vdb                  # FIRST USE ONLY — destroys existing data
sudo mkdir -p /media/volume
sudo mount /dev/vdb /media/volume
sudo chown $USER:$USER /media/volume
# persist across reboot (mount by UUID; device names aren't stable)
UUID=$(blkid -s UUID -o value /dev/vdb)
echo "UUID=$UUID /media/volume xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
```

Detach safely / expand:

```bash
sudo umount /media/volume                       # always unmount before detaching
openstack server remove volume web-01 data-vol
openstack volume set data-vol --size 200        # grow (while detached/Available)
# reattach, mount, then: sudo xfs_growfs /media/volume
```

### Snapshots & images

```bash
# Volume snapshot
openstack volume snapshot create --volume data-vol data-vol-snap
openstack volume create --snapshot data-vol-snap restored-vol   # restore to new volume

# Instance (root-disk) snapshot — power off first for consistency
openstack server stop web-01
openstack server image create --name web-01-image web-01
openstack server start web-01
```

Custom images: install `cloud-init`, keep only minimal accounts, remove SSH host
keys, root as the sole first partition; upload with
`openstack image create --disk-format qcow2 --private --file img.qcow2 <name>`
(images are private to the project; public image creation is disabled).

### Lifecycle / cost control

```bash
openstack server shelve web-01     # STOPS billing (frees compute); preferred for idle VMs
openstack server unshelve web-01   # can be slow for io.*/hpc.*; may fail if cloud is full
openstack server stop web-01       # powers off but STILL BILLS — usually not what you want
```

### Teardown (destructive — generate as code, do NOT run unprompted)

```bash
# Destroys the VM and its ephemeral disk irreversibly; attached volumes survive.
openstack server delete web-01
# Detach + delete a volume (irreversible). Unmount inside the VM first.
openstack server remove volume web-01 data-vol
openstack volume delete data-vol        # needs status Available, no snapshots
openstack floating ip delete <floating-ip>
```

See SKILL.md rule 1 before producing teardown commands, and never run them on
your own initiative.

---

## Sending email from a VM (SMTP relay)

Only the settings are CSC-specific — write ordinary `smtplib`/MTA code around
them:

```
host: smtp.pouta.csc.fi   port: 25   auth: none   TLS: none
```

- **Not `smtp.csc.fi`** — that's CSC-internal and won't relay for cloud users.
- No `login()`/`starttls()`; access is by **source IP**, so mail-sending code
  **only works from the VM**, not from a laptop. Test on the VM
  (`swaks --server smtp.pouta.csc.fi:25 --from you@university.fi --to you@university.fi`).
- Set a valid **envelope sender** (`send_message(msg, from_addr=...)`,
  Postfix `relayhost = [smtp.pouta.csc.fi]:25`) — the relay validates it, and
  it's a different header from `From`.
- Deliverability (SPF `include:hosted-at.csc.fi`) and volume limits: see
  `concepts.md`.

---

## Heat / Terraform

For reproducible, tear-down-and-rebuild infrastructure, prefer
**infrastructure-as-code**: OpenStack **Heat** (`python-heatclient`,
`openstack stack create -t template.yaml mystack`) is fully supported by the
Pouta team; **Terraform** via the OpenStack provider is also widely used and
reads the same `clouds.yaml`. Generate templates rather than imperative
`server create` calls when the user wants repeatable environments.
