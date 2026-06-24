# Rahti concepts & CSC quirks

Source: CSC user guide (`cloud/rahti/`). Rahti runs **OKD** (the upstream of Red
Hat OpenShift), a Kubernetes distribution. Web console: `https://rahti.csc.fi`;
API: `https://api.2.rahti.csc.fi:6443`. This is **Rahti 2** (current; `.2.` in
hostnames), OKD **4.20**. CLI-tool downloads: `https://console.rahti.csc.fi/command-line-tools`.

## PaaS, not IaaS

You deploy **applications**, not machines. CSC frames it as: cPouta is a data
centre where you add your own computers; Rahti is one big computer where you
launch applications. Because the cluster is **multi-tenant** (shared with other
users), strict limits apply — most importantly **containers run as a
non-privileged, non-root user** (see Security below). Use Rahti for web apps,
sites, APIs, databases, pre-packaged complex apps; use cPouta/ePouta when you
need root, custom kernels, or VM-level isolation (sensitive data → ePouta).

## Kubernetes / OpenShift objects (the vocabulary)

- **Namespace / Project** — the sandbox holding all your objects. In OpenShift a
  *project* is a namespace plus annotations. "Project" and "namespace" are used
  interchangeably.
- **Pod** — one or more containers sharing an IP; the basic run unit. Pods are
  **expendable** (killed/rescheduled any time, IP changes) — persist anything
  valuable on a PVC, not in the pod.
- **Service** — stable virtual IP + DNS name in front of a set of pods (selected
  by labels); acts as an internal load balancer. Type `ClusterIP` by default.
- **Deployment** — manages a ReplicaSet and rolling updates of stateless pods.
  **Use this.** **DeploymentConfig** is the older OpenShift-specific equivalent,
  **deprecated since OKD 4.14** — don't author new ones.
- **StatefulSet** — like a Deployment but with stable identity + per-pod storage,
  for stateful apps (databases, clustered services).
- **Job** — runs pods to completion N times (batch tasks). Object names are
  unique per namespace, so a Job can't be re-run until the old one is removed.
- **ConfigMap / Secret** — config data injected as env vars or mounted files.
  Secrets are only **base64-encoded** (not encrypted) and hidden from default
  output; editing them is fiddly (get JSON → base64-decode → edit → re-encode →
  `oc replace`). Don't treat base64 as protection.
- **Route** (OpenShift) — exposes a Service to the internet over HTTP/HTTPS; the
  OpenShift equivalent of a Kubernetes Ingress (see Networking).
- **ImageStream** — abstracts container images and emits triggers when a new
  image is pushed. **BuildConfig** — builds images (Docker/S2I strategy) into an
  ImageStream; trigger with `oc start-build`.
- **PersistentVolumeClaim (PVC)** — a request for durable storage (see Storage).

Everything is described in YAML/JSON and created via the API (`oc create -f`,
`oc apply -f`). `oc` is OpenShift's CLI; `kubectl` also works but OpenShift-only
features (routes, builds, `oc new-app`) need `oc`.

## Rahti project vs CSC project, quota & access

- A **Rahti project = a Kubernetes namespace**. A **CSC computing project** is
  the billing/membership entity at `my.csc.fi`. Every Rahti project must map to
  exactly one CSC project via **`csc_project: <number>`** — set in the project
  **Description** at creation (web console) or `--description='csc_project: 1000123'`
  (CLI). It becomes the `csc_project` **label** on the namespace.
- **The label can't be changed by normal users after creation** — contact
  servicedesk, or create a new project with the right label.
- **One CSC project can own several Rahti projects**, and the **quota is shared**
  across all of them. **All members of the CSC project automatically get admin**
  on its Rahti projects — blast radius of any change/deletion is everyone.
- **Access**: apply for the Rahti service on the project at
  `https://my.csc.fi/projects` → accept terms → CSC approves (can take a while;
  allow up to ~30 min, sometimes hours, to propagate). **MFA is required** for
  login (since 2025-11-25). A "User not found" error usually means access hasn't
  propagated / isn't granted yet.

### Default quota (per CSC computing project)

| Resource | Initial quota |
|---|---|
| Virtual cores (CPU) | 4 |
| RAM | 16 GiB |
| Storage (PVCs) | 100 GiB |
| Image streams | 20 |
| Size of each registry image | 5 GiB |

Raise via Service Desk (case-by-case). Inspect live:
`oc describe AppliedClusterResourceQuotas` and `oc describe limitranges`
(or web console **Administration → ResourceQuota / LimitRanges**).

### Per-pod requests/limits

Every container has **requests** (minimum reserved) and **limits** (hard cap).
If you set none, the **defaults** apply:

