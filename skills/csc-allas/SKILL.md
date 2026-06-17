---
name: csc-allas
description: >
  Use Allas, CSC's object storage, correctly and safely. Invoke when the user
  wants to read/write/list/share data in Allas, store or publish results in an
  Allas bucket, configure Allas credentials, or asks about Allas concepts
  (buckets, CSC projects, public/private access, ACLs, bucket policies,
  lifecycle, S3 vs Swift, a3s.fi). Also use for the common case "at the end of
  this workflow, upload the result to such-and-such Allas bucket". Generates
  code/scripts (boto3, aws-cli, s3cmd, rclone) but does NOT itself run mutating
  or destructive Allas operations.
---

# CSC Allas object storage

Allas is CSC's general-purpose object storage (Ceph, exposed over **S3** and
**Swift**). Data lives as *objects* in *buckets*. This skill helps you (a) write
correct code/scripts that move data in and out of Allas and (b) advise on the
mechanics, with the CSC-specific quirks built in.

## Operating rules (read first)

1. **Default to the S3 protocol.** S3 is the long-term interface; Swift is being
   phased out. Generate S3 code (boto3 / aws-cli / s3cmd) and S3 config unless an
   exception below applies. Endpoint is always `https://a3s.fi`.

   **Stick with Swift only when:**
   - the user explicitly asks for Swift, **or**
   - the target bucket is already Swift-managed — e.g. it was populated with
     `a-commands` (`a-put`) or rclone over Swift, or it has a companion
     `<bucket>_segments` bucket (the tell-tale of a Swift large-object upload).

   Reason: the protocols are not interchangeable for objects >5 GB. A large
   object written via Swift **cannot** be read back over S3 (and vice versa), so
   for an existing bucket, match whatever protocol already owns its data. Never
   mix protocols within one bucket.

2. **Do not run destructive or data-changing Allas operations yourself.** This
   skill *writes* code and scripts; the user runs them. Two things you **may**
   run on request:
   - **Read-only inspection** — `s3cmd ls`/`info`/`du`, `aws s3 ls`,
     `rclone ls`/`lsd`.
   - **Bucket creation and name-availability probing** — creating an empty
     bucket is harmless and reversible, and it's the natural way to find a free
     name (names are globally unique, so a `Conflict`/409 just means "taken, try
     another"). You may run `s3cmd mb` / `aws s3 mb` / `create_bucket`
     interactively to claim a name. (Still confirm the name with the user first
     if they haven't pinned one down.)

   You must **not** independently invoke uploads, deletes, moves, `sync`,
   bucket *removal*, or ACL/policy/lifecycle changes — anything that writes,
   overwrites, deletes, or changes who can reach existing data.

   If the user explicitly asks you to perform one of those actions:
   - State plainly and specifically what it would do — which bucket, which
     objects, and **whether anything gets deleted or overwritten** (call out
     `rclone sync` and `rclone delete`, and that *every* project member shares
     full read/write, so a deletion is unrecoverable and affects everyone).
   - Offer to **write a reviewable script** instead of running it. Prefer that.
   - Only run it if the user, after that, clearly confirms — and even then,
     never a bulk/recursive delete or a `sync` that prunes a destination.

3. **Credentials are per-CSC-project, one at a time.** Allas access comes from a
   CSC project; with a given credential set, exactly one project is "active" and
   you see that project's buckets. Switching projects = re-running config (or
   using a different S3 profile). Never hard-code or echo secret keys into code,
   logs, or committed files. See `references/concepts.md`.

## Quick start: generating upload code

The most common request is *"at the end of this workflow, upload the result to
Allas bucket X with naming scheme Y."* Steps:

1. **Confirm the bucket name and the naming scheme.** Bucket names are globally
   unique across all Allas and are public — recommend a project-prefixed,
   DNS-safe, lowercase name (e.g. `2001234-results`). For the object key, turn
   the user's scheme into an explicit pattern (e.g.
   `runs/{date}/{sample}-{metric}.tar.zst`) and use pseudo-folders (`/` in the
   key) for structure.
2. **Pick the tool** to match the surrounding workflow, all over S3 (rule 1):
   - Python in-process → `boto3`.
   - Shell / batch job, single objects or ad-hoc → `aws-cli` or `s3cmd`.
   - Bulk directory transfers (whole result dirs, many files) → **`rclone`**.
     It's usually preinstalled on Puhti/Mahti, handles directories and resumes
     well, and is often the smoothest choice — use remote `s3allas:` for S3.
     Caveat: don't use rclone to copy/move *inside* Allas (mishandles >5 GB
     objects), and `rclone sync` deletes at the destination (see rule 2).
3. **Generate the code** from `references/code-patterns.md`. For Python boto3,
   always include the two checksum env vars and `endpoint_url='https://a3s.fi'`.
4. **Handle credentials out-of-band** — the code assumes the project's S3
   credentials are already configured (`allas-conf -m S3`, or a Puhti/Mahti web
   "Cloud storage configuration" profile). Don't bake keys in.
5. **Don't auto-create or auto-overwrite** in surprising ways. If the scheme
   could overwrite prior results, point it out and suggest including a
   timestamp/run-id, or a lifecycle rule for expiring old runs.

## Reference material

Load the relevant file when you need detail:

- `references/concepts.md` — CSC projects & credentials, S3 vs Swift, bucket
  naming & limits, public/private, ACLs (sharing to another project), bucket
  policies (IP allow), lifecycle, large-object/`_segments` behaviour, billing,
  common error messages, and the quirks that trip people up.
- `references/code-patterns.md` — ready-to-adapt snippets: boto3
  (upload/download/list/presigned URL), aws-cli, s3cmd (incl. public objects,
  ACLs, signed URLs, lifecycle, IP policy), rclone, and Slurm batch-job
  templates for both S3 and Swift.

When advising on mechanics, prefer these notes over memory; if something here is
silent on a detail, say so rather than inventing CSC-specific behaviour.
