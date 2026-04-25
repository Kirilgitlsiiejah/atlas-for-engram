# atlas-for-engram

Plug-and-play CRUD ecosystem for the **atlas knowledge layer** in [engram](https://github.com/Gentleman-Programming/engram). Lets you ingest, edit, delete, lookup, browse, and integrity-check `type=atlas` observations sourced from any markdown vault (built for Obsidian Web Clipper but vault-agnostic).

## Why

Engram has no native ingestion path for external knowledge clips (web articles, papers). This plugin fills that gap with 7 skills + 1 hook that orchestrate the full lifecycle around a per-vault `atlas-pool/` directory:

- **Ingestion**: Web Clipper drops markdown into your vault, then `inject-atlas` parses + saves to engram
- **Discoverability**: Auto-trigger PostToolUse hook on every `mem_search` separates own_work vs atlas results
- **CRUD**: Edit, delete, lookup, integrity-check
- **Browse**: Generates a navigable `Atlas-Index.md` in your vault root

Cross-OS (Windows Git Bash, macOS, Linux). Stack: bash + curl + jq + rg + fd. Same dependencies as the engram claude-code plugin.

## Compatibility

- **engram**: >= v1.13.0 (uses `/observations`, `/observations/recent`, `/observations/{id}` PATCH/DELETE, `/search`)
- **Claude Code**: any version supporting Skills + PostToolUse hooks
- **OS**: Windows (Git Bash), macOS, Linux

## Install

```bash
git clone https://github.com/Kirilgitlsiiejah/atlas-for-engram.git
cd atlas-for-engram
bash install.sh
```

The installer copies all skills to `$HOME/.claude/skills/` and prints the hook snippet you need to add to `$HOME/.claude/settings.json`.

## Quickstart

1. Configure your Web Clipper (or any markdown source) to write to `$VAULT_ROOT/atlas-pool/` (default `$HOME/vault/atlas-pool/`)
2. Clip an article, the markdown lands in `atlas-pool/`
3. In Claude Code: `inyectá al proyecto myproj la info de <article-title>` invokes `inject-atlas`
4. Browse: `atlas index` regenerates `$VAULT_ROOT/Atlas-Index.md`
5. Lookup: `atlas lookup <url>` answers "do I already have this?"
6. Cleanup: `atlas cleanup` produces an orphans/dangling/duplicates/malformed report

## Skills

| Skill | Trigger | Purpose |
|---|---|---|
| `inject-atlas` | "inyectá al proyecto X la info de Y" | CREATE: clip to engram |
| `atlas-edit` | "editá el atlas X" | UPDATE: PATCH `/observations/{id}` |
| `atlas-delete` | "borrá el atlas X" | DELETE: individual + bulk + raw cleanup |
| `atlas-lookup` | "tengo atlas de URL X?" | READ: cross-project URL search |
| `atlas-cleanup` | "atlas integrity check" | INTEGRITY: orphans/dangling/duplicates/malformed |
| `atlas-index` | "atlas index" | BROWSE: generates Atlas-Index.md |
| `compare-with-atlas` | "compará con atlas" + auto via hook | READ: separates own_work vs atlas results |

## Hook setup

Add to `$HOME/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__plugin_engram_engram__mem_search",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/skills/compare-with-atlas/hook.sh"
          }
        ]
      }
    ]
  }
}
```

`install.sh` will print this snippet so you can copy-paste safely (it does NOT modify your settings.json automatically since that is destructive).

## Architecture

```
Browser Web Clipper
        |
        v
   atlas-pool/<slug>.md  (raw markdown)
        |  (inject-atlas, manual trigger)
        v
   engram type=atlas, project=<auto-detected>
        |
        v
   Atlas-Index.md (auto-regen on every inject)
        |
        v
   Browse from Obsidian / any markdown editor
```

Project resolution: same algorithm as engram core, git remote, then git root basename, then cwd basename, fallback `dev`. Override per-invocation by passing project explicitly.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `ENGRAM_HOST` | `http://127.0.0.1:7437` | engram HTTP API URL |
| `ENGRAM_PORT` | `7437` | shorthand if HOST not set |
| `VAULT_ROOT` | `$HOME/vault` | vault root (parent of atlas-pool/) |
| `ATLAS_PROJECTS` | auto-detected | comma-separated list for `atlas-cleanup` cross-project scan |
| `MOVE_RAW_AFTER_INJECT` | `false` | move .md to `atlas-pool/injected/` after inject |
| `ATLAS_EDIT_CONFIRM_TYPE_CHANGE` | `false` | required `=yes` to change type of an atlas obs |

## Testing pedigree

This plugin survived a parallel adversarial review (judgment-day): 2 blind judges, 2 rounds, 21 confirmed fixes applied, 0 CRITICAL remaining. Independently re-verified end-to-end (sdd-verify): 8/8 requirements PASS. See commit history for fix details.

## Credits

- [engram](https://github.com/Gentleman-Programming/engram) by Gentleman-Programming
- Patterns aligned with engram's `claude-code` plugin (bash + curl + jq, defensive style, exit 0 always)

## License

MIT, see [LICENSE](./LICENSE).