| | CPU | Memory |
|---|---|---|
| limits | 500m | 1Gi |
| requests | 100m | 500Mi |

(`m` = millicores; `500m` = half a core.) Rahti enforces a **max limit/request
ratio of 5** (e.g. request 50m → limit ≤ 250m; to allow a 1-core limit, request
≥ 200m). Exceeding the **memory limit** kills the pod (OOM, exit 137); exceeding
the **CPU limit** only throttles it. Add ~10–20 % headroom over expected use.

## Billing

Billed in **Cloud Billing Units (BU)**, hourly, from scraped usage. Three things
bill; **for CPU and memory the billed amount is `max(request, actual usage)`** —
so a generous *request* costs even when idle.

| Resource | BU per hour |
|---|---|
| Pod core·hour | **1.05** |
| Pod RAM GB·hour | **1.6** |
| Storage TiB·hour | **3.6** |

> These are the **2026** rates (a slight adjustment from prior years) and are
> **indicative** — confirm budgets with the BU calculator (`https://my.csc.fi/buc/`).
> Rahti currently does **not** bill for stored images.

Example: a pod requesting 1 core + 512 MiB, actually using 0.5 core + 1 GiB,
bills on `max` → 1 core and 1 GiB. To stop a deployment's billing without
deleting data, **scale it to 0** (`oc scale --replicas=0` — an avoid-zone op,
since it takes the app down); the PVC keeps billing for its storage.

## Security model (the important part)

Rahti enforces multi-tenant isolation; you can't opt out:

- **No root, no privileged containers.** Images requiring `USER root` or
  privileged mode fail to deploy.
- **Random UID, group 0.** Each pod is assigned an arbitrary UID (e.g.
  `1000620000`) belonging to the **root *group* (GID 0)** — you don't choose the
  UID. The **restricted-v2** SCC applies: `allowPrivilegeEscalation` must be
  empty/false, capabilities dropped (only `NET_BIND_SERVICE` allowed), seccomp
  `runtime/default`.
- **No privileged ports.** Can't bind <1024; listen on e.g. **8080**/8081 and
  let the Service map it.

### Making an image Rahti-compatible

- Don't run as a fixed non-zero UID alone — support an **arbitrary** UID. Make
  the dirs the app writes **group-writable and owned by group root**:
  `chmod g+rwx <dirs>` and `chown <user>:root <dirs>` (also `chmod g=u` for
  files the random UID must read/write).
- Change any privileged listen port to ≥1024 (e.g. nginx `listen 80;` → `8081;`).
- `EXPOSE` the unprivileged port; set `USER <name>:root` (or `USER 1001`).
- Prefer small, trusted base images; keep build-time deps out of the runtime
  image (multi-stage builds); use `.dockerignore`. Don't bake in secrets.

You are responsible for the security of what you expose. Use modern TLS (v1.2+;
v1.3 preferred), restrict access (IP allowlist / NetworkPolicy) for anything not
meant to be fully public, and add an HSTS header where appropriate
(`oc annotate route <r> haproxy.router.openshift.io/hsts_header='true'`).

## Networking

- **Routes expose Services to the internet over HTTP(80)/HTTPS(443) only.** Any
  host matching **`*.2.rahtiapp.fi`** (or the older `*.rahtiapp.fi`) gets an
  automatic **DNS record + valid TLS certificate**. Default hostname is
  `<route-name>-<project>.2.rahtiapp.fi` unless you set `spec.host`. Non-HTTP
  protocols and other ports aren't exposed via Routes (LoadBalancer services
  exist for special cases, with port range 30000–35000).
- **TLS termination** modes on a Route: **edge** (Route holds the cert, talks
  plain HTTP to the pod — simplest, default), **passthrough** (pod terminates
  TLS itself), **reencrypt** (Route→pod re-encrypted). `insecureEdgeTerminationPolicy:
  Redirect` sends HTTP→HTTPS.
- **Custom domain**: point a **CNAME to `router.2.rahtiapp.fi`** (or an A record
  to `195.148.21.61`), set `spec.host`, and supply your own `certificate` + `key`
  in the Route's `tls` block (or use cert-manager + Let's Encrypt).
- **IP allowlist** (strongly recommended for non-public services):
  `oc annotate route <r> haproxy.router.openshift.io/ip_allowlist='193.166.0.0/16 203.0.113.7'`
  (space-separated IPs/CIDRs). The old `ip_whitelist` is **deprecated**.
  **Warning:** a *malformed* allowlist is discarded and **all traffic is
  allowed** — validate the syntax.
