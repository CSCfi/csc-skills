# Roihu code patterns — ready to adapt

Replace `<project>` with the CSC project (Unix group, e.g. `project_2001234`
— shown in MyCSC → Projects), `<username>` with the CSC username. CPU jobs:
build/submit on `roihu-cpu.csc.fi`; GPU jobs: on `roihu-gpu.csc.fi`. Never
echo, log, or commit private keys, certificates, passwords, or tokens.

## SSH setup and certificates

### One-time key setup

```bash
ssh-keygen -t ed25519          # always set a passphrase
# Then add ~/.ssh/id_ed25519.pub in MyCSC (Profile -> SSH public keys).
# ssh-copy-id / authorized_keys do NOT work on CSC systems.
```

### Get a certificate — option A: helper tool (recommended for daily use)

```bash
git clone https://github.com/CSCfi/certificate-helper-tool.git
cd certificate-helper-tool

python3 csc_cert.py -u <username> ~/.ssh/id_ed25519.pub
# -> opens https://my.csc.fi login in the browser, shows a 6-digit code
#    to paste back, writes ~/.ssh/id_ed25519-cert.pub, runs ssh-add.
```

Useful flags: `-S` status (keys, certs + expiry, agents, MyCSC
reachability), `-r` force refresh, `-s`/`-v` silent/verbose,
`-a none` skip agents. Windows (PowerShell): `python csc_cert.py -u
<username> C:\Users\<u>\.ssh\id_ed25519.pub` — also writes a
`-cert.ppk` for PuTTY/WinSCP (needs WinSCP installed; Pageant running;
note MobaXterm's MobAgent is *not* updated — use Pageant). Certificates
last **24 h**; there is no auto-renew — rerun the tool.

### Get a certificate — option B: MyCSC (no tooling required)

MyCSC → Profile → SSH PUBLIC KEYS → ⋮ next to the key → *Sign and download
SSH certificate* → save as `~/.ssh/id_ed25519-cert.pub` (exactly this
naming — OpenSSH finds certs by convention `<key>-cert.pub`).

### Connect

```bash
ssh <username>@roihu-cpu.csc.fi     # x86 side (CPU partitions)
ssh <username>@roihu-gpu.csc.fi     # ARM side (GPU partitions)
# specific login node: roihu-cpu-login1..4, roihu-gpu-login1..2
```

Non-default key location — note *two* `-i` flags (key + cert):

```bash
ssh <username>@roihu-cpu.csc.fi -i ~/keys/mykey -i ~/keys/mykey-cert.pub
```

`~/.ssh/config` entry:

```
Host roihu-cpu
    HostName roihu-cpu.csc.fi
    User <username>
    IdentityFile ~/.ssh/id_ed25519
    CertificateFile ~/.ssh/id_ed25519-cert.pub   # Roihu only
```

Troubleshooting: "Too many authentication failures" → pass `-i` explicitly;
cert expired → re-sign (check with `-S` or `ssh-keygen -L`); FileZilla can't
take a cert file — it must come from Pageant; in WinSCP either point at the
`-cert.ppk` or leave the key field *empty* so Pageant is used.

## Data transfer

Certificates apply to scp/rsync/sftp too. For host→Roihu copies *from*
Puhti/Mahti, forward your agent (`ssh -A`) so the cert travels; or log in to
Roihu and **pull** (then no cert needed in the agent).

```bash
# local -> Roihu
rsync -aP mydata/ <username>@roihu-cpu.csc.fi:/scratch/<project>/$USER/mydata/

# Puhti -> Roihu, direct (run on Puhti after ssh -A into it), inside tmux/screen
rsync -aP /scratch/<project>/my-data <username>@roihu-cpu.csc.fi:/scratch/<project>/

# pull from Roihu instead (no cert in agent needed)
rsync -aP <username>@puhti.csc.fi:/scratch/<project>/my-data /scratch/<project>/

# many small files: tar in flight (often beats rsync)
tar c -C /scratch/<project> my-data | \
  ssh <username>@roihu-cpu.csc.fi 'cat > /scratch/<project>/my-data.tar'
# with zstd compression: tar c -I zstd ... 'cat > .../my-data.tar.zst'
```

Rules of thumb: plain `rsync -aP` is fine for < 1000 files or > 1 MB average
size — otherwise archive first. `scp` is discouraged (no resume, no
checksums). `rsync` **overwrites newer files at the target by default** (use
`-u` to keep them) — and `--delete`, like `rclone sync`, is avoid-zone: write
it as a reviewable script if the user insists. Long transfers: `tmux` on
Roihu (`screen` doesn't exist there). Roihu is `rsync`-reachable but files
land owned by the transferring user.

## Slurm job scripts

Submit with `sbatch script.sh`; status `squeue -u $USER`; cancel your own
just-submitted test with `scancel <jobid>` (cancelling anything else:
avoid-zone — confirm first). `--account` is mandatory. New script? Run it on
`test`/`gputest` first (15 min limit, high priority).

### Serial / partial node (CPU, `small`)

```bash
#!/bin/bash
#SBATCH --job-name=example
#SBATCH --account=<project>
#SBATCH --partition=small
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem-per-cpu=1000M

srun myprog <options>
```

MPI on a partial node: same, with `--ntasks=<n>`. OpenMP threads:

```bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=1000M

export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export OMP_PLACES=cores
export OMP_PROC_BIND=spread
srun myprog <options>
```

### Full CPU nodes (`medium` ≤ 6 nodes, `large` 6–60 — needs approval)

Product of `--ntasks-per-node` × `--cpus-per-task` must be **384**
(pure MPI 384×1, hybrid 192×2 or 96×4; billing is per full node):

```bash
#!/bin/bash
#SBATCH --job-name=example
#SBATCH --account=<project>
#SBATCH --partition=medium
#SBATCH --time=00:30:00
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=384 --cpus-per-task=1   # product = 384

srun myprog <options>          # srun, never mpirun/mpiexec
```

Hugemem (`hugemem`/`hugemem_longrun`, XL nodes): product = **128**;
optionally `--gres=nvme:<GB>` (≤ 13000) for `$LOCAL_SCRATCH` (billed).

### GPU job (GH200; submit from roihu-gpu)

`--gres=gpu:gh200:<n>` is per node (max 4). Each GPU brings up to 72 cores
and 217 GiB — request the cores, they're already paid for (200 BU/GPU·h):

```bash
#!/bin/bash
#SBATCH --job-name=example
#SBATCH --account=<project>
#SBATCH --partition=gpumedium
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1 --cpus-per-task=72   # 72 x number of GPUs/node
#SBATCH --gres=gpu:gh200:1

export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
srun myprog <options>
```

Multi-node GPU (`gpularge`, needs approval): `--nodes=<n>`,
`--ntasks-per-node=4 --cpus-per-task=72`, `--gres=gpu:gh200:4`.

PyTorch example (module renamed from Puhti/Mahti!):

```bash
module load python-pytorch/2.10
srun python3 myprog.py
```

### Packing many tasks

Ordinary Slurm array jobs (`#SBATCH --array=1-50` on `small`) for tens of
≥ 30-min tasks; 100+ or shorter tasks → HyperQueue. Chained post-processing:
add `#SBATCH --dependency=afterok:<jobid>` to a small serial job instead of
padding the big job's time limit.

### Interactive sessions (never compute on the login node)

```bash
sinteractive --account <project>              # prompts / defaults, CPU side
sinteractive --account <project> --cores 4    # inside: use prterun, not srun
# explicit srun form:
srun --ntasks=1 --time=00:10:00 --mem=1G --pty \
     --account=<project> --partition=small bash
# shell on a node where your job already runs (no direct ssh to nodes):
srun --jobid=<jobid> --overlap --pty bash
```

GPU smoke test: `--partition=gputest --gres=gpu:gh200:1` (15 min). Web
interface (`https://www.roihu.csc.fi`) gives persistent compute-node shells,
Jupyter, VS Code etc. — max 16 h, partitions `interactive`/`small`/`test`/
`gputest`.

## Local NVMe staging (the small-files fix)

`$TMPDIR` on compute nodes is automatic and free (20 GiB shared node /
600 GiB full node / 150 GiB per GPU job), wiped at job end:

```bash
#!/bin/bash
#SBATCH --job-name=staged
#SBATCH --account=<project>
#SBATCH --partition=small
#SBATCH --time=02:00:00
#SBATCH --ntasks=1 --cpus-per-task=4
#SBATCH --mem-per-cpu=2G

# 1. stage in: unpack the (pre-tarred) dataset onto fast local disk
tar xf /scratch/<project>/big_dataset.tar.gz -C "$TMPDIR"

# 2. compute against $TMPDIR
cd "$TMPDIR"
srun myprog --input "$TMPDIR/big_dataset" --output "$TMPDIR/results"

# 3. stage out BEFORE the job ends — local disk is wiped afterwards
tar czf /scratch/<project>/$USER/results.tar.gz -C "$TMPDIR" results
```

Do **not** port Puhti/Mahti `--gres=nvme:N` for this — on Roihu that syntax
only reserves `$LOCAL_SCRATCH` on hugemem/viz nodes. Disaggregated storage
(bigger fast scratch, full-node jobs only, billed 0.02 BU/GiB·h):

```bash
#SBATCH --bb="#BB_LUA SBF storagesize=100G path=/run/sbb/$USER"
# GPU partitions additionally need --exclusive (bills the whole node).
# Multinode: every step must be launched via srun to see the mount.
```

## Compiling and installing

```bash
# CPU side (roihu-cpu): GNU default; AMD AOCC alternative
module load gcc/15.2.0 openmpi/5.0.10        # default suite
mpicc  -O3 -march=znver5 example.c -o example
module load aocc/5.0.0 openmpi/5.0.10        # AMD suite (clang/flang)

# GPU side (roihu-gpu): GNU + CUDA, or NVIDIA HPC SDK
module load gcc/15.2.0 cuda/13.1.1 openmpi/5.0.10 openblas/0.3.30
nvcc -gencode arch=compute_90a,code=sm_90a example.cu   # Hopper-only, fastest
#    arch=compute_90,code=sm_90 for portable cc9.0

module purge && module load nvhpc/26.3       # bundles CUDA+MPI+BLAS
nvc++ -O3 -mp=gpu -gpu=cc90 example.cpp      # OpenMP offload
nvc++ -O3 -acc=gpu -gpu=cc90 example.cpp     # OpenACC
```

Compile in `$TMPDIR` on the login node (serial `make`, or an interactive
session for `make -j`), install into `/projappl/<project>/`, and load the
same modules at runtime.

Python (venv over a CSC module — never bare conda on Lustre):

```bash
module load python-data
python3 -m venv --system-site-packages /projappl/<project>/my-venv
source /projappl/<project>/my-venv/bin/activate
pip install <package>
# NB: envs are architecture-specific — separate venvs for CPU and GPU sides.
```

Conda environments → Tykky containers:

```bash
module purge && module load tykky
conda-containerize new --prefix /projappl/<project>/my-env env.yml
export PATH="/projappl/<project>/my-env/bin:$PATH"
```

Apptainer (no `apptainer_wrapper` on Roihu):

```bash
apptainer exec --bind="$(csc-common-bind)" container.sif mycommand
apptainer exec --nv --bind="$(csc-common-bind)" container.sif python3 ...   # GPU
export APPTAINER_CACHEDIR=$TMPDIR   # keep caches off Lustre
apptainer build --fakeroot --bind="$TMPDIR:/tmp" container.sif container.def
# MPI in containers: keep Slurm env vars — no --cleanenv / --contain
```

## Allas from Roihu

```bash
module load allas
allas-conf <project>        # S3 by default on Roihu (persistent keys)
a-put results.tar.gz mybucket/     # a-commands, rclone (s3allas:), s3cmd, aws all work
rclone lsd s3allas:
allas-conf --swift          # only if the data was written via Swift (8 h token;
                            # a-commands then need --swift)
check-allas-connections
```

See the `csc-allas` skill for bucket safety rules (S3 PUT silently
overwrites — script uploads rather than running them blind).

## Monitoring and accounting (read-only, run freely — but politely)

```bash
squeue -u $USER                     # my queue state (don't wrap in watch/loops)
scontrol show job <jobid>
seff <jobid>                        # efficiency after completion — act on it
sacct -X -j <jobid> -o jobid,partition,state,elapsed,reqmem,maxrss
sacct --starttime now-7days > sacct.txt   # short ranges; save, don't re-query
csc-projects                        # BU balances per project
csc-workspaces                      # disk areas, quotas, cleaning cycle
module load lue && lue /scratch/<project>/$USER/subdir   # not the whole project
sinfo --summarize                   # partition state
```

## Avoid-zone: reviewable scripts only

Deleting on shared disk areas (no backups!), cancelling running jobs, or
deletion-capable syncs: generate a script, spell out what it destroys, run
only on explicit confirmation. Example shape for a scratch cleanup:

```bash
#!/bin/bash
# cleanup-old-results.sh — REVIEW BEFORE RUNNING
# Deletes /scratch/<project>/$USER/old-runs (N GiB, M files, last used ...).
# scratch has NO backup; this is IRREVERSIBLE and the area is shared with
# every member of <project>.
set -euo pipefail
target=/scratch/<project>/$USER/old-runs
lue "$target"                      # show what's there, first
read -rp "Type the directory name to confirm deletion: " ans
[ "$ans" = "old-runs" ] || { echo "aborted"; exit 1; }
rm -rf -- "$target"
```

(CSC's own `lcleaner` tool helps with purge-list-driven cleanups:
`lcleaner --sort-by-size --limit 10 <path_summary.txt>`; bulk deletes take
hours — run inside `tmux`.)
