---
name: csc-roihu
description: >
  Use Roihu, CSC's national supercomputer, correctly and safely. Invoke when the
  user wants to run/submit/monitor Slurm batch jobs (sbatch, srun, squeue, seff)
  or interactive sessions; pick a CPU or GPU partition (small, medium, large,
  longrun, hugemem, test, gpumedium, gpularge, gputest, interactive); write job
  scripts for AMD Zen 5 CPU or Nvidia GH200 GPU nodes; connect over SSH — Roihu
  requires a signed SSH certificate (24 h, MyCSC or the certificate-helper-tool
  csc_cert.py); manage data on home/projappl/scratch/dataset disk areas or local
  NVMe ($TMPDIR); compile or install software (modules, x86 vs ARM, containers,
  Tykky);
  migrate from Puhti/Mahti; use the web interface (www.roihu.csc.fi) or Allas;
  or asks about Roihu concepts (billing units, quotas, Lustre, login-node
  policy, HPC etiquette). Generates job scripts, runs read-only inspection, and
  submits jobs only with cost disclosure; does NOT delete data or cancel/modify
  existing jobs — it writes reviewable scripts for those.
---

# CSC Roihu (national supercomputer)

Roihu is CSC's national supercomputer (generally available since June 2026),
replacing **Puhti and Mahti** (compute shut down July/August 2026, storage
mid-October 2026). It has two halves with **different CPU architectures**:

- **Roihu-CPU** — login `roihu-cpu.csc.fi` — 486 nodes, 2×192-core AMD Turin
  9965 (x86, Zen 5, AVX-512) each, 768/1536 GiB; plus 4 hugemem (6 TiB) and
  4 visualization (2× Nvidia L40) nodes.
- **Roihu-GPU** — login `roihu-gpu.csc.fi` — 132 nodes, 4× Nvidia GH200 each
  (H100 GPU + 72-core ARM Grace CPU, 96 GiB GPU + 120 GiB CPU memory per
  superchip).

Batch system is **Slurm**, OS is RHEL9, web interface is
`https://www.roihu.csc.fi`. This skill helps you (a) write correct job
scripts, commands and transfer/install recipes and (b) advise on mechanics,
with CSC quirks built in. For object storage use the `csc-allas` skill; for
cloud VMs `csc-pouta`; for containers-as-a-service `csc-rahti`.

## Operating rules (read first)

1. **Never mix the two architectures.** Binaries, Python environments, and
   containers built on one side do not run on the other. Compile for CPU
   nodes on `roihu-cpu.csc.fi`, for GPU nodes on `roihu-gpu.csc.fi`, and
   **submit each job from the matching login node** — the scheduler will
   accept a cross-submission but the job may fail unpredictably. The file
   system is shared between both sides.

2. **SSH requires a signed certificate — keys alone are not enough.** Users
   sign their MyCSC-registered public key to get an SSH certificate valid
   **24 hours**; then it must be re-signed. Two routes: download from MyCSC
   (Profile → SSH public keys → *Sign and download SSH certificate*), or the
   CSC **certificate helper tool** (`csc_cert.py`, from
   https://github.com/CSCfi/certificate-helper-tool — stdlib-only Python,
   opens MyCSC in the browser, asks for the 6-digit code, installs the cert
   and loads the agent). The certificate is proof of two-factor
   authentication — treat it like a private key: never copy, echo, or commit
   it. The web interface needs no key or certificate (MFA login). Details and
   troubleshooting: `references/code-patterns.md`.

