# dotfiles

Personal dotfiles for Linux dev environments (VS Code devcontainers, GitHub Codespaces, fresh VMs).

**Public repo, zero PII baked in.** Identity + secrets are injected at runtime (host file mount, env vars, or CLI flags), never committed.

## Use with VS Code Dev Containers (recommended)

Two pieces of plumbing in your VS Code **user** settings (`Cmd+,` → "Open Settings (JSON)"):

```json
"dotfiles.repository": "hilikliming/dotfiles",
"dotfiles.targetPath": "~/dotfiles",
"dotfiles.installCommand": "install.sh",
"dev.containers.defaultFeatures": {
    "ghcr.io/hilikliming/dotfiles/claude-work:1": {},
    "ghcr.io/hilikliming/dotfiles/github-token:1": {},
    "ghcr.io/hilikliming/dotfiles/graphite-token:1": {},
    "ghcr.io/hilikliming/dotfiles/tks-workspace:1": {}
},
"terminal.integrated.defaultProfile.linux": "zsh"
```

> **Heads-up for forkers:** the `claude-work` Feature mounts the host's `~/.claude-work` dir, which is unusual. I use it because I run a work/personal Claude Code split (`CLAUDE_CONFIG_DIR=~/.claude-work` for the work account, default `~/.claude` for personal). If you don't have that split and use plain `~/.claude`, fork this Feature and change two paths: the mount `source` in `features/claude-work/devcontainer-feature.json` and the `CLAUDE_CONFIG_DIR` line in `zshrc.append`. Swap `.claude-work` for `.claude` in both spots.
>
> **This mount is also how the container authenticates.** It carries `.credentials.json`, so nothing injects an OAuth token. If you fork this and don't want your host Claude credentials visible inside containers, don't enable the Feature.

Plus one-time host setup (Mac, in a regular shell):

```sh
# 1. Load your work SSH key into the agent so git operations inside containers
#    can push. --apple-use-keychain persists across reboots.
ssh-add --apple-use-keychain ~/.ssh/<your-work-key>

# 2. Log the work profile in once, so ~/.claude-work exists and holds
#    credentials the containers can share. No `claude setup-token` involved:
#    Claude Code >= 2.1.197 keeps credentials per config dir.
CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude   # then /login

# 3. (Optional) GitHub CLI token for `gh` ops (PRs, issues, CI status).
#    Git push/pull goes over SSH via the forwarded agent. `gh` is only used
#    for API ops, so it gets its own PAT. Create at
#    https://github.com/settings/personal-access-tokens/new (fine-grained,
#    repo scope: Contents R/W, Pull requests R/W, Issues R/W, Actions R,
#    plus Organization → Members R if you want org listing). Fine-grained
#    PATs targeting org repos may need org admin approval before they work;
#    if cross-org access matters, fall back to a classic PAT with `repo`,
#    `read:org`, `workflow`.
umask 077
echo 'YOUR_GITHUB_PAT_HERE' > ~/.github-work-token

# 4. (Optional) Graphite CLI token. Get it from `gt auth status` on a host
#    where Graphite is already logged in, or from the Graphite web UI.
umask 077
echo 'YOUR_GRAPHITE_TOKEN_HERE' > ~/.graphite-work-token

# 5. (Optional) TKS. Install the CLI on the Mac, then create the workspace
#    the tks-workspace Feature mounts. Bare `gh` here uses the keychain OAuth
#    token, which is SAML-blocked for the TribeAI org; the fine-grained PAT
#    from step 3 is not, so pass it explicitly.
export GH_TOKEN="$(cat ~/.github-work-token)"
gh api repos/TribeAI/tks-cli/contents/scripts/install.sh \
  -H "Accept: application/vnd.github.raw" | bash
tks init ~/Code/knowledge
```

> **Keep the workspace out of `~/PersonalCode/`.** The Mac's `~/.gitconfig` has
> `includeIf "gitdir:~/PersonalCode/"` pointing at a personal email, so brains
> created under there would push commits to TribeAI-org repos under the wrong
> identity. Anywhere else inherits the work identity. The container is immune
> either way: that `includeIf` path never resolves inside it.

> **Token rotation:**
> - **Anthropic:** nothing to rotate. The container reads the same `.credentials.json` as the host through the bind mount, and Claude Code refreshes it in place using the stored refresh token. When the refresh token itself finally lapses, `/login` once (host or container, either writes through the mount) and every container picks it up live. This is the whole reason the old `anthropic-token` Feature was retired: an injected `CLAUDE_CODE_OAUTH_TOKEN` is a bare access token with no refresh token, so it could not renew, and it silently outranked the good credential whenever both were present.
> - **GitHub / Graphite:** overwrite the same file on the host (`umask 077; echo NEW > ~/.X-work-token`), then `exec zsh` in the container. `gh` and `gt` cache auth state, so on the next container rebuild the postCreate copy + `install.sh` re-auth will pick up the new token; for an existing container you can run `gh auth login --with-token < ~/.github-work-token` or `gt auth --token "$(cat ~/.graphite-work-token)"` directly to refresh without a rebuild.

