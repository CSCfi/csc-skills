# Roihu concepts — mechanics and CSC quirks

Source of truth: https://docs.csc.fi (computing section, `systems-roihu`,
`roihu-disk`, `running/*`, `connecting/*`, `usage-policy`, `lustre`,
`hpc-billing`) and the CSC "efficient use" training material
(https://github.com/csc-training/csc-env-eff). Facts below were extracted
2026-08; rates, quotas and preliminary features drift — re-verify anything
budget- or deadline-critical against docs.csc.fi.

## System anatomy: one machine, two architectures

| Node | Count | Compute | Cores | Memory | Local disk |
|------|------:|---------|-------|--------|-----------:|
| M    | 414 | AMD Turin 9965 | 2×192 (x86) @ 2.25 GHz | 768 GiB | 0.96 TB |
| L    | 72  | AMD Turin 9965 | 2×192 (x86) @ 2.25 GHz | 1536 GiB | 0.96 TB |
| XL (hugemem) | 4 | AMD Turin 9555 | 2×64 (x86) @ 3.20 GHz | 6144 GiB | 15.36 TB |
| V (viz) | 4 | AMD Turin 9335 + 2× Nvidia L40 | 2×32 (x86) | 384 GiB + 2×48 GB | 15.36 TB |
| GPU  | 132 | 4× Nvidia GH200 | 4×72 (ARM) | 4×120 GiB CPU + 4×96 GiB GPU | 0.96 TB |

- **Roihu-CPU** (x86_64, Zen 5, supports AVX-512): login nodes
  `roihu-cpu.csc.fi` (`roihu-cpu-login1..4`).
- **Roihu-GPU** (aarch64, Grace CPU + Hopper H100): login nodes
  `roihu-gpu.csc.fi` (`roihu-gpu-login1..2`).
- Same Lustre file systems are mounted on both sides — files are shared,
  binaries are not. **Software (including Python envs and containers with
  native code) must be built and run on the same architecture**, and jobs
  must be submitted from the matching login node: the interactive/batch
  environment inherits the login node's modules, and cross-arch submissions
  "may fail unpredictably" (docs' words).
- Network: InfiniBand NDR — 1× 200 Gb/s per CPU node, 4× 200 Gb/s (one per
  GPU) per GPU node. OS: RHEL9.
- Sizing: 186 624 x86 cores; 528 GPUs; ~34 PFlop/s aggregate HPL.

### Access prerequisites

- A CSC project with the **Roihu service enabled in MyCSC** (not all projects
  have it; `csc-workspaces` on the system shows which of your projects do).
- **Medium or high level of identity assurance (LoA)** on the CSC account.
- Existing CPU/GPU/storage billing units work on Roihu — no new application
  needed if BUs remain.

## SSH certificates (new vs Puhti/Mahti)

Plain SSH keys are not enough: the public key registered in MyCSC must be
**signed** to produce a certificate (`~/.ssh/id_<alg>-cert.pub`), and each
certificate is **valid for 24 hours**. The certificate is proof of a
completed two-factor authentication at MyCSC — never share, copy, log, or
commit it (with the private key it grants account access). Key types: Ed25519
(strongly recommended) or RSA 4096–16384. `ssh-copy-id` and
`~/.ssh/authorized_keys` do not work on CSC systems; keys go through MyCSC.
Unlike Puhti/Mahti there is no ~1 h propagation delay — certificates work
immediately.

Two signing routes (details in `code-patterns.md`):

1. **MyCSC download** — Profile → SSH PUBLIC KEYS → ⋮ → *Sign and download
   SSH certificate*; save next to the private key with the exact name
   `<key>-cert.pub` (OpenSSH finds certificates by naming convention).
2. **Certificate helper tool** — `csc_cert.py` from
   https://github.com/CSCfi/certificate-helper-tool (Python ≥ 3.8, stdlib
   only). Prints/opens a MyCSC login URL, you paste a 6-digit code, it writes
   the cert (and on Windows a `-cert.ppk`) and loads ssh-agent/Pageant.
   No auto-renew daemon — rerun when expired (`-r` forces refresh, `-S`
   shows status).

Other access paths:

- **Web interface** `https://www.roihu.csc.fi` — MFA login (CSC/Haka/Virtu),
  no key or certificate needed. Files, shell, batch-job view, quotas, and
  interactive apps (Jupyter, marimo (Roihu-only), RStudio, R-Jupyter, MATLAB,
  VS Code, TensorBoard, MLflow, Desktop, Accelerated Visualization on L40s).
  Max interactive job length 16 h; partitions exposed: `interactive`,
  `small`, `test`, `gputest` (+ `vizinteractive` for visualization).
- **FirecREST v2 REST API** at `https://api.roihu.csc.fi` (subsystems `cpu`
  and `gpu`); personal JWT tokens from MyCSC, 24 h validity. Robot accounts
  not yet supported (expected Q3 2026).
- **No direct SSH to compute nodes** (not yet configured). To reach a node
  where your job runs: `srun --jobid=<jobid> --overlap --pty bash`.
- `screen` is not available on Roihu; use `tmux` for long login-node
  transfers.

## Slurm partitions

Allocation types: **R** = shared node, CPU and memory requested
independently; **N** = full nodes only; **C** = memory fixed per requested
core; **G** = CPU and memory fixed per requested GPU.

### CPU partitions (submit from roihu-cpu)

| Partition | Type | Time limit | Nodes | Max CPUs | Max memory | Notes |
|-----------|------|-----------|-------|----------|------------|-------|
| `test`    | R | 15 min  | 1–2  | 384/node | 744 GiB/node | high priority; for smoke tests |
| `small`   | R | 72 h    | 1    | 384/job  | 1500 GiB/job | the default workhorse; serial + partial node |
| `medium`  | N | 36 h    | 1–6  | 384/node | 744 GiB/node | full nodes only |
| `large`   | N | 36 h    | 6–60 | 384/node | 744 GiB/node | requires approved scalability test |
| `longrun` | R | 10 days | 1    | 192/job  | 1500 GiB/job | lower priority — use shorter if you can |
| `hugemem` | C | 36 h    | 1    | 128/job  | 6037 GiB/job | XL nodes |
| `hugemem_longrun` | C | 10 days | 1 | 128/job | 6037 GiB/job | XL nodes |
| `interactive` | R | 36 h | 1   | 32/job   | 64 GiB/job | high priority, for `sinteractive` |

### GPU partitions (submit from roihu-gpu)

| Partition | Type | Time limit | Nodes | GPUs | Memory | Notes |
|-----------|------|-----------|-------|------|--------|-------|
| `gputest`   | G | 15 min | 1–2  | 1–4/node | 217 GiB/GPU | high priority; smoke tests |
| `gpumedium` | G | 36 h   | 1–4  | 1–4/job  | 217 GiB/GPU | |
| `gpularge`  | G | 36 h   | 1–10 | min 4, 4/node | 217 GiB/GPU | requires scalability test + GPU-utilization evidence |
| `gpuinteractive` | G | 12 h | 1 | GPU slices (TBA) | TBA | slices (1/7 GH200, 12 GiB) **not yet configured** — currently gives full GPUs |

Each reserved GH200 GPU brings up to **72 ARM cores** and **217 GiB memory**
(95 GiB HBM3 + 122 GiB LPDDR5) — request the cores explicitly
(`--cpus-per-task`), but they don't bill separately. `--gres=gpu:gh200:N` is
per node, max 4.

Visualization: `vizinteractive` (G, 12 h, 1 node, max 2 L40 GPUs/job; each
L40 grants 32 cores + 183 GiB).

`large`/`gpularge` access: apply in MyCSC, 30-day test period, submit a
scalability report — minimum **75 % parallel efficiency** (≥1.5× speedup when
doubling nodes), tested at ≥3 node counts; `gpularge` also needs demonstrated
GPU utilization.

Inspection: `sinfo --summarize`, `scontrol show partition <name>`.

### Job-script rules that differ from Puhti/Mahti

- `--account=<project>` is **mandatory**; omitting it fails with the
  misleading error `AssocMaxSubmitJobLimit ... Job violates accounting/QOS
  policy`.
- Full M/L nodes have **384 cores**: on `medium`/`large` don't use
  `--ntasks`; use `--ntasks-per-node` × `--cpus-per-task` = 384 (hugemem:
  = 128). Billing is per full node regardless of how much you use.
- Start MPI programs with **`srun`**, never `mpirun`/`mpiexec`; load the MPI
  module inside the script.
- **`$TMPDIR` NVMe is automatic** — do *not* port Puhti/Mahti `--gres=nvme:N`
  requests (that syntax remains only for reserving `$LOCAL_SCRATCH` on
  XL/viz nodes). `$LOCAL_SCRATCH` is not a drop-in replacement.
- `--mail-type` does nothing yet (email notifications not enabled).
- Inside `sinteractive` sessions, use `prterun -n N` instead of `srun` (and
  `--oversubscribe` to use all requested cores); vim/emacs are absent (vi/
  nano only).

## Billing (indicative — verify in MyCSC / `csc-projects`)

BU types are separate pools per project: CPU BU, GPU BU, Storage BU, Cloud
BU. Balance: `csc-projects` (CLI) or MyCSC → Projects → Resources. Jobs bill
on **actual runtime** but on **all requested resources**.

- **Shared-node CPU** (`test`, `small`, `longrun`, `interactive`):
  `max(0.75 BU × cores, 0.375 BU × mem-GiB) per hour`
  (+ `0.02 BU/GiB·h` for reserved disaggregated storage).
  Example: 4 cores + 16 GiB × 2 h → `max(3, 6) × 2 = 12 BU` — memory can
  dominate.
- **Full-node CPU** (`medium`, `large`): `288 BU per node-hour`.
- **Hugemem**: `max(12 BU × cores, 0.25 BU × mem-GiB) per hour`
  (+ 0.02 BU/GiB·h for `--gres=nvme` local scratch).
- **GPU** (all GPU/viz partitions): `200 BU per GPU-hour` — cores and memory
  included. Rule of thumb: one Roihu GPU-hour ≈ 270 CPU-core-hours in BU;
  a job should be clearly GPU-accelerated to justify it (compare with `seff`;
  1 CPU BU and 1 GPU BU cost the same).
- **Storage BU**: scratch `6 BU/TiB·h`; home and projappl `10 BU/TiB·h`;
  dataset public 6, restricted 10. (1 TiB on scratch for 180 days ≈ 25 920
  Storage BU.) Automatic `$TMPDIR` is free; reserved `$LOCAL_SCRATCH` and
  disaggregated storage bill into compute BUs at 0.02 BU/GiB·h.
- Out of BUs: submission blocks immediately for the exhausted type; negative
  Storage BU disables `/scratch` + `/projappl` access after 30 days; project
  closes after 60 days.

## Disk areas and quotas

| Area | Path | Owner | Default quota | Files | Cleaning |
|------|------|-------|--------------|-------|----------|
| home     | `/users/<user>` (`$HOME`) | personal | 15 GiB | 150 k | no |
| projappl | `/projappl/<project>` | project | 15 GiB (max 250 GiB) | 150 k (max 2.5 M) | no |
| scratch  | `/scratch/<project>` | project | 250 GiB (max 100 TiB) | 500 k (max 10 M) | **180 days unused → deleted** (90 days for quotas ≥ 5 TiB) |
| dataset  | `/dataset/<project>` | dataset project | 0 (applied for) | 0 | no |

- **No backups, anywhere.** Deleted files are unrecoverable. Back up what
  matters to Allas (`allas-backup`).
- home is for config files only; **run everything from `/scratch`**; put
  compiled software/envs in `/projappl`. scratch and projappl are shared
  group-writable with all project members (blast radius!); convention:
  work under `/scratch/<project>/$USER/`.
- Quota increases via MyCSC. Overview: `csc-workspaces` (also shows cleaning
  cycle). If a workflow needs millions of files, restructure it (containers,
  tar, SquashFS) rather than raising the file quota.
- **Dataset projects** (new in Roihu, first grants early Aug 2026): a shared
  read-mostly area `/dataset/<id>` for datasets used by several projects.
  One project has write access; read can be granted to users, projects,
  organizations, or all Roihu users (public). No scratch/projappl, no
  compute — **never use the dataset project as `--account`**. Applied for in
  MyCSC (quota must be requested; valid 1 year at a time; exit strategy
  required). Intended for active use up to a few TiB, not archival.

### Local storage tiers (fast I/O)

- **Login nodes**: 80 GB `$TMPDIR` — for compiling and pack/unpack jobs;
  cleaned frequently.
- **Compute nodes, automatic `$TMPDIR`** (free, no reservation): 20 GiB on
  shared-node (R) jobs, 600 GiB on full-node (N), 150 GiB per-GPU-job (G),
  578 GiB on XL, 14 TiB on viz. ~5000/1400 MB/s R/W on M/L/GPU nodes.
  Wiped when the job ends —
  copy results out *inside* the job script.
  On M/L/GPU nodes this is meant for temp files, not sustained
  high-performance I/O; XL/V nodes have the faster (6700/4000 MB/s) drives.
- **Reserved `$LOCAL_SCRATCH`** — XL (and later viz) nodes only:
  `--gres=nvme:<GB>` up to 13000; bills 0.02 BU/GiB·h.
- **Disaggregated storage** (network-attached NVMe presented as local; pool
  307.2 TB): `#SBATCH --bb="#BB_LUA SBF storagesize=<N>G path=/run/sbb/$USER"`.
  **Full-node jobs only** for now (`medium`/`large`, or `--exclusive` on GPU
  partitions — which bills the whole node); improper requests die as
  `CANCELLED by 350` with no output. Multinode steps must be launched with
  `srun` to see the mount. Shared-node support expected Q3 2026.

## Lustre etiquette (why and thresholds)

Two independent flash Lustre systems: scratch 6.0 PiB (24 OST/4 MDT, peak
~560 GB/s read) and home+projappl 0.5 PiB (4 OST/4 MDT) — so scratch load
can't stall home. But within scratch, **metadata operations (open/close/
stat) are the bottleneck**, and the file system is shared by all users:

