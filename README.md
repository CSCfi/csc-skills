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

## Installing

This repo is a Claude Code **plugin marketplace**. The recommended way to
install — and to get updates by pulling — is via the plugin system. In Claude
Code, first register the marketplace:

```
/plugin marketplace add ssh://git@gitlab.ci.csc.fi:10022/soda/csc-skills.git
```

(HTTPS alternative if you don't have SSH set up on CSC GitLab:
`/plugin marketplace add https://gitlab.ci.csc.fi/soda/csc-skills.git`.)

Then install either the **bundle** (all CSC skills) or just **one** skill:

```
/plugin install csc-skills@csc-skills    # everything
/plugin install csc-allas@csc-skills     # just the Allas skill
```

The form is `<plugin>@<marketplace>`; here the marketplace is named
`csc-skills`. After the marketplace is added, `/plugin` also lets you browse and
toggle plugins interactively. Updating is `git pull` in the marketplace
checkout, or re-running `/plugin marketplace add` to refresh.

### Manual install (without the plugin system)

Skills are also discovered from `~/.claude/skills/`. Each skill's canonical
files live at `plugins/<skill>/skills/<skill>/`, so to install one for your
user:

```bash
cp -r plugins/csc-allas/skills/csc-allas ~/.claude/skills/
```

Or symlink it so it tracks the repo:

```bash
ln -s "$PWD/plugins/csc-allas/skills/csc-allas" ~/.claude/skills/csc-allas
```

Either way, ask Claude Code something a skill covers (e.g. "upload this result
to an Allas bucket") and it will pick the skill up automatically.

## Layout

```
csc-skills/
├── .claude-plugin/
│   └── marketplace.json          # lists the plugins below
├── README.md
└── plugins/
    ├── csc-allas/                # per-skill plugin — holds the real files
    │   ├── .claude-plugin/plugin.json
    │   └── skills/csc-allas/{SKILL.md, references/}
    └── csc-skills/               # bundle plugin — all skills via symlink
        ├── .claude-plugin/plugin.json
        └── skills/csc-allas -> ../../csc-allas/skills/csc-allas
```

The bundle plugin links to each per-skill plugin's canonical files rather than
copying them; symlinks that stay within the marketplace are dereferenced and
copied into the cache at install time, so each plugin still installs standalone.

## Contributing — adding a skill

1. Create the per-skill plugin: `plugins/<name>/.claude-plugin/plugin.json`
   plus `plugins/<name>/skills/<name>/SKILL.md` (YAML frontmatter `name` +
   `description`, then the body) and optional `references/*.md` loaded on demand.
2. Link it into the bundle:
   `ln -s ../../<name>/skills/<name> plugins/csc-skills/skills/<name>`.
3. Add a `plugins[]` entry for it in `.claude-plugin/marketplace.json`.

CSC-specific facts should be sourced from the
[CSC user guide](https://docs.csc.fi/).