3. **Safety tiers — same model as the other CSC skills:**
   - **Read-only inspection** — fine to run on request: `squeue`, `sinfo`,
     `scontrol show`, `seff`, `sacct` (short ranges only — never in a loop or
     `watch`, and don't query more than a few days at a time), `csc-workspaces`,
     `csc-projects`, `module spider`, `lue` (on subdirectories, not whole
     projects), `ls` (not `ls -l` over huge directories).
   - **Submitting a new job** is a create: OK after disclosing the estimated
     BU cost (see the billing formulas in `concepts.md`) and sanity-checking
     the resource request (right-sized, `test`/`gputest` first for new
     scripts). A submitted job costs real billing units from a **shared
     project allocation**.
   - **Modifying or deleting** — the avoid-zone: `scancel` of running jobs,
     any `rm`/cleanup on `/scratch`, `/projappl`, `/dataset` (there are **no
     backups anywhere on Roihu**; deleted files are unrecoverable, and disk
     areas are shared with every project member), quota changes, and
     `rsync`/`rclone` with `--delete`/`sync` semantics. Write a reviewable
     script, state what it destroys, and run only on explicit confirmation.

4. **Be a good HPC citizen — this includes you, when this session is running
   on Roihu itself.** CSC's usage policy: login nodes are only for compiling,
   managing batch jobs, moving data, and *light* pre/post-processing —
   "light" = **one core, minutes of runtime, < 1 GiB memory**; anything else
   is terminated without warning. So on a login node: no test suites, no
   `make -j`, no data crunching, no model runs — package that work as a batch
   job (`test` partition for smoke tests, 15 min high priority) or an
   interactive session (`sinteractive`), and don't poll `squeue`/`sacct` in
   loops while waiting. CSC's strong preference is that **development happens
   on your own machine and HPC is for running code**: agents/IDEs on Roihu
   are not banned, but the supported pattern is edit-and-test locally (or in
   the web-interface VS Code/Jupyter apps), sync to Roihu, and submit.
   Remote-VS-Code-style computation on login nodes is explicitly unsupported
   by CSC.

5. **Respect the file systems.** Lustre (`/scratch`, `/projappl`, home) is
   built for parallel I/O on large files and melts under small-file/metadata
   load — and it's shared, so abuse slows the whole machine. Hundreds of
   files: fine; thousands: pay attention; hundreds of thousands: don't.
   For I/O-heavy or many-small-file work, **stage onto the node-local NVMe
   `$TMPDIR`** (automatic, free, wiped when the job ends — copy results back)
   and tar/untar datasets rather than copying file trees. Never install conda
   environments directly on Lustre (deprecated by CSC — containerize with
   Tykky/Apptainer), never run databases on `/scratch`, prefer `lue` to `du`,
   and remember scratch is auto-cleaned (files unused 180 days; 90 days for
   ≥ 5 TiB quotas) with no backups.

6. **Right-size and verify.** Request only what the job uses (billing is
   `max(cores, memory)`-based on CPU partitions; full nodes bill fully even
   if undersubscribed; GPUs bill 200 BU/h each). Run `seff <jobid>` after
   completion and adjust. It's better to occasionally hit a limit and rerun
   than to always over-request. Pack many short tasks (< ~30 min) into one
   job (array jobs, or HyperQueue for 100+); don't submit hundreds of tiny
   jobs.

## Quick start: common requests

- **"I can't SSH in / set up my connection."** Check the certificate first —
  it expires every 24 h. `csc_cert.py -u <user> -S` shows status; re-sign via
  the tool or MyCSC. Recipes (ssh config with `CertificateFile`, Windows
  variants, agent forwarding for host-to-host copies): `code-patterns.md`.
- **"Write me a job script."** Ask (or infer): CPU or GPU? project
  (`--account` is mandatory — omitting it gives a misleading
  `AssocMaxSubmitJobLimit` error)? Then pick the partition from the tables in
  `concepts.md` and adapt a template from `code-patterns.md`. Full CPU nodes:
  ntasks×cpus product = 384. GPUs: `--gres=gpu:gh200:N` (max 4/node), 72
  cores + 217 GiB per GPU come with it. Start MPI with `srun`, never
  `mpirun`.
- **"Run this now / give me a shell on a compute node."** `sinteractive
  --account <project>` (CPU) or the `gpuinteractive`/`gputest` route (GPU) —
  from the matching login node. Web interface alternative at
  `www.roihu.csc.fi` (Jupyter, VS Code, desktop; max 16 h).
- **"My job is slow / lots of small files."** Stage to `$TMPDIR` (20 GiB
  shared / 600 GiB full node / 150 GiB per GPU job), untar there, compute,
  copy results back before the job ends. Patterns in `code-patterns.md`.
- **"Move my data from Puhti/Mahti / upload data."** Direct `rsync -aP` (or
  `tar | ssh` for many small files) between systems — not via Allas or your
  laptop. Needs agent forwarding or a pull from Roihu. Deletion-capable
  transfers (`rsync --delete`, `rclone sync`) are avoid-zone.
- **"Install my software / Python env."** Into `/projappl`, from the
  correct login node. venv on top of a CSC module for Python; Tykky
  containers for conda; Spack for HPC codes (still work-in-progress
  upstream). Module names changed from Puhti/Mahti (e.g. `pytorch` →
  `python-pytorch`).
- **"What does it cost?"** CPU: `max(0.75 BU × cores, 0.375 BU × GiB)`/h
  (shared) or 288 BU/node-hour (full nodes); GPU: 200 BU/GPU-hour; hugemem:
  `max(12 BU × cores, 0.25 BU × GiB)`/h. Indicative only — check
  `csc-projects` for balance and MyCSC for authoritative rates.

## Reference material

Load the relevant file when you need detail:

- `references/concepts.md` — system anatomy and the CPU/GPU split, SSH
  certificate model, partition tables (CPU/GPU/interactive) with limits,
  billing formulas and storage rates, disk areas and quotas (incl. dataset
  projects and disaggregated storage), Lustre mechanics and small-file
  thresholds, software environment (modules, compilers, CUDA cc90, conda
  policy, containers), usage policy and HPC etiquette (incl. the
  development-vs-running stance), migration gotchas from Puhti/Mahti, and
  known-preliminary items.
- `references/code-patterns.md` — certificate helper and SSH setup, data
  transfer recipes, ready-to-adapt Slurm scripts (serial/OpenMP/MPI/hybrid/
  full-node/GPU/array/dependency), interactive sessions, local-NVMe staging,
  compiling for x86 and ARM+CUDA, Python/Tykky/Apptainer installs, Allas from
  Roihu (S3 by default — unlike Puhti/Mahti), monitoring commands, and
  avoid-zone operations written as reviewable scripts.

When advising on mechanics, prefer these notes over memory; if something here
is silent on a detail, say so rather than inventing CSC-specific behaviour.
Roihu is new and some features are explicitly preliminary (GPU slices,
disaggregated storage on shared nodes, viz-node `$LOCAL_SCRATCH`, email
notifications, robot accounts) — check `concepts.md` § "Preliminary" before
promising them.