- Avoid `ls -l` in huge directories (ownership/permissions come from the
  MDT); plain `ls` is cheaper. Avoid `du`, `stat`, `find -size` sweeps — use
  **`lue`** (`module load lue; lue <subdir>`), and never scan a whole
  `/scratch/<project>` in one command.
- Avoid many files in one directory, rapid open/close loops, file locks for
  synchronization, and databases on `/scratch` (use Pukki DBaaS).
- Magnitudes (from CSC training): hundreds of files OK; thousands — pay
  attention; hundreds of thousands — don't. "If you're creating 10 000+
  files, rethink the workflow."
- The fix for small-file workloads: **tar the dataset, untar to `$TMPDIR`,
  compute there, tar results back** (10× speedups measured for AI loads);
  or SquashFS-mount read-only datasets into containers. Python/R stacks
  (thousands of small files) belong in containers.
- Striping: default 1 MB / count 1. For large files under parallel I/O,
  `lfs setstripe -c <n>` on the directory *before* creating files (rule of
  thumb: ≈ √(file size in GB), ≤ number of I/O processes). Stripe settings
  are fixed at file creation. Lustre compression: not yet supported.

## Software environment

- **Lmod modules**, hierarchical (`module avail` shows loadable now,
  `module spider <name>` shows everything + prerequisites). Separate,
  independent module trees per architecture, selected by the login node.
