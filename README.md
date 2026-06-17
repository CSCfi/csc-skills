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

This repo is a Claude Code **plugin marketplace**. The recommended way to
install — and to get updates by pulling — is via the plugin system. In Claude
Code:

```
/plugin marketplace add <this-repo-url>
/plugin install csc-skills@csc-skills
```

(After the marketplace is added, `/plugin` also lets you browse and toggle it
interactively.) Updating is `git pull` in the marketplace checkout, or
re-running `/plugin marketplace add` to refresh.

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
│   ├── plugin.json        # plugin manifest
│   └── marketplace.json   # marketplace manifest (lists this plugin)
├── README.md
└── skills/
    └── csc-allas/         # one directory per skill
        ├── SKILL.md
        └── references/
```

## Contributing

Add a skill as a new directory under `skills/` with a `SKILL.md` (YAML
frontmatter `name` + `description`, then the body) and optional `references/*.md`
files loaded on demand. The plugin auto-discovers everything under `skills/`, so
no manifest edits are needed for a new skill. CSC-specific facts should be
sourced from the [CSC user guide](https://docs.csc.fi/).