That's it. Every devcontainer you open from then on will:

1. Auto-apply the `claude-work` Feature, which bind-mounts `~/.claude-work` from your Mac and symlinks it at both `$HOME/.claude-work` and `$HOME/.claude`. Credentials come from the `.credentials.json` inside it.
2. Run `install.sh` (no args), which sets up oh-my-zsh / `.alias` / `.zshrc`, then notices the work config mount and installs `@anthropic-ai/claude-code` plus the onboarding-skip marker.
3. Export `CLAUDE_CONFIG_DIR=$HOME/.claude-work` on every shell start (via `zshrc.append`). The `$HOME/.claude` symlink covers launchers that never source `.zshrc`.
4. Auto-apply the `tks-workspace` Feature, which bind-mounts `~/Code/knowledge` and symlinks it at `$HOME/knowledge`. `install.sh` then installs the `tks` CLI so the container agent can run the verbs, not just read the files.

Git identity is handled separately by VS Code's automatic copy of your host `~/.gitconfig` (`dev.containers.copyGitConfig`, default on).

### Why not pass secrets through `dotfiles.installCommand` args?

Because VS Code's installCommand parser doesn't handle arguments. It treats the whole `"install.sh --name '...' ..."` string as a single executable path and the install silently fails ([microsoft/vscode-remote-release#5673](https://github.com/microsoft/vscode-remote-release/issues/5673), closed unfixed). The Feature-based mounts sidestep the bug entirely and keep credentials out of `settings.json`.

### Caveats

- **Host files must exist** before opening a devcontainer. If `~/.claude-work`, `~/.github-work-token`, `~/.graphite-work-token`, or `~/Code/knowledge` is missing on the Mac while the corresponding Feature is enabled, the container will fail to start with `bind source path does not exist` (the dev containers spec doesn't yet support optional mounts, see [devcontainers/spec#132](https://github.com/devcontainers/spec/issues/132)). The bootstrap above creates all four; just don't delete them. If you don't want one of them, drop the matching entry from `dev.containers.defaultFeatures`. This bites hardest with `tks-workspace`: enable it before running `tks init` and *every* devcontainer stops opening, not just the one you wanted TKS in.
- **First publish of the Feature is private on GHCR.** After the GitHub Action publishes for the first time, visit `github.com/users/hilikliming/packages/container/dotfiles%2Fclaude-work/settings` and set visibility to Public so the devcontainer CLI can pull without auth.
- **`devcontainer-lock.json` may pin the Feature reference** into team repos ([microsoft/vscode-remote-release#11616](https://github.com/microsoft/vscode-remote-release/issues/11616)). To avoid accidentally committing it, the global gitignore covers it:
  ```sh
  echo '.devcontainer/devcontainer-lock.json' >> ~/.config/git/ignore
  ```
- **Codespaces:** `${localEnv:HOME}` resolves to the Codespaces host (`/home/codespace`), where `~/.claude-work` won't exist. Either bootstrap it in your Codespaces dotfiles flow, or remove `dev.containers.defaultFeatures` from your Settings Sync profile for Codespaces use.

## Use manually (no VS Code)

Args or env vars, whichever fits:

```sh
git clone https://github.com/hilikliming/dotfiles ~/dotfiles

# Option A: args
~/dotfiles/install.sh --name "Your Name" --email "you@example.com"

# Option B: env vars
DOTFILES_GIT_USER_NAME="..." \
DOTFILES_GIT_USER_EMAIL="..." \
  ~/dotfiles/install.sh
```

The Claude setup (CLI install + onboarding-skip) fires when a work config dir is present, either as the Feature's mount at `/var/claude-work.mount` or as `~/.claude-work`. Outside a devcontainer, log in normally with `claude` and `/login`. Idempotent, safe to re-run.

## What it does

- Installs oh-my-zsh (unattended). Its `git` plugin's aliases (`gst`, `gpsup`, `gd`, `gco`, `gcb`, etc.) come along for free
- Sets zsh as the user's login shell (where permissions allow)
- Drops `.alias` into `$HOME` (kubectl shortcuts, nav helpers, `git` → `gt` routing when Graphite is installed)
- Maintains a marker-guarded block in `~/.zshrc` (rewritten on each run, so `zshrc.append` updates apply cleanly)
- Sets `git user.name` / `user.email` *if* provided via arg or env var (otherwise relies on host `~/.gitconfig` copy in devcontainers)
- When a work config dir is present (`/var/claude-work.mount` or `~/.claude-work`):
  - Installs `@anthropic-ai/claude-code` via npm (via mise-managed node if needed)
  - Pre-marks the onboarding wizard complete so credentials take effect immediately
  - `zshrc.append` exports `CLAUDE_CONFIG_DIR=$HOME/.claude-work` on every shell start
- Installs `gh` (GitHub CLI) from the official apt repo when it's missing and `apt-get` is available
- When `~/.github-work-token` is present and non-empty (via the `github-token` Feature):
  - Bind-mounts the file from host and stages it at `$HOME/.github-work-token` (mode 600, owned by the container user)
  - Runs `gh auth login --with-token` from it once `gh` is on PATH, so API ops (PRs, issues, CI) work out of the box
  - Does **not** run `gh auth setup-git` (git push/pull stays on SSH via the forwarded agent)
- When `~/.graphite-work-token` is present and non-empty (via the `graphite-token` Feature):
  - Bind-mounts the file from host and stages it at `$HOME/.graphite-work-token` (mode 600, owned by the container user)
  - Runs `gt auth --token "$(cat ...)"` if `gt` is on PATH (the team's `setup.sh` installs `gt` via mise before this script runs)
- When `~/.claude-work` exists on the host (via the `claude-work` Feature):
  - Bind-mounts host `~/.claude-work` into the container and symlinks it at **both** `$HOME/.claude-work` and `$HOME/.claude`
  - `zshrc.append` exports `CLAUDE_CONFIG_DIR=$HOME/.claude-work` so Claude Code reads/writes the shared config dir
  - The `$HOME/.claude` link is what makes env-blind launchers work. The VS Code Claude Code panel, tasks, and non-login shells never source `.zshrc`, so they fall back to the default config dir. Before that link existed they found no credentials there and prompted `/login` on every invocation
  - Credentials live in the mounted `.credentials.json`, so a login on either side of the boundary serves both, and refreshes write through the mount
  - Preferences, global memories, and `settings.json` persist across container rebuilds and stay in sync with the host's Claude Code
  - **Note:** on macOS the host stores its own credential in the Keychain (namespaced per config dir, e.g. `Claude Code-credentials-<hash>`), not in `.credentials.json`. Linux containers have no Keychain and use the file. So the two sides can hold independent logins that both work; the file is the container's store
  - **Caveat: per-project conversation transcripts and per-project memories do NOT auto-merge across the host/container boundary.** Claude Code scopes them by cwd-derived project path (e.g. host cwd `/Users/jhall` becomes `projects/-Users-jhall/`, container cwd `/workspaces/k-and-e-transaction-management-platform` becomes `projects/-workspaces-k-and-e-.../`). Different folders inside the same `projects/` tree means "resume yesterday's host conversation from inside the container" doesn't just work. Global settings travel, project-scoped state doesn't.
- When `~/Code/knowledge` exists on the host (via the `tks-workspace` Feature):
  - Bind-mounts it into the container and symlinks it at `$HOME/knowledge`. One link is enough, unlike `claude-work`: `tks` finds a workspace by walking up from cwd for `_workspace/manifest.yaml`, so nothing depends on a fixed `$HOME` path
  - Installs the `tks` CLI with `mise use -g "github:TribeAI/tks-cli@latest"` (standalone binary, no Node at runtime, no `~/.zshrc` edit), falling back to the official `gh`-piped installer on images without mise
  - Runs *after* the `gh` login step, because both install paths fetch a private release asset. The PAT is passed as `MISE_GITHUB_TOKEN` explicitly rather than relying on mise reading `gh`'s stored token, since that login is allowed to fail non-fatally
  - **TKS keeps nothing under `~/.claude`**, so the `claude-work` mount carries none of it. Only the workspace persists across rebuilds, through its own mount. `~/.tks`, the mise shim, and `~/.config/tks/telemetry.json` are container-local and reinstalled every time
  - Git operations against the `tks-*` source repos go over the forwarded SSH agent, which is SSO-authorized for the TribeAI org. Only the release-asset download needs the PAT
  - Because host and container share one directory, sessions the container agent writes appear in the Mac's Obsidian vault live, with no sync step
- When the mounted work config dir carries the `deep-security` skill:
  - Runs that skill's own `ci_install_scanners.sh full` to provision the scanner kit (opengrep, gitleaks, osv-scanner, bandit, checkov; trivy already comes from the project's mise config)
  - `$HOME/.local/bin` has no volume, so these are wiped on every rebuild. Without this the skill reports 6 of 8 scanners MISSING and every scan comes back DEGRADED until someone reinstalls them by hand
  - Provisions `uv` globally via mise first, since `bandit` and `checkov` install through `uv tool` and uv otherwise comes only from a project's `.mise.toml`, which does not apply in `~/dotfiles`
- When mise is present, installs `herdr@0.9.5` (agent multiplexer) and `jq` globally via mise, each only if it doesn't already run. `jq` is there for the herdr-dispatch skills, since it otherwise comes only from a project's `.mise.toml`
  - Deliberately does **not** run `herdr integration install claude`: it writes a hook with an absolute container path into the shared `settings.json`, so the Mac's Claude Code would hit a missing file on every session start. herdr reads Claude's working/blocked/idle state from the screen without it
  - If the hook is ever wanted, rewrite its command to the portable form `sh "${CLAUDE_CONFIG_DIR:-$HOME/.claude-work}/hooks/herdr-agent-state.sh" session` (the statusline in that `settings.json` already uses this form)
  - Inside a container, attach with `herdr session attach <name>` from the VS Code terminal. Warp can't be opened from inside the container, so herdr-dispatch needs `--no-warp`
