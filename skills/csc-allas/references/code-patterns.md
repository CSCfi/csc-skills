# Allas code patterns

Adapt these to the user's workflow. **Default to S3.** Endpoint is always
`https://a3s.fi`. Credentials are assumed already configured (see
`concepts.md`) — never hard-code keys.

---

## Python — boto3 (S3, the default)

### Create a resource

Two checksum env vars are **required** with recent `aws`/`botocore` versions or
uploads/downloads to Allas fail. `endpoint_url` is always `https://a3s.fi`.

```python
import os
import boto3

# Required for Allas with recent botocore; harmless on older versions.
os.environ["AWS_REQUEST_CHECKSUM_CALCULATION"] = "when_required"
os.environ["AWS_RESPONSE_CHECKSUM_VALIDATION"] = "when_required"

# Single project: credentials from the default location (~/.aws/credentials).
s3 = boto3.resource("s3", endpoint_url="https://a3s.fi")
```

Multiple projects — select a per-project profile (`s3allas-<project>`):

```python
import os, boto3

os.environ["AWS_SHARED_CREDENTIALS_FILE"] = os.path.expanduser("~/.boto3_credentials")
os.environ["AWS_REQUEST_CHECKSUM_CALCULATION"] = "when_required"
os.environ["AWS_RESPONSE_CHECKSUM_VALIDATION"] = "when_required"

session = boto3.Session(profile_name="s3allas-project_2001234")
s3 = session.resource("s3", endpoint_url="https://a3s.fi")
```

> Note on multi-project credentials: rclone-style configs store keys as
> `access_key_id` / `secret_access_key`, but boto3 wants them prefixed `aws_`.
> The CSC-documented trick is to derive a boto3 file from the rclone config:
> `sed -E 's/^(access|secret)/aws_\1/g' ~/.config/rclone/rclone.conf > ~/.boto3_credentials`

### Upload a result at the end of a workflow

This is the common "upload the result with a naming scheme" case. Build the
object key explicitly from the scheme; use pseudo-folders for structure.

```python
# Example naming scheme: runs/<date>/<sample>-<metric>.tar.zst
key = f"runs/{run_date}/{sample}-{metric}.tar.zst"
s3.Object("2001234-results", key).upload_file("results/out.tar.zst")
# public URL (if the object is public): https://a3s.fi/<bucket>/<key>
```

If the scheme can overwrite a previous result, include a timestamp/run-id in the
key (S3 PUT silently overwrites), or guard with a `head_object` existence check.

Downloads, listing and presigned URLs are ordinary boto3 against the same
resource — nothing Allas-specific beyond the endpoint and env vars above.

### Create a bucket (may be run interactively)

```python
s3.create_bucket(Bucket="2001234-results")   # name must be globally unique
```

Creating an empty bucket is reversible and is the natural way to probe whether a
name is free — a `ClientError` with `BucketAlreadyExists`/409 just means the
name is taken, so try another. OK to run on request (SKILL.md rule 2).

### Delete (generate as code; do NOT run it yourself)

```python
s3.Object("2001234-results", "old.txt").delete()    # deletes for the WHOLE project
# Bucket must be empty before removal:
# s3.Bucket("2001234-results").objects.all().delete(); s3.Bucket("2001234-results").delete()
```

Deletes affect all project members irreversibly — see SKILL.md rule 2 before
producing one, and never run it yourself.

### pandas / GDAL direct I/O

`awswrangler` (AWS SDK for pandas) and GDAL-based libraries can read/write Allas
over S3 directly; point them at `endpoint_url=https://a3s.fi` (or `AWS_S3_ENDPOINT`
/ GDAL `/vsis3/` config). Useful for streaming dataframes/rasters without a
local round-trip.

---

## aws-cli (S3)

Works as usual with `--endpoint-url https://a3s.fi` on every command (or set
the endpoint in `~/.aws/config` and drop the flag).

---

## s3cmd (S3) — sharing, signing, lifecycle, policy

`allas-conf -m S3` writes `~/.s3cfg`, so ordinary s3cmd commands (`mb`, `put`,
`get`, `ls`, `del`, `rb`, `info`, `du -H`) work as-is. The CSC-relevant recipes:

### Public

```bash
s3cmd put fishes/salmon.jpg s3://my-bucket/fishes/salmon.jpg -P   # public on upload
s3cmd setacl --acl-public s3://my-bucket                          # whole bucket
s3cmd setacl --acl-public s3://my-bucket/object                   # one object
# Public URL: https://a3s.fi/my-bucket/fishes/salmon.jpg
```

### Share to another CSC project (ACL)

