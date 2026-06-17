# Allas concepts & CSC quirks

Source: CSC user guide (`data/Allas/`). Endpoint for everything is
`https://a3s.fi`.

## CSC projects & credentials

- Allas access is granted to a **CSC project** (the project must have the Allas
  service enabled). All members of a project have **equal, full read/write**
  access to the project's buckets — anyone can overwrite or delete anyone's
  objects. Allas keeps no record of who uploaded what. Treat shared buckets
  accordingly: a deletion is unrecoverable and hits everyone.
- **One project active at a time.** A given credential set maps to a single
  project; you see (and `ls`) only that project's buckets. To use another
  project's Allas, reconfigure for it.
  - `allas-conf` (Swift) / `allas-conf -m S3` (S3) configure **one** project per
    session; rerun to switch. Re-running `allas-conf -m S3` overwrites the
    existing credentials file.
  - To juggle several projects without clobbering, use the Puhti/Mahti web
    **Cloud storage configuration** app, which stores per-project S3 profiles
    named `s3allas-<project>` (e.g. `s3allas-project_2001234`) in
    `~/.config/rclone/rclone.conf`.
- The Allas project need not match the project you're computing under on
  Puhti/Mahti.
- Default Allas quota is **10 TB** per project (raise via servicedesk@csc.fi).

### Where credentials live (S3)

`allas-conf -m S3` writes:
- `~/.aws/credentials` + `~/.aws/config` (used by aws-cli, **boto3**, R `aws.s3`)
- `~/.s3cfg` (s3cmd)
- `~/.config/rclone/rclone.conf` (rclone, remote `s3allas:`)

S3 keys are **permanent** (no expiry) and stored **readable** in your home
directory. Anyone who reads them can access/modify all the project's Allas data.
Removing them from your machine does **not** revoke them — revoke with
`allas-conf --s3remove`. Never commit, log, or echo these keys.

S3 connection details for tools without `allas-conf`:
- endpoint: `a3s.fi` / `https://a3s.fi`
- region: usually empty (`""`)
- access key + secret key from `~/.aws/credentials`

## S3 vs Swift

| | S3 (**default**) | Swift |
|---|---|---|
| Auth | key pair, **permanent** connection | token, valid **8 h** |
| CSC direction | the long-term protocol | being phased out |
| Convenient for | batch jobs (no re-auth), automation | short interactive sessions on shared nodes |
| Security note | permanent keys = bigger blast radius if host compromised | token expires, lower risk on multi-user nodes |

- CSC docs historically default `a-commands` and rclone to **Swift** on
  Puhti/Mahti for the security reason above. This skill nonetheless defaults to
  **S3** (long-term protocol, simpler for automation), except when a bucket is
  already Swift-managed or the user asks for Swift.
- **Never mix protocols on the same object/bucket.** For small objects the two
  are interchangeable, but objects over ~5 GB are split and become readable
  **only** via the protocol that wrote them.

## Buckets, objects, naming

- A bucket is a flat container — **no nested buckets**. Structure comes from
  **pseudo-folders**: a `/` in an object key (`fishes/salmon.png`) is shown as a
  folder by many clients.
- Bucket names are **globally unique across all of Allas** and **public**. You
  can't reuse a name another project took, and you **can't rename** a bucket.
  - Put no confidential info in bucket names.
  - Recommend a project- or user-specific, DNS-valid (RFC 1035) name, lowercase,
    ASCII only — e.g. `2001234-raw-data`, `2001234-results`.
- Limits (generally not raisable): **1000 buckets/project**, **500 000
  objects/bucket**. Spread large object counts across buckets for performance.
- Object size guidance: prefer fewer large objects; keeping objects under 5 GB
  avoids chunking; objects over ~100 GB cause long transfer times. Common
  pattern: `tar`/`zip` a dataset before upload.

## Access control

Default is **private** — only authenticated members of the owning project.
Three sharing modes:

1. **Public** (read to anyone via URL): `https://a3s.fi/<bucket>/<object>`.
   - s3cmd: `s3cmd put file s3://bucket -P`, or
     `s3cmd setacl --acl-public s3://bucket[/object]`.
2. **Share to another CSC project** via **ACL** (S3 ACLs act on buckets, and on
   objects if you target/recurse them):
   - Need the grantee project's **UUID** (`openstack project show $OS_PROJECT_NAME`,
     or the Pouta dashboard identity page).
   - `s3cmd setacl --acl-grant=read:<UUID> s3://bucket`
     (`write:` for write; `--recursive` to cover existing objects;
     `--acl-revoke=read:<UUID>` to remove).
   - **A shared bucket does NOT appear in the grantee's `s3cmd ls`** — they must
     be told the bucket name, then `s3cmd ls s3://bucket` works.
3. **Temporary signed URL** (time-limited, no credentials needed by the reader):
   `s3cmd signurl s3://bucket/object +3600` (seconds).

## Bucket policies (IP restriction)

Restrict a bucket to source IP ranges with a JSON policy applied via
`s3cmd setpolicy policy.json s3://bucket` (view with `s3cmd info`, remove with
`s3cmd delpolicy`). **Warning:** a policy that denies your own IP locks you out
with no way to fix it. Always include your own range. See
`references/code-patterns.md` for the JSON shape.

## Object lifecycle (auto-expiry)

Set per-bucket lifecycle rules (XML) with `s3cmd setlifecycle policy.xml
s3://bucket` (view with `getlifecycle`). Rules match by **prefix** (pseudo-folder)
and/or **tag** (`x-amz-tagging:KEY=VALUE` header at upload), each with an
expiration in days. Useful for "expire old runs automatically." Confirm
retention requirements before enabling — expiry is irreversible deletion.

## Large objects & `_segments` buckets

Objects over ~5 GB are split during upload. With Swift-based tools (a-commands,
rclone-swift, swift) the pieces go into a separate `<bucket>_segments` bucket,
and the main bucket holds only a manifest. **Don't touch or delete objects in
`_segments` buckets.** s3cmd reassembles segments into one object instead. The
presence of a `_segments` bucket is a strong signal the data was written over
Swift — read it back over Swift.

## Billing

Billing is on **data stored** (1.05 Storage BU/TiBh ≈ 25.2 BU/TiB/day). CSC does
**not** charge for network transfers or API calls — unusual vs. commercial S3,
so transfer-heavy workflows are fine.

## Common error messages

| Symptom | Meaning |
|---|---|
| `Conflict` (409) | Bucket name already exists (globally) |
| `NoSuchBucket` (404) | Bucket doesn't exist (or not visible to this project) |
| `AccessDenied` (403) | Credentials can't see/use the bucket |
| `QuotaExceeded` (403) | Hit the project quota — request increase from servicedesk |
| `EntityTooLarge` (400) / `Too Large Object` | File too big / hit 500 000-objects-per-bucket limit |

## Backups

Allas survives disk/server failure but **not** accidental deletion. It is not a
backup service. Recommend the user keep independent backups of anything
important; `allas-backup` (an a-command) only copies to another Allas bucket
that's equally deletable.
