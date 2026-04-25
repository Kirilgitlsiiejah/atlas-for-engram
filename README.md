# atlas-for-engram

Plug-and-play CRUD ecosystem for the **atlas knowledge layer** in [engram](https://github.com/Gentleman-Programming/engram). Lets you ingest, edit, delete, lookup, browse, and integrity-check `type=atlas` observations sourced from any markdown vault (built for Obsidian Web Clipper but vault-agnostic).

## Why

Engram has no native ingestion path for external knowledge clips (web articles, papers). This plugin fills that gap with 7 skills + 2 hooks that orchestrate the full lifecycle around a per-vault `atlas-pool/` directory:

- **Ingestion**: Web Clipper drops markdown into your vault, then `inject-atlas` parses + saves to engram
- **Discoverability**: Auto-trigger PostToolUse hook on every `mem_search` separates own_work vs atlas results
- **CRUD**: Edit, delete, lookup, integrity-check
- **Browse**: Generates a navigable `Atlas-Index.md` in your vault root
- **Self-check**: SessionStart doctor surfaces missing deps, engram down, legacy hook conflicts

Cross-OS (Windows Git Bash, macOS, Linux). Stack: bash + curl + jq + rg + fd. Same dependencies as the engram claude-code plugin.

## Install (recommended — native plugin)

```bash
claude plugin marketplace add Kirilgitlsiiejah/atlas-for-engram
claude plugin install atlas
```

The marketplace points at this repo's `.claude-plugin/marketplace.json`. Once installed, Claude Code resolves all skills, hooks, and scripts from `${CLAUDE_PLUGIN_ROOT}` automatically — no manual file copies, no settings.json edits.

To update later:

```bash
claude plugin update atlas
```

## Install (legacy / manual)

> **DEPRECATED — removed in v0.2.0.** Kept temporarily for users on older Claude Code versions without native plugin support. New users should always use the native install above.

```bash
git clone https://github.com/Kirilgitlsiiejah/atlas-for-engram.git
cd atlas-for-engram
bash install.sh
```

The legacy installer copies skills to `$HOME/.claude/skills/` and prints a hook snippet for `$HOME/.claude/settings.json`. If you used this path before, **remove the legacy hook** from `~/.claude/settings.json` after switching to the native plugin — otherwise the PostToolUse fires twice.

## Skills

| Skill | Trigger | Purpose |
|---|---|---|
| `inject-atlas` | "inyectá al proyecto X la info de Y" | CREATE — parse atlas-pool .md and save to engram as type=atlas |
| `atlas-edit` | "editá el atlas X" | UPDATE — PATCH `/observations/{id}` with field=value pairs |
| `atlas-delete` | "borrá el atlas X" | DELETE — individual + bulk + optional raw .md cleanup |
| `atlas-lookup` | "tengo atlas de URL X?" | READ — cross-project URL search |
| `atlas-cleanup` | "atlas integrity check" | INTEGRITY — orphans / dangling / duplicates / malformed report |
| `atlas-index` | "atlas index" | BROWSE — regenerates `Atlas-Index.md` in vault root |
| `compare-with-atlas` | "compará con atlas" + auto via PostToolUse hook | READ — separates own_work vs atlas results in mem_search |

## Architecture

```
Browser Web Clipper
        |
        v
   ${VAULT_ROOT}/atlas-pool/<slug>.md  (raw markdown, no project)
        |  inject-atlas (manual trigger)
        v
   engram type=atlas, project=<auto-detected from git>
        |
        +--> Atlas-Index.md  (auto-regen on every inject)
        |
        +--> mem_search → compare-with-atlas hook → own_work vs atlas
        |
        v
   Browse / retrieve from any markdown editor or claude-code session
```

The plugin lives entirely under `${CLAUDE_PLUGIN_ROOT}` once installed:

```
${CLAUDE_PLUGIN_ROOT}/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── hooks/
│   └── hooks.json          # PostToolUse + SessionStart registration
├── scripts/
│   ├── _helpers.sh         # detect_project / resolve_project
│   ├── _doctor.sh          # healthcheck (4 checks)
│   └── session-start.sh    # SessionStart shim → calls _doctor.sh
└── skills/
    ├── inject-atlas/
    ├── atlas-edit/
    ├── atlas-delete/
    ├── atlas-lookup/
    ├── atlas-cleanup/
    ├── atlas-index/
    └── compare-with-atlas/
```

Project resolution: same algorithm as engram core — git remote → git root basename → cwd basename → fallback `dev`. Override per-invocation by passing project explicitly.

## Hooks

The plugin registers two hooks via `hooks/hooks.json`:

### PostToolUse — `compare-with-atlas`

Matcher: `mcp__plugin_engram_engram__mem_search`. After every `mem_search` call, the hook reads the JSON tool_response on stdin, splits the results by `type` (own_work vs `type=atlas`), and emits an `additionalContext` payload so the agent presents the results with provenance. Silent if no atlas results.

### SessionStart — atlas doctor

Matcher: `startup|clear`. Runs `scripts/session-start.sh` (which calls `scripts/_doctor.sh`) at every session start and after `/clear`. Timeout 3s, status message `atlas: checking environment...`. If everything is healthy, the hook is silent.

## Doctor

`scripts/_doctor.sh` runs four checks, each <100ms in a healthy env:

1. **engram reachable** — `GET http://${ENGRAM_HOST}/health` with 1s timeout
2. **deps present** — `jq`, `curl`, `rg`, `fd` on PATH
3. **vault layout** — `${VAULT_ROOT:-$HOME/vault}/atlas-pool/` exists
4. **no legacy hook** — `~/.claude/settings.json` does NOT contain a PostToolUse hook for `compare-with-atlas` (would double-fire alongside the native plugin)

Exit codes:

- `0` always — never blocks session start
- stdout empty → silent OK (healthy env)
- stdout JSON → warnings surfaced as `additionalContext` for the agent

Example output (unhealthy env):

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "atlas-doctor:\n  - engram unreachable at http://127.0.0.1:7437\n  - missing commands: fd\n  - atlas-pool not found at /home/u/vault/atlas-pool\n"
  }
}
```

Run manually any time:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/_doctor.sh
```

