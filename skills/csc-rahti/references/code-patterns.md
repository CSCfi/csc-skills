# Rahti code patterns

Adapt to the user's task. Per SKILL.md rule 1: **creating new resources** may be
run (after disclosing BU cost and public exposure); **modifying or deleting
existing resources** (scale, edit, patch, replace, rollout, delete, apply over a
live object) is written as a **reviewable script**, not run on your own
initiative. Never hard-code, echo, log, or commit the `oc` login token or any
secret.

Endpoints: console `https://rahti.csc.fi`, API `https://api.2.rahti.csc.fi:6443`,
registry `image-registry.apps.2.rahti.csc.fi`, route domain `*.2.rahtiapp.fi`.

---

## Install & log in

Download `oc` (and `kubectl`) from the console:
`https://console.rahti.csc.fi/command-line-tools` → put the binary on your PATH
(`oc --help` to verify).

Log in: in the web console, click your name → **Copy login command** → it gives
a token-based command. Paste it (the token is a short-lived credential — don't
echo/commit it):

```bash
oc login https://api.2.rahti.csc.fi:6443 --token=<token-from-web-console>
oc whoami            # sanity check (read-only)
oc projects          # list projects you can see
oc project <name>    # switch active project
```

---

## Create a project (with the CSC-project mapping)

The `csc_project` mapping is mandatory and **cannot be changed later**.

```bash
# Creating a namespace is non-clobbering (name clash just errors). Disclose which
# CSC project it bills before running.
oc new-project my-unique-project-name \
  --description='csc_project: 1000123' \
  --display-name='My web app'

# Verify the mapping took:
oc get project my-unique-project-name -o yaml | grep -A2 labels   # look for csc_project
```

Web console: **Create Project** → put `csc_project: 1000123` in the Description.

---

## Deploy an application

### From a Git repo (Source-to-Image)

```bash
# Auto-detects language; creates ImageStream + BuildConfig + Deployment + Service.
# Default branch is master — append #main if needed.
oc new-app https://github.com/CSCfi/nodejs-16-rahti-example.git
oc logs -f bc/nodejs-16-rahti-example          # watch the build (read-only)
oc expose svc/nodejs-16-rahti-example          # create a public Route (DISCLOSE: public)
oc get route nodejs-16-rahti-example           # the resulting *.2.rahtiapp.fi URL
```

### From an existing image

```bash
oc new-app image-registry.apps.2.rahti.csc.fi/<project>/my-image:latest --name=myapp
oc expose svc/myapp
```

### From manifests (Deployment + Service + Route)

`oc create -f` is a true create (errors if the object exists). Disclose the BU/h
(from the requests) and, for the Route, that the app becomes **public**.

```yaml
# app.yaml — note: non-root friendly (containerPort 8080), explicit resources
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels: { app: myapp }
spec:
  replicas: 1
  selector: { matchLabels: { app: myapp } }
  strategy: { type: Recreate }        # use Recreate if it mounts an RWO PVC
  template:
    metadata: { labels: { app: myapp } }
    spec:
      containers:
      - name: myapp
        image: image-registry.openshift-image-registry.svc:5000/<project>/myapp:latest
        ports: [ { containerPort: 8080 } ]
        resources:
          requests: { cpu: 100m, memory: 256Mi }   # billed on max(request, usage)
          limits:   { cpu: 500m, memory: 512Mi }   # limit/request ratio ≤ 5
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels: { app: myapp }
spec:
  selector: { app: myapp }
  ports: [ { name: 8080-tcp, port: 8080, targetPort: 8080, protocol: TCP } ]
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp
  labels: { app: myapp }
  annotations:
    # Recommended unless the app is meant to be world-visible:
    haproxy.router.openshift.io/ip_allowlist: '193.166.0.0/16'
spec:
  to: { kind: Service, name: myapp, weight: 100 }
  port: { targetPort: 8080 }
  tls: { termination: edge, insecureEdgeTerminationPolicy: Redirect }   # HTTP→HTTPS
  # host: omitted → defaults to myapp-<project>.2.rahtiapp.fi
```

```bash
oc create -f app.yaml      # true create
```

### Helm (preferred over deprecated Templates)

```bash
helm install myrelease <chart> --namespace <project>   # creates the release's objects
```

### Kustomize

```bash
oc kustomize build overlays/production            # render only (read-only)
oc apply -k overlays/production                   # create new objects (disclose if it overwrites live ones)
```

---

## Inspect / debug (read-only — safe to run)

```bash
oc get pods                       # also: deploy, svc, route, pvc, is, bc, all
oc describe pod <pod>
oc logs -f <pod>                  # -c <container> for a specific container
oc rsh <pod>                      # interactive shell in the pod
oc status
oc get route <name> -o jsonpath='{.spec.host}'
oc describe AppliedClusterResourceQuotas   # quota usage
oc describe limitranges
```

---

## Routes, TLS & custom domains

```bash
# Add an IP allowlist to an existing route (modifies a live object → reviewable).
oc annotate route <route> haproxy.router.openshift.io/ip_allowlist='193.166.0.0/16 203.0.113.7'
oc annotate route <route> haproxy.router.openshift.io/hsts_header='true'
```

Custom domain: create a **CNAME → `router.2.rahtiapp.fi`** (or A → `195.148.21.61`),
then a Route carrying your cert:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata: { name: myapp }
spec:
  host: app.example.org
  to: { kind: Service, name: myapp, weight: 100 }
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
    certificate: |-
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
    key: |-
      -----BEGIN PRIVATE KEY-----
      ...        # the private key is a secret — keep this manifest out of git
      -----END PRIVATE KEY-----
