# dotfiles

Personal dotfiles for Linux dev environments — VS Code devcontainers, GitHub Codespaces, fresh VMs.

**Public repo, zero PII baked in.** Identity + secrets are passed in by the caller (CLI flags, env vars, or VS Code user settings), so this repo can stay public without leaking work emails or tokens.

## Use with VS Code Dev Containers

Add to your VS Code **user** settings (`Cmd+,` → "Open Settings (JSON)" — local file on your Mac):

```json
"dotfiles.repository": "hilikliming/dotfiles",
"dotfiles.targetPath": "~/dotfiles",
"dotfiles.installCommand": "install.sh --name 'Your Name' --email 'you@example.com' --anthropic-token 'YOUR_OAUTH_TOKEN'",
"terminal.integrated.defaultProfile.linux": "zsh"
```

Drop the `--anthropic-token` chunk if you'd rather log in via `claude /login` manually inside each container.

> **Token tradeoff:** Putting the OAuth token in `installCommand` keeps it in `~/Library/Application Support/Code/User/settings.json` (mode 0644, local-only on your Mac, not synced unless you enable Settings Sync). Less restrictive than the 0600 perms on `~/.anthropic-work-key` directly. Worth it for fully automatic devcontainer setup; skip it if you want stricter at-rest perms.

## Use manually

```sh
git clone https://github.com/hilikliming/dotfiles ~/dotfiles
~/dotfiles/install.sh \
  --name "Your Name" \
  --email "you@example.com" \
  --anthropic-token "YOUR_OAUTH_TOKEN"
```

Env-var equivalents (handy for one-off shell sessions):

```sh
DOTFILES_GIT_USER_NAME="..." \
DOTFILES_GIT_USER_EMAIL="..." \
DOTFILES_ANTHROPIC_OAUTH_TOKEN="..." \
  ~/dotfiles/install.sh
```

## What it does

- Installs oh-my-zsh (unattended)
- Sets zsh as the user's login shell (where permissions allow)
- Drops `.alias` into `$HOME` (kubectl shortcuts + nav helpers)
- Maintains a marker-guarded block in `~/.zshrc` (rewritten on each run, so `zshrc.append` updates apply cleanly)
- Sets `git user.name` / `user.email` *if* provided
- Installs `@anthropic-ai/claude-code` via npm and configures it for your work OAuth token *if* `--anthropic-token` provided
  - Writes token to `~/.anthropic-work-key` (mode 0600)
  - `zshrc.append` auto-exports `CLAUDE_CODE_OAUTH_TOKEN` from that file on every shell start
  - Pre-marks the onboarding wizard complete so the token takes effect immediately

Idempotent. Re-running is safe.

## Generating an Anthropic OAuth token

If you don't already have one in `~/.anthropic-work-key` on your Mac, generate one once:

```sh
claude            # interactive — log in to the account you want the container to use
claude setup-token   # outputs a 1-year OAuth token; copy it into VS Code settings or save to ~/.anthropic-work-key
```