- Defaults — CPU side: `gcc/15.2.0`, `ucx`, `openmpi/5.0.10`,
  `openblas`, `StdEnv`. GPU side: `gcc/14.3.0`, `cuda/12.9.1`,
  `openmpi/5.0.10`, `openblas`, `StdEnv`.
- **Compilers, CPU side**: GNU 15.2 (default) and AMD AOCC 5.0
  (`clang`/`flang`); MPI wrappers `mpicc`/`mpicxx`/`mpif90` follow the loaded
  suite. Optimization: `-O2/-O3 -march=znver5`.
- **Compilers, GPU side**: GNU + CUDA (12.9 or 13.1) or NVIDIA HPC SDK
  (`module purge; module load nvhpc/26.3` — bundles CUDA/MPI/BLAS). CUDA
  target: compute capability 9.0 — `-gencode arch=compute_90,code=sm_90`
  (portable) or `compute_90a/sm_90a` (Hopper-only, faster). OpenMP offload
  `-mp=gpu -gpu=cc90`, OpenACC `-acc=gpu`, stdpar `-stdpar=gpu` (nvc++).
  MPI is CUDA-aware in all provided stacks.
- Compile on the **login-node local disk** (`$TMPDIR`), serially or in an
  interactive session (no `make -j` on login nodes); move artifacts to
  `/projappl` afterwards.
