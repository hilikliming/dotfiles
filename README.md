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
    "ghcr.io/hilikliming/dotfiles/anthropic-token:1": {},
    "ghcr.io/hilikliming/dotfiles/claude-work:1": {}
},
"terminal.integrated.defaultProfile.linux": "zsh"
```

> **Heads-up for forkers:** the `claude-work` Feature mounts the host's `~/.claude-work` dir, which is unusual. I use it because I run a work/personal Claude Code split (`CLAUDE_CONFIG_DIR=~/.claude-work` for the work account, default `~/.claude` for personal). If you don't have that split and use plain `~/.claude`, fork this Feature and change two paths: the mount `source` in `features/claude-work/devcontainer-feature.json` and the `CLAUDE_CONFIG_DIR` line in `zshrc.append`. Swap `.claude-work` for `.claude` in both spots.

Plus one-time host setup (Mac, in a regular shell):

```sh
# 1. Load your work SSH key into the agent so git operations inside containers
#    can push. --apple-use-keychain persists across reboots.
ssh-add --apple-use-keychain ~/.ssh/<your-work-key>

# 2. Generate an OAuth token if you don't already have one
claude              # log in to the account you want the container to use
claude setup-token  # outputs a 1-year token

# 3. Save it where the Feature will look for it
umask 077
echo 'YOUR_OAUTH_TOKEN_HERE' > ~/.anthropic-work-key
```

> **Token rotation:** `claude setup-token` tokens expire after about a year. When `claude` inside the container starts failing on auth, just regenerate (same `claude setup-token`), overwrite `~/.anthropic-work-key` on host, then `exec zsh` in any container shell to re-read the env var. No rebuild needed: the bind mount surfaces the new contents live.

That's it. Every devcontainer you open from then on will:

1. Auto-apply the `anthropic-token` Feature, which bind-mounts `~/.anthropic-work-key` from your Mac into the container and installs it at `$HOME/.anthropic-work-key` (mode 0600, owned by the container user).
2. Run `install.sh` (no args), which sets up oh-my-zsh / `.alias` / `.zshrc`, then notices the token file is already in place and installs `@anthropic-ai/claude-code` plus the onboarding-skip marker.
3. Export `CLAUDE_CODE_OAUTH_TOKEN` from the token file on every shell start (via `zshrc.append`).

Git identity is handled separately by VS Code's automatic copy of your host `~/.gitconfig` (`dev.containers.copyGitConfig`, default on).

### Why not pass the token through `dotfiles.installCommand` args?

Because VS Code's installCommand parser doesn't handle arguments. It treats the whole `"install.sh --name '...' ..."` string as a single executable path and the install silently fails ([microsoft/vscode-remote-release#5673](https://github.com/microsoft/vscode-remote-release/issues/5673), closed unfixed). The Feature-based mount sidesteps the bug entirely and keeps the token out of `settings.json`.

### Caveats

- **Host file must exist** before opening a devcontainer. If `~/.anthropic-work-key` is missing on the Mac, the container will fail to start with `bind source path does not exist` (the dev containers spec doesn't yet support optional mounts, see [devcontainers/spec#132](https://github.com/devcontainers/spec/issues/132)). The bootstrap above creates it; just don't delete it.
- **First publish of the Feature is private on GHCR.** After the GitHub Action publishes for the first time, visit `github.com/users/hilikliming/packages/container/dotfiles%2Fanthropic-token/settings` and set visibility to Public so the devcontainer CLI can pull without auth.
- **`devcontainer-lock.json` may pin the Feature reference** into team repos ([microsoft/vscode-remote-release#11616](https://github.com/microsoft/vscode-remote-release/issues/11616)). To avoid accidentally committing it, the global gitignore covers it:
  ```sh
  echo '.devcontainer/devcontainer-lock.json' >> ~/.config/git/ignore
  ```
- **Codespaces:** `${localEnv:HOME}` resolves to the Codespaces host (`/home/codespace`), where `~/.anthropic-work-key` won't exist. Either bootstrap that file in your Codespaces dotfiles flow, or remove `dev.containers.defaultFeatures` from your Settings Sync profile for Codespaces use.

## Use manually (no VS Code)

Args, env vars, or a pre-placed token file all work. Pick whichever fits the situation:

```sh
git clone https://github.com/hilikliming/dotfiles ~/dotfiles

# Option A: pass everything as args
~/dotfiles/install.sh \
  --name "Your Name" \
  --email "you@example.com" \
  --anthropic-token "YOUR_OAUTH_TOKEN"

# Option B: env vars
DOTFILES_GIT_USER_NAME="..." \
DOTFILES_GIT_USER_EMAIL="..." \
DOTFILES_ANTHROPIC_OAUTH_TOKEN="..." \
  ~/dotfiles/install.sh

# Option C: place the token file beforehand, then run with no args
echo 'YOUR_OAUTH_TOKEN' > ~/.anthropic-work-key && chmod 600 ~/.anthropic-work-key
~/dotfiles/install.sh
```

The Claude setup (CLI install + onboarding-skip) fires whenever `~/.anthropic-work-key` ends up non-empty, regardless of which path put it there. Idempotent, safe to re-run.

## What it does

- Installs oh-my-zsh (unattended). Its `git` plugin's aliases (`gst`, `gpsup`, `gd`, `gco`, `gcb`, etc.) come along for free
- Sets zsh as the user's login shell (where permissions allow)
- Drops `.alias` into `$HOME` (kubectl shortcuts, nav helpers, `git` → `gt` routing when Graphite is installed)
- Maintains a marker-guarded block in `~/.zshrc` (rewritten on each run, so `zshrc.append` updates apply cleanly)
- Sets `git user.name` / `user.email` *if* provided via arg or env var (otherwise relies on host `~/.gitconfig` copy in devcontainers)
- When `~/.anthropic-work-key` is present and non-empty:
  - Installs `@anthropic-ai/claude-code` via npm (via mise-managed node if needed)
  - Pre-marks the onboarding wizard complete so the token takes effect immediately
  - `zshrc.append` auto-exports `CLAUDE_CODE_OAUTH_TOKEN` from the file on every shell start
- When `~/.claude-work` exists on the host (via the `claude-work` Feature):
  - Bind-mounts host `~/.claude-work` into the container and symlinks it at `$HOME/.claude-work`
  - `zshrc.append` exports `CLAUDE_CONFIG_DIR=$HOME/.claude-work` so Claude Code reads/writes the shared config dir
  - Preferences, global memories, and `settings.json` persist across container rebuilds and stay in sync with the host's Claude Code
  - **Caveat: per-project conversation transcripts and per-project memories do NOT auto-merge across the host/container boundary.** Claude Code scopes them by cwd-derived project path (e.g. host cwd `/Users/jhall` becomes `projects/-Users-jhall/`, container cwd `/workspaces/k-and-e-transaction-management-platform` becomes `projects/-workspaces-k-and-e-.../`). Different folders inside the same `projects/` tree means "resume yesterday's host conversation from inside the container" doesn't just work. Global settings travel, project-scoped state doesn't.
