---
name: csc-rahti
description: >
  Use Rahti, CSC's container cloud (OpenShift/OKD, Kubernetes-based), correctly
  and safely. Invoke when the user wants to deploy/run/scale a containerised app,
  web service or website on Rahti; work with pods, deployments, services, routes,
  jobs, configmaps/secrets, persistent volumes (PVC) or volume snapshots; build
  or push container images to Rahti's integrated registry (BuildConfig, S2I,
  `oc new-app`, `oc new-build`); use the `oc` CLI or the web console
  (rahti.csc.fi); set up custom domains, TLS, IP allowlists or NetworkPolicies;
  create/manage a Rahti project/namespace and its CSC-project mapping and quota;
  or asks about Rahti concepts (OpenShift vs Kubernetes, non-root containers,
  rahtiapp.fi routes, billing). Can create resources (with clear disclosure of
  cost in BU and public network exposure) but does NOT itself modify or delete
  existing resources — it writes reviewable code/scripts for those.
---

# CSC Rahti (OpenShift container cloud)

Rahti is CSC's **Platform-as-a-Service** container cloud. It runs on
**OKD** (the community distribution that powers Red Hat OpenShift), which is a
Kubernetes distribution. You manage **applications** directly (pods, deployments,
services, routes), not VMs/networks — contrast cPouta, where you manage
infrastructure (use the `csc-pouta` skill for that).

- Web console: `https://rahti.csc.fi` · API: `https://api.2.rahti.csc.fi:6443`
- This is **Rahti 2** (the current generation; hostnames carry `.2.`). The
  cluster is currently OKD **4.20**.
- Apps get an automatic public URL under `*.2.rahtiapp.fi` with a valid TLS
  certificate already installed.

This skill helps you (a) write correct OpenShift/Kubernetes manifests and `oc`
commands and (b) advise on the mechanics, with the CSC-specific quirks built in.

## Operating rules (read first)

1. **Creating new resources is fine — with clear disclosure. Modifying or
   deleting existing resources is the avoid-zone.** This skill can deploy; it
   should not quietly change or tear down what already exists. Three tiers:

   - **Read-only inspection** — always OK to run on request: `oc get`,
     `oc describe`, `oc status`, `oc logs`, `oc projects`/`oc project` (to view),
     `oc whoami`, `oc explain`, `oc get route`/`oc get pvc`, `oc kustomize build`.
   - **Creating new resources** — OK to run, *after* you state plainly what
     you're about to create and the user gives a go-ahead. Covers `oc new-app`,
     `oc new-build`, `oc start-build`, `oc create -f`, `oc expose`, `oc apply -f`
     **of objects that don't yet exist**, `docker/podman push` to the registry,
     creating a project/PVC/route/secret. Two things you must always disclose
     up front:
     - **Cost.** Pods bill on CPU + RAM, and PVCs on storage, by the hour (see
       `concepts.md`) — give a rough BU/h from the requested/used resources so
       the user isn't surprised. A running deployment bills until scaled to 0 or
       deleted.
     - **Public exposure.** A **Route** (or `oc expose`) publishes the app to
       the **open internet** at `*.2.rahtiapp.fi` with a public TLS cert. Say so,
       and for anything not meant to be world-visible, **default to an IP
       allowlist** (`haproxy.router.openshift.io/ip_allowlist`) rather than
       leaving it open — see `concepts.md` / `code-patterns.md`.
   - **Modifying or deleting existing resources** — do NOT run on your own;
     **write a reviewable manifest/script** and let the user run it. This covers
     anything that changes or removes something already live: `oc delete`,
     `oc scale`, `oc edit`, `oc patch`, `oc replace`, `oc rollout`, `oc set`,
     `oc apply -f` **over an object that already exists** (apply is
     create-*or-overwrite*), deleting a project, deleting/expanding a PVC,
     editing a Route/NetworkPolicy in use, rotating a secret.

   The non-clobbering test: **`oc create -f` errors if the object already exists**
   (harmless, like a name clash) — that's a true create. **`oc apply`/`oc replace`
   silently overwrite** an existing object's spec — treat applying over a live
   object as a *modify* (avoid-zone), not a create.

   When asked to do something in the avoid-zone, state plainly and specifically
   what it does and the sharp edges before writing the script:
   - **`oc delete project`** — irreversibly destroys *everything* in the
     namespace, **including data in persistent volumes**. Unrecoverable.
   - **Deleting a PVC** — destroys the volume's data permanently (back up to
     Allas first; see the `csc-allas` skill).
   - **`oc scale --replicas=0`** / `oc delete` of a deployment — stops the app
     (and its billing) but takes the service down.
   - **Every member of the CSC project automatically has admin** on the Rahti
     project — a change or deletion affects everyone, not just you.
   Only run such an operation if the user, after that, clearly confirms — and
   never an `oc delete`, project deletion, or bulk teardown on your own
   initiative.