```bash
# Get a project UUID:
openstack project show $OS_PROJECT_NAME
# Grant read to project UUID (bucket-level; --recursive for existing objects):
s3cmd setacl --acl-grant=read:3d5b0ae8e724b439a4cd16d1290 s3://my-bucket
s3cmd setacl --recursive --acl-grant=read:<UUID> s3://my-bucket
s3cmd setacl --acl-grant=write:<UUID> s3://my-bucket/object
s3cmd info s3://my-bucket | grep -i acl                # check
s3cmd setacl --recursive --acl-revoke=read:<UUID> s3://my-bucket   # revoke
```

The grantee won't see the bucket in `s3cmd ls`; send them the bucket name so
they can `s3cmd ls s3://my-bucket`.

### Temporary signed URL

```bash
s3cmd signurl s3://my-bucket/object +3600     # valid 1 hour
```

### Lifecycle (auto-expire by prefix and/or tag)

`policy.xml`:

```xml
<?xml version="1.0" ?>
<LifecycleConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
   <!-- by prefix (pseudo-folder) -->
   <Rule>
      <ID>expire-daily</ID>
      <Status>Enabled</Status>
      <Prefix>daily/</Prefix>
      <Expiration><Days>30</Days></Expiration>
   </Rule>
   <!-- by tag (matches objects PUT with x-amz-tagging:days=1) -->
   <Rule>
      <ID>expire-tagged-1d</ID>
      <Status>Enabled</Status>
      <Filter><Tag><Key>days</Key><Value>1</Value></Tag></Filter>
      <Expiration><Days>1</Days></Expiration>
   </Rule>
</LifecycleConfiguration>
```

Prefix and tag can be combined within one rule using an `<And>` block.

```bash
s3cmd setlifecycle policy.xml s3://my-bucket
s3cmd getlifecycle s3://my-bucket
# Tag an object so a tag-based rule applies:
s3cmd --add-header=x-amz-tagging:days=1 put file.tar.gz s3://my-bucket/
```

### Restrict a bucket to IP ranges (bucket policy)

`ippolicy.json` — **include your own IP range or you lock yourself out**:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "IPAllow", "Effect": "Deny", "Principal": "*", "Action": "s3:*",
    "Resource": ["arn:aws:s3:::MY-BUCKET", "arn:aws:s3:::MY-BUCKET/*"],
    "Condition": { "NotIpAddress": { "aws:SourceIp": "86.50.164.0/24" } }
  }]
}
```

```bash
s3cmd setpolicy ippolicy.json s3://MY-BUCKET
s3cmd delpolicy s3://MY-BUCKET
```

---

## rclone

rclone remotes: `s3allas:` (S3) and `allas:` (Swift). **Do not use rclone to
copy/move/rename objects *inside* Allas** — it mishandles >5 GB objects. Use it
for transfers between local/compute and Allas.

```bash
rclone copy results/ s3allas:2001234-results/runs/2026-06-17/   # upload a dir
rclone copy s3allas:2001234-results/runs/2026-06-17/ ./out/     # download
rclone lsd s3allas:                 # list buckets
rclone ls  s3allas:2001234-results  # list objects
```

`rclone sync` makes the destination match the source — it **deletes** extra
files at the destination. Treat it as destructive: never run it unprompted, and
if asked, spell out exactly what would be deleted first (SKILL.md rule 2). If an
upload of a >5 GB file is interrupted, delete the partial object before retrying.

---

## Slurm batch jobs

### S3 (default) — permanent keys, nothing special needed

Once `allas-conf -m S3` has been run once on the login node, the S3 keys
persist, so an ordinary job script just calls aws-cli / s3cmd / boto3 / rclone
directly — no re-auth, no extra `#SBATCH` options.

### Swift — token expires in 8 h, so refresh inside the job

Only when the bucket is Swift-managed or the user wants Swift. Before submitting,
run `module load allas; allas-conf -k` on the login node (stores the password in
`$OS_PASSWORD` so re-auth is non-interactive). In the script, re-source before
each Allas step (path differs by machine):

```bash
# Puhti:
source /appl/opt/csc-cli-utils/allas-cli-utils/allas_conf -f -k $OS_PROJECT_NAME
# Mahti:
source /appl/opt/csc-tools/allas-cli-utils/allas_conf -f -k $OS_PROJECT_NAME

rclone copy allas:2001234-data/input.tar.zst ./
# ... analysis ...
# re-source again before the upload step (job may have run >8 h) ...
rclone copy results/ allas:2001234-results/
```

The `a-commands` (`a-get`, `a-put`, ...) refresh the Swift connection
themselves, so with them you only need `allas-conf -k` before `sbatch` and no
in-script re-source.