## Troubleshooting

**engram unreachable**: start engram (`engram serve` or however you run it) and re-check with `curl -sf http://127.0.0.1:7437/health`. Override host with `ENGRAM_HOST=host:port`.

**missing commands**: install whichever the doctor flagged. On Windows Git Bash use scoop / chocolatey. On macOS `brew install jq curl ripgrep fd`. On Linux use your package manager — the names are usually `jq curl ripgrep fd-find`.

**atlas-pool not found**: create it (`mkdir -p $HOME/vault/atlas-pool`) and point your Web Clipper output there. Override the parent with `VAULT_ROOT=/path/to/vault`.

**legacy hook detected (double-fire)**: you installed via `bash install.sh` previously and switched to the native plugin. Open `~/.claude/settings.json`, remove the `PostToolUse` entry whose `command` matches `.claude/skills/compare-with-atlas`, save. The native plugin's `hooks/hooks.json` covers it.

## Compatibility

- **engram**: >= v1.13.0 (uses `/observations`, `/observations/recent`, `/observations/{id}` PATCH/DELETE, `/search`)
- **Claude Code**: any version supporting native plugins + skills + PostToolUse + SessionStart hooks
- **OS**: Windows (Git Bash), macOS, Linux
- **Deps**: `bash`, `jq`, `curl`, `rg` (ripgrep), `fd`

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `ENGRAM_HOST` | `http://127.0.0.1:7437` | engram HTTP API URL |
| `ENGRAM_PORT` | `7437` | shorthand if HOST not set |
| `VAULT_ROOT` | `$HOME/vault` | vault root (parent of atlas-pool/) |
| `ATLAS_PROJECTS` | auto-detected | comma-separated list for `atlas-cleanup` cross-project scan |
| `MOVE_RAW_AFTER_INJECT` | `false` | move .md to `atlas-pool/injected/` after inject |
| `ATLAS_EDIT_CONFIRM_TYPE_CHANGE` | `false` | required `=yes` to change type of an atlas obs |

## License

MIT, see [LICENSE](./LICENSE).

## Relationship to engram

This is a **community / companion plugin** for [engram](https://github.com/Gentleman-Programming/engram). It integrates with engram's HTTP API and follows engram's claude-code plugin conventions (bash + curl + jq, defensive style, exit 0 always), but it is **not officially affiliated with, endorsed by, or maintained by the engram project**.

This plugin is independently maintained. Bugs, feature requests, and PRs go here, not to the engram repository.