2. **A Rahti project is a Kubernetes namespace; it maps to a CSC project for
   billing.** Each Rahti project (namespace) must declare `csc_project: <number>`
   (in its description at creation / as a label) — that's the CSC computing
   project whose **Cloud BU quota** it bills against. One CSC project can own
   several Rahti projects, and **its quota is shared across all of them**. The
   `csc_project` label **can't be changed after creation** (contact servicedesk
   or make a new project). All resources live inside one namespace; credentials
   (`oc login` token) are per-user, MFA-gated. See `concepts.md`.

3. **Containers run non-root, as a random UID — design images for it.** Rahti is
   multi-tenant: **no root, no privileged mode**, the pod gets an arbitrary UID
   in **group 0 (root group)**, and apps **can't bind ports <1024** (listen on
   e.g. 8080). An image that needs root or a privileged port will fail to start.
   Make app dirs group-writable (`chmod g+rwx`, `chown :root`) and never bake
   credentials into images. See `concepts.md` for the image checklist.

4. **Prefer the current, non-deprecated path, and say why.** Use **Deployment**,
   not the deprecated **DeploymentConfig** (deprecated since OKD 4.14). In the
   catalog prefer **Helm charts**; **Templates are deprecated** and old
   **builder images** are slated for removal. Use `ip_allowlist`, not the
   deprecated `ip_whitelist`; `oc create token`, not `oc sa get-token`. Never
   hard-code, echo, log, or commit the `oc` login token or any secret (the
   `.gitignore` covers the usual files).

## Quick start: common requests

- **"Deploy my app / this Git repo on Rahti."** Confirm: source (a Git repo →
  S2I `oc new-app <giturl>#<branch>`; a prebuilt image → `oc new-app <image>`;
  raw manifests → `oc create -f`), the **CSC project** to bill, and whether it
  should be **public**. Then disclose rough BU/h and (if exposing) the public
  URL, and either run the create (rule 1 allows it) or generate the manifests
  from `code-patterns.md`. Expose with `oc expose svc/<name>`; get the URL with
  `oc get route`.
- **"Make it reachable from the web."** Create a Route (auto DNS+TLS at
  `<name>-<project>.2.rahtiapp.fi`). **Disclose it's public**; offer an IP
  allowlist by default for non-public services. Custom domain → CNAME to
  `router.2.rahtiapp.fi` + your own cert (see `code-patterns.md`).
- **"Give it persistent storage."** Generate a PVC (`standard-csi`,
  **ReadWriteOnce only**) and mount it. Note: **no online expansion**, and
  deleting the PVC destroys the data — recommend backups to Allas.
- **"Build/push a container image."** Registry is
  `image-registry.apps.2.rahti.csc.fi/<project>/<name>`; log in with
  `docker login -u unused -p $(oc whoami -t) …`. Or build in-cluster with
  `oc new-build` / `oc start-build`. Make the image Rahti-compatible (rule 3).
- **"Scale / update / roll back / delete it."** These touch live objects
  (`oc scale`, `oc set image`, `oc rollout`, `oc delete`) — avoid-zone: write
  the command/manifest as a reviewable script, state the effect, and let the
  user run it.
- **"What will this cost?"** Use the indicative BU/h rates in `concepts.md`
  (pod cores + RAM + PV storage, billed on the *max* of request and actual
  usage), but point at the BU calculator (https://my.csc.fi/buc/) for budgeting
  — rates are reference-only and change (the 2026 rates apply now).

## Reference material

Load the relevant file when you need detail:

- `references/concepts.md` — OpenShift vs Kubernetes and the core objects
  (pod/deployment/service/route, configmap/secret, job, PVC, BuildConfig/
  ImageStream), Rahti projects vs CSC projects & quota, billing model & rates,
  the non-root/random-UID security model and image requirements, networking
  (routes, TLS termination, IP allowlist, NetworkPolicies, egress IP), storage
  (ephemeral/PVC/snapshots, `standard-csi`, no online expand, Allas), the
  registry, deprecations, and gotchas.
- `references/code-patterns.md` — `oc` install & login, project creation with
  the CSC mapping, deploy recipes (from Git/S2I, from image, from YAML, Helm,
  Kustomize), Route + TLS + custom domain + IP allowlist, PVC create/mount/
  snapshot, registry login/tag/push and in-cluster builds, a Rahti-ready
  Dockerfile, and the avoid-zone operations (scale/update/rollback/delete)
  written as reviewable scripts.

When advising on mechanics, prefer these notes over memory; if something here is
silent on a detail, say so rather than inventing CSC-specific behaviour.