- **NetworkPolicies**: namespaces are **isolated by default** (two default
  NetworkPolicies; outside traffic only reaches pods via a Route). Add policies
  to allow traffic from another namespace or to IP-allowlist
  LoadBalancer/internal traffic.
- **Egress IP**: outgoing traffic from Rahti workloads currently leaves from
  **`86.50.229.150`** (may change; dedicated egress IPs for a namespace on
  request to servicedesk@csc.fi). Rahti is **IPv4-only**.

## Storage

- **Ephemeral (`emptyDir`)** — fast local scratch shared by a pod's containers;
  **lost when the pod is killed/restarted**. Optionally memory-backed
  (`medium: Memory`, counts against the pod's memory). Keep nothing valuable.
- **Persistent volume (PVC)** — durable, CEPH-backed. The StorageClass is
  **`standard-csi`** and only **ReadWriteOnce (RWO)** is available (mountable
  read-write by **one pod at a time** — more classes/RWX are "in the works").
  A PVC is provisioned lazily, the first time it's mounted. **Deleting a PVC
  deletes its data permanently** — back up to Allas (see the `csc-allas` skill).
  With RWO, set the deployment update strategy to **Recreate** (not RollingUpdate)
  so the old pod releases the volume before the new one mounts it.
- **No online expansion.** Editing a PVC's size is rejected (`spec is immutable…`).
  To grow: create a new PVC (use sizes in **multiples of 8 GiB**), `oc scale`
  the app to 0, copy data across in a helper pod (`rsync`), repoint the
  deployment, scale back up. (All but the create are avoid-zone — script them.)
- **Volume snapshots** — `VolumeSnapshot` with class `standard-csi`; the PVC
  **must not be in use** by any pod when you snapshot. Restore by creating a PVC
  with a `dataSource` referencing the snapshot.
- **Object storage (Allas)** — Rahti has **no built-in Allas StorageClass**.
  Access Allas from a pod with S3 credentials + `rclone`/SDK (endpoint
  `https://a3s.fi`); see the `csc-allas` skill. Batch many small files into a
  `tar` for throughput. PVC storage bills at 3.6 BU/TiB·h.
- High-file-count volumes (>15,000 files) can take **>5 min to mount**.

## Container registry

- Integrated registry: **`image-registry.apps.2.rahti.csc.fi`**; images live at
  `image-registry.apps.2.rahti.csc.fi/<project>/<name>:<tag>`. From inside the
  cluster: `image-registry.openshift-image-registry.svc:5000/<project>/<name>`.
- Log in with your `oc` token: `docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi`.
  For CI, use a **service-account token** (`oc create token <sa>`), not
  `oc sa get-token` (deprecated).
- Max image size **5 GiB** (the quota's per-image cap); keep images small. If a
  push 500s on the manifest HEAD, create the ImageStream first
  (`oc create imagestream <name>`). Image storage is currently **not billed**.

## Deploying & building

- **From a Git repo (S2I)**: `oc new-app <giturl>#<branch>` auto-detects the
  language, creates ImageStream + BuildConfig + Deployment + Service. **Default
  Git ref is `master`** — pass `#main` if your repo uses it (a common gotcha
  with GitHub webhooks).
- **From an existing image**: `oc new-app <image>`.
- **From manifests**: `oc create -f file.yaml` (or `oc apply -f` for new
  objects; see SKILL.md rule 1 on apply-vs-create).
- **In-cluster build from a local dir**: `oc new-build --binary --name=x` then
  `oc start-build x --from-dir=./ -F`.
- **Catalog**: prefer **Helm charts**; **Templates are deprecated** and old
  **builder images** are slated for removal.
- **CI/CD**: trigger rebuilds via a BuildConfig **webhook** (GitHub/GitLab/
  Bitbucket/Generic) — copy the webhook URL from the BuildConfig and add the
  matching secret. Or `oc start-build` from your pipeline.

## Known gotchas

- **`oc apply` is create-*or-overwrite*** — re-applying over a live object
  silently changes it. Use `oc create` for a guaranteed non-clobbering create.
- **`oc new-app` warns when a base image runs as root** — it'll still create the
  objects, but the pod will likely crash-loop until you fix the image (rule 3).
- **Default Git branch is `master`**, not `main` — builds/webhooks silently
  watch the wrong ref otherwise.
- **RWO PVC + RollingUpdate** deadlocks (old pod won't release the volume) — use
  the **Recreate** strategy.
- **Usernames are case-sensitive** when sharing a project, and Rahti won't
  validate a non-existent username — a typo silently grants nobody.
- **`oc delete project` and PVC deletion are irreversible**, including PV data.
- **Quota is shared** across all Rahti projects under one CSC project.
