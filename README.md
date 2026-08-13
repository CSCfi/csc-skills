# csc-skills

Claude Code skills for using CSC infrastructure correctly, safely, and in a
streamlined way. Each subdirectory is a self-contained skill.

## Available skills

- **csc-allas** — use [Allas](https://docs.csc.fi/data/Allas/), CSC's object
  storage. Generates code/scripts (boto3, aws-cli, s3cmd, rclone) for reading, writing,
  listing, sharing and publishing Allas data; advises on the mechanics (CSC
  projects & credentials, public/private buckets, ACLs, bucket policies,
  lifecycle, S3 vs Swift). Defaults to S3, and does not run destructive Allas
  operations on your behalf.

- **csc-pouta** — use [Pouta](https://docs.csc.fi/cloud/pouta/), CSC's OpenStack
  IaaS cloud (cPouta, plus ePouta for sensitive data). Generates code/scripts
  (openstack CLI, openstacksdk, Heat/Terraform) for launching and managing VMs,
  volumes, snapshots, images, networking, security groups and SSH access;
  advises on the mechanics (CSC projects/tenants, flavors, billing & shelving,
  ephemeral vs persistent storage, application credentials, sending mail via the
  `smtp.pouta.csc.fi` relay). Can create
  resources with clear disclosure of cost/exposure, but does not modify or
  delete existing OpenStack resources on your behalf.

- **csc-roihu** — use [Roihu](https://docs.csc.fi/computing/systems-roihu/),
  CSC's national supercomputer (successor to Puhti and Mahti). Generates Slurm
  job scripts (CPU and GH200 GPU partitions), SSH-certificate setup (24 h
  certificates via MyCSC or the certificate helper tool), data-transfer and
  software-install recipes; advises on the mechanics (the x86/ARM
  architecture split, partitions and billing units, disk areas and quotas,
  Lustre vs node-local NVMe, login-node policy and HPC etiquette). Runs
  read-only inspection and submits jobs only with cost disclosure; does not
  delete data or cancel/modify existing jobs on your behalf.

- **csc-rahti** — use [Rahti](https://docs.csc.fi/cloud/rahti/), CSC's container
  cloud (OpenShift/OKD, a Kubernetes-based PaaS). Generates manifests and `oc`
  commands for deploying and running containerised apps — pods, deployments,
  services, routes, jobs, persistent volumes (PVC) and snapshots — building and
  pushing images to the integrated registry (BuildConfig, S2I, `oc new-app`),
  custom domains/TLS/IP allowlists, and project/quota setup; advises on the
  mechanics (OpenShift vs Kubernetes, the non-root multi-tenant security model,
  `*.rahtiapp.fi` routes, sending mail via the `smtp.pouta.csc.fi` relay,
  billing). Can create resources with clear disclosure
  of cost (BU) and public exposure, but does not modify or delete existing
  Rahti resources on your behalf.

## Installing

This repo is a Claude Code **plugin marketplace**. The recommended way to
install — and to get updates by pulling — is via the plugin system. In Claude
Code, first register the marketplace:

```
/plugin marketplace add https://github.com/CSCfi/csc-skills.git
```

Then install the plugin (one plugin bundles all the skills):

```
/plugin install csc-skills@csc-skills
```

The form is `<plugin>@<marketplace>`; here the plugin and the marketplace are
both named `csc-skills`. After the marketplace is added, `/plugin` also lets you
browse and toggle plugins interactively. Updating is `git pull` in the
marketplace checkout, or re-running `/plugin marketplace add` to refresh.

Skills are loaded on demand — Claude only pulls a skill into context when its
description matches what you're doing — so installing the whole plugin costs
nothing for the skills you don't happen to use.

### Manual install (without the plugin system)

Skills are also discovered from `~/.claude/skills/`. To install them for your
user without the plugin system:

```bash
cp -r skills/csc-* ~/.claude/skills/
```

Or symlink an individual skill so it tracks the repo:

```bash
ln -s "$PWD/skills/csc-allas" ~/.claude/skills/csc-allas
```

Either way, ask Claude Code something a skill covers (e.g. "upload this result
to an Allas bucket") and it will pick the skill up automatically.

## Layout

```
csc-skills/
├── .claude-plugin/
│   ├── plugin.json        # plugin manifest (source ".": the repo is the plugin)
│   └── marketplace.json   # marketplace manifest (lists this one plugin)
├── README.md
└── skills/
    └── csc-allas/         # one directory per skill
        ├── SKILL.md
        └── references/
```

## Contributing — adding a skill

Add a new directory under `skills/` with a `SKILL.md` (YAML frontmatter `name` +
`description`, then the body) and optional `references/*.md` files loaded on
demand. The plugin auto-discovers everything under `skills/`, so no manifest
edits are needed for a new skill. CSC-specific facts should be sourced from the
[CSC user guide](https://docs.csc.fi/).
