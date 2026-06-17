# csc-skills

Claude Code skills for using CSC infrastructure correctly, safely, and in a
streamlined way. Each subdirectory is a self-contained skill.

## Available skills

- **csc-allas** — use [Allas](https://docs.csc.fi/data/Allas/), CSC's object
  storage. Generates code/scripts (boto3, aws-cli, s3cmd) for reading, writing,
  listing, sharing and publishing Allas data; advises on the mechanics (CSC
  projects & credentials, public/private buckets, ACLs, bucket policies,
  lifecycle, S3 vs Swift). Defaults to S3, and does not run destructive Allas
  operations on your behalf.

## Installing

Skills are discovered from `~/.claude/skills/`. To install all skills from this
repo for your user:

```bash
cp -r csc-* ~/.claude/skills/
```

Or symlink an individual skill so it tracks the repo:

```bash
ln -s "$PWD/csc-allas" ~/.claude/skills/csc-allas
```

Then ask Claude Code something the skill covers (e.g. "upload this result to an
Allas bucket") and it will pick the skill up automatically.

## Contributing

Each skill is a directory with a `SKILL.md` (YAML frontmatter `name` +
`description`, then the body) and optional `references/*.md` files loaded on
demand. CSC-specific facts should be sourced from the
[CSC user guide](https://docs.csc.fi/).