```

(Or automate certs with cert-manager + a Let's Encrypt `Issuer`/`Certificate`
using the `openshift-default` ingress class.)

---

## Persistent storage

`standard-csi`, **ReadWriteOnce only**, no online expansion, deleting it
destroys the data.

```yaml
# pvc.yaml — a true create
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data-pvc }
spec:
  accessModes: [ ReadWriteOnce ]
  storageClassName: standard-csi
  resources: { requests: { storage: 8Gi } }   # multiples of 8 GiB recommended
```

Mount it in the pod spec:

```yaml
      volumes:
      - name: data
        persistentVolumeClaim: { claimName: data-pvc }
      containers:
      - name: myapp
        # ...
        volumeMounts: [ { name: data, mountPath: /data } ]
```

Snapshot (PVC must not be mounted by any pod):

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: { name: data-snap }
spec:
  volumeSnapshotClassName: standard-csi
  source: { persistentVolumeClaimName: data-pvc }
```

Backing a volume up to Allas (run inside/against a pod; see the `csc-allas`
skill for credentials). Tar small files first for throughput:

```bash
oc exec <pod> -- sh -c 'tar -czf /tmp/backup.tgz -C /data .'
oc cp <pod>:/tmp/backup.tgz ./backup.tgz
rclone --config rclone.conf copy ./backup.tgz allas-s3:my-bucket/   # endpoint https://a3s.fi
```

---

## Container registry: log in, tag, push

```bash
# Token login (the token is a credential — don't echo/commit it):
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi
# (podman works the same; some setups need sudo + sudo oc login)

docker tag myapp:latest image-registry.apps.2.rahti.csc.fi/<project>/myapp:latest
docker push          image-registry.apps.2.rahti.csc.fi/<project>/myapp:latest   # ≤ 5 GiB
```

For CI, use a service-account token (not the deprecated `oc sa get-token`):

```bash
oc create serviceaccount pusher
oc policy add-role-to-user system:image-pusher -z pusher
docker login -u unused -p "$(oc create token pusher --duration=87600h)" \
  image-registry.apps.2.rahti.csc.fi
```

### Build in-cluster instead of pushing

```bash
oc new-build --binary --name=myapp --to=myapp:latest
oc start-build myapp --from-dir=./ -F      # Dockerfile in ./, streams output
# multi-stage / from Git:
oc new-build https://github.com/<org>/<repo>.git
```

---

## A Rahti-ready Dockerfile (non-root, arbitrary UID, group 0)

```dockerfile
FROM nginx:alpine
# Make the dirs the app writes group-writable and owned by group root,
# because Rahti runs the container as a random UID in group 0.
RUN chmod g+rwx /var/cache/nginx /var/run /var/log/nginx && \
    chown -R nginx:root /var/cache/nginx /var/run /var/log/nginx && \
    # privileged ports (<1024) are not allowed — listen on 8081 instead of 80
    sed -i 's/listen\(.*\)80;/listen 8081;/' /etc/nginx/conf.d/default.conf && \
    # OpenShift sets the user anyway — drop the `user` directive
    sed -i 's/^user/#user/' /etc/nginx/nginx.conf
EXPOSE 8081
USER nginx:root
```

Keep it small: combine `RUN`s, use a `.dockerignore`, prefer multi-stage builds
(build in a fat image, `COPY --from=builder` only the artifact into a slim one),
keep data out of the image (mount a PVC or pull from Allas at start).

---

## Sending email from a pod (SMTP relay)

Only the settings are CSC-specific — write ordinary mail code around them:

```
host: smtp.pouta.csc.fi   port: 25   auth: none   TLS: none
```

- **Not `smtp.csc.fi`** — that's CSC-internal and won't relay for cloud users.
- No credentials to mount; the relay authorises by **source IP** (Rahti nodes
  qualify), so it **only works from a pod**, not from a laptop — test from
  inside: `oc exec deploy/myapp -- python -c '...'` (or `swaks`, if the image
  has it).
- Set a valid **envelope sender** — the relay validates it, and it's a different
  header from `From`.
- Host, port and sender are **not secrets** — a ConfigMap referenced via
  `envFrom` keeps the image portable, no Secret needed:
  `oc create configmap smtp-config --from-literal=SMTP_HOST=smtp.pouta.csc.fi
  --from-literal=SMTP_PORT=25 --from-literal=MAIL_SENDER=you@university.fi`
  (wiring it into a *live* deployment with `oc set env` is avoid-zone).
- Deliverability (SPF `include:hosted-at.csc.fi`) and volume limits: see
  `concepts.md`.

---

## Avoid-zone: modifying / deleting live resources (write, don't run)

Per rule 1, generate these as a reviewable script and let the user run them;
state the effect first. None should be run on your own initiative.

```bash
# Scale (changes a live deployment; --replicas=0 stops the app AND its billing):
oc scale --replicas=3 deploy/myapp
oc scale --replicas=0 deploy/myapp        # downtime

# Update the running image / roll back:
oc set image deploy/myapp myapp=image-registry.apps.2.rahti.csc.fi/<project>/myapp:v2
oc rollout status deploy/myapp
oc rollout undo deploy/myapp

# Edit / patch / replace a live object (overwrites current spec):
oc edit deploy/myapp
oc apply -f app.yaml          # over an EXISTING object this is an overwrite, not a create
oc set resources deploy/myapp --limits=cpu=1,memory=1Gi --requests=cpu=200m,memory=512Mi

# Destructive — irreversible, and the CSC project is shared:
oc delete all --selector app=myapp        # removes the app's objects
oc delete pvc data-pvc                     # DESTROYS the volume's data permanently
oc delete project my-project               # DESTROYS everything incl. PV data
```

See SKILL.md rule 1 before producing any of these, and never run a delete,
project teardown, or scale-to-zero on your own initiative.
