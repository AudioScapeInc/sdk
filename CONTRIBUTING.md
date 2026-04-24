# Contributing to audioscape-sdk

## Setup

```sh
# Rokit (one-time, system-wide) — installs pinned lune/rojo/stylua/selene/luau-lsp/wally
rokit self-install    # https://github.com/rojo-rbx/rokit/releases
rokit install

# Add Rokit's bin to your shell PATH if not already:
#   fish:       fish_add_path $HOME/.rokit/bin
#   bash/zsh:   export PATH="$HOME/.rokit/bin:$PATH"
```

## Local checks

```sh
# Static analysis (Cmd+Shift+B in VS Code): stylua → selene → luau-lsp
stylua --check src/ tests/ examples/
selene src/ tests/
rojo sourcemap default.project.json --output sourcemap.json && \
  luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau \
    --base-luaurc=.luaurc --platform=roblox src/ tests/ examples/

# Unit tests (default test task in VS Code)
lune run tests/run.luau

# Full CI pipeline locally via act (runs both jobs, including openCloud smoke):
act --secret-file .env.integration

# Open Cloud smoke directly (faster than act, skips the container build):
set -a; source .env.integration; set +a; lune run tests/openCloud/smoke.luau
```

Auto-format: `stylua src/ tests/ examples/`.

## Test layers

| Layer | What | Where | When |
| --- | --- | --- | --- |
| Unit | URL building, error mapping, retry math, mocked HTTP | `tests/*.spec.luau` via Lune | every CI run |
| Integration | Every HTTP-hitting public method against the real API, through real Roblox engine (HttpService / Sound / RemoteFunction) | `tests/openCloud/smoke.luau` via Open Cloud Luau Execution | every CI run with `ROBLOX_API_KEY` set |
| Manual | Audio playback + `BindToClose` shutdown flush (Luau Execution doesn't run BindToClose callbacks) | Roblox Studio | pre-release |

For the manual pass you can drive Studio via the Roblox Studio MCP (see your Claude Code config) — `execute_luau` runs server-side scripts, `start_stop_play` plays the place, `get_console_output` surfaces warnings.

## Open Cloud smoke — first-time setup

1. **Create a dedicated test place.** Separate universe. Enable HttpService (Studio → Game Settings → Security → Allow HTTP Requests).
2. **Provision the AudioScape key as a Roblox Secret.** Creator Hub → your experience → Secrets → `AUDIOSCAPE_KEY` = your AudioScape API key. The smoke retrieves it via `HttpService:GetSecret` so it never materialises as a plain string in code.
3. **Create an Open Cloud API key** with the `universe.place.luau-execution-session:write` scope for your test place. Creator Hub → Open Cloud → API Keys.
4. **Copy `.env.integration.example` → `.env.integration`** (gitignored) and fill in the three Roblox vars.
5. **Create the `openCloud-smoke` GitHub environment with a required reviewer** and store the three secrets there (not repo-scoped). See below.

### CI topology + security gate

The workflow is split into two jobs:

- `qa` — lint + static analysis + unit tests. Runs on every PR. No secrets, no gate.
- `smoke` — `needs: qa`, declares `environment: openCloud-smoke`. Secrets live on that environment. A maintainer must approve each run before secrets are exposed to the job.

Why the gate: a malicious commit to `tests/openCloud/smokeScript.luau` on a repo-internal branch could `print(HttpService:GetSecret("AUDIOSCAPE_KEY"))` or otherwise exfiltrate `ROBLOX_API_KEY`. Required-reviewer protection means a human looks at the diff before secrets are released to that run. Forked PRs skip the smoke job entirely (job-level `if` checks `head.repo.full_name`).

One-time setup via `gh`:

```sh
USER_ID=$(gh api user --jq .id)

# Create the environment with yourself as required reviewer.
gh api --method PUT repos/<owner>/<repo>/environments/openCloud-smoke --input - <<EOF
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [{"type": "User", "id": $USER_ID}],
  "deployment_branch_policy": null
}
EOF

# Store the three secrets on the environment (not repo-scoped).
(
  set -a && source .env.integration && set +a
  printf '%s' "$ROBLOX_API_KEY" | gh secret set ROBLOX_API_KEY --env openCloud-smoke
  printf '%s' "$ROBLOX_TEST_UNIVERSE_ID" | gh secret set ROBLOX_TEST_UNIVERSE_ID --env openCloud-smoke
  printf '%s' "$ROBLOX_TEST_PLACE_ID" | gh secret set ROBLOX_TEST_PLACE_ID --env openCloud-smoke
)
```

## VS Code

Three tasks (Cmd+Shift+P → Run Task):

- `static analysis: stylua + selene + luau-lsp` — default build (Cmd+Shift+B)
- `unit tests (lune)` — default test (Cmd+Shift+P → Run Test Task)
- `act: full CI workflow with .env.integration secrets` — runs both jobs (qa → smoke) in a container locally

## Run CI locally with `act`

```sh
brew install act
act --secret-file .env.integration
```

`.actrc` pins the runner image and linux/amd64 arch (needed on Apple Silicon). `act` ignores `environment:` protection (no reviewer gate locally), so both jobs run back-to-back against your `.env.integration`.

## House style

- `--!strict` on every production `.luau` file under `src/` and `tests/`. CI fails on any `luau-lsp analyze` error.
- Examples (`examples/*.luau`) use `--!nocheck` — they reference Roblox service paths that don't exist in this project's sourcemap.
- Tabs for indentation, 120-col width (`.stylua.toml`).
- Test files end in `.spec.luau` and live under `tests/`. Integration coverage lives in `tests/openCloud/smoke.luau`.
- Every `assert(...)` needs a message — selene's roblox std rejects single-arg asserts.

## Release

1. Bump `version` in `wally.toml`.
2. Add a top entry in `CHANGELOG.md` (focus on what changes for the consumer).
3. Full local CI sequence green, including `openCloud smoke`.
4. **Verify the package snapshot**: `diff <(wally package --list | LC_ALL=C sort) tests/wally-package.expected.txt`. If intentional additions: `wally package --list | LC_ALL=C sort > tests/wally-package.expected.txt`.
5. Manual Studio pass — audio playback + BindToClose shutdown flush (see Test layers above).
6. `chore: release vX.Y.Z — <summary>`, tag `git tag vX.Y.Z && git push --tags`, `wally publish`.