- **Everything from Puhti/Mahti most likely needs recompiling**; some module
  names changed (`pytorch` → `python-pytorch`, `geoconda` → `python-geo`);
  some commercial ARM-less software (Desmond, CryoSPARC) won't run on the
  GPU side.
- **Conda directly on Lustre is deprecated CSC-wide** — containerize
  (Tykky `conda-containerize`, or plain Apptainer). Python: venv on top of a
  CSC module (`python-data` etc.) in `/projappl`; note Roihu's per-arch
  user-package paths (`~/.local/x86_64/...` vs `~/.local/aarch64/...`).
- **Containers**: Apptainer; `apptainer_wrapper` is deprecated and absent on
  Roihu — use `apptainer` directly with
  `--bind="$(csc-common-bind)"` (Roihu-only helper) and `--nv` for GPUs.
  CSC base images live in the `satama.csc.fi` registry (CPU/GPU Spack cores,
  `ml-base`, `pytorch`, `vllm`). Keep Slurm env vars — don't use
  `--cleanenv`/`--contain` with MPI.
- Spack user installs: documented for Roihu but explicitly **work in
  progress** upstream.
- App availability: https://docs.csc.fi/apps/by_availability/#roihu or
  `module spider <name>` on the system.

## Allas from Roihu

`module load allas`, then `allas-conf` — which on Roihu configures an **S3
connection by default** (Puhti/Mahti default to Swift). S3 keys are
persistent (stored in aws/s3cmd/rclone configs in home — no re-auth every
session); rclone remote is `s3allas:`. Swift is still available with
`allas-conf --swift` (8 h token; a-commands then need `--swift`), and Lumi-O
with `allas-conf --lumi`. `check-allas-connections` diagnoses. This aligns
with the `csc-allas` skill's S3-first stance; see that skill for bucket
mechanics and safety rules (uploads are create-or-replace!).

## Usage policy and etiquette (the part users get wrong)

- **Login nodes**: compiling, batch-job management, data moving, and light
  pre/post-processing only — light = 1 core, minutes, < 1 GiB. Processes
  breaking this are **terminated without warning**. `tmux` is sanctioned on
  login nodes only for long *transfers/cleanup*, not computation.
- **Where interactive work goes**: `sinteractive` (`interactive` partition:
  36 h, 32 cores, 64 GiB, high priority — little queueing) or the web
  interface apps (persistent compute-node shell survives dropped
  connections). Prompt tells you where you are: `rc5183` = compute node,
  `roihu-cpu-login3` = login node.
- **Development workflow** (CSC's stance, encoded here deliberately):
  develop and test on your own machine where feasible; use HPC to *run*
  code. Remote VS Code over SSH is "here be dragons" per CSC — connection
  issues are unsupported, and **running computations via remote VS Code on
  HPC is explicitly not supported**; the web-interface VS Code/Jupyter/
  RStudio apps are the supported in-situ editors. The same logic applies to
  AI coding agents: not banned, but an agent session on a login node is
  subject to the 1-core/minutes/1-GiB rule like any process — keep agent
  activity to editing, job management and light glue, run real work through
  Slurm, and prefer doing iterative development off-machine, syncing code in.
- **Scheduler hygiene**: fair-share priority (heavy recent use lowers it);
  don't poll `squeue`/`sacct` in loops or `watch`; `sacct` queries over long
  ranges load the accounting DB (3-month max; redirect output to a file).
  Tens of jobs/steps OK, hundreds — pay attention, thousands — don't:
  pack short (< 30 min) tasks with array jobs or HyperQueue
  (recommended; `small`/`longrun` are the only serial partitions — a packed
  workflow on `medium` must fill 384 cores).
- **GPU discipline**: GPUs are for workloads that clearly benefit; compare
  BU consumption vs CPU with `seff`. CSC may terminate jobs that severely
  underutilize resources or overload storage.
- **Test first**: new scripts go to `test`/`gputest` (15 min, high priority)
  to catch typos and mis-requests before queueing something big; then a
  small trial run; check `seff <jobid>`; scale up. Occasionally getting
  killed for a too-tight request and rerunning beats always over-requesting.

## Migration from Puhti/Mahti — gotchas checklist

- Puhti compute stopped 31 Jul 2026; Mahti stops 31 Aug 2026; both storages
  retire ~15 Oct 2026 (unsupported Sep–Oct — move data by end of Aug).
- Transfer **directly** with `rsync -aP`/`tar|ssh` between systems (not via
  Allas — capacity-constrained; not via laptop). < 1000 files or > 1 MB
  average size for plain rsync; otherwise tar in flight.
- Recompile everything; rewrite `--gres=nvme` → automatic `$TMPDIR`; check
  renamed modules; GPU containers/envs must be rebuilt for ARM.
- Quota extensions did **not** carry over; Roihu defaults are small.
- Ownership: transferred files belong to the transferring user — each member
  moves their own data.

## Preliminary / TBA (do not promise these)

- **GPU slices** (`gpuinteractive` MIGs): not configured — full GPUs given.
- **Disaggregated storage on shared nodes**: full-node only until ~Q3 2026.
- **`$LOCAL_SCRATCH` on visualization nodes**: not implemented (use
  `$TMPDIR`).
- **Email notifications** (`--mail-type`): inactive.
- **FirecREST robot accounts**: expected Q3 2026.
- **Lustre compression**: announced, not yet supported.
- **Sensitive-data (SD) workflows on Roihu**: pilot autumn 2026, GA possibly
  early 2027.
- **Spack user-install tutorial**: marked work-in-progress upstream.
