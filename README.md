# dotfiles

Personal dotfiles for Linux dev environments — VS Code devcontainers, GitHub Codespaces, fresh VMs.

**Public repo, zero PII baked in.** Git identity is passed in by the caller (CLI flag or env var), so this repo can stay public without leaking work emails to scrapers.

## Use with VS Code Dev Containers (recommended)

Add to your VS Code **user** settings (`Cmd+,` → "Open Settings (JSON)" — local file on your Mac, not synced unless you enable settings sync):

```json
"dotfiles.repository": "hilikliming/dotfiles",
"dotfiles.targetPath": "~/dotfiles",
"dotfiles.installCommand": "install.sh --name 'Your Name' --email 'you@example.com'",
"terminal.integrated.defaultProfile.linux": "zsh"
```

Next devcontainer build: VS Code clones this repo into `~/dotfiles` and runs `install.sh` with your identity. Identity lives in your local VS Code settings, never in this repo.

## Use manually

```sh
git clone https://github.com/hilikliming/dotfiles ~/dotfiles
~/dotfiles/install.sh --name "Your Name" --email "you@example.com"
```

Or via env vars (handy when you've already exported them):

```sh
DOTFILES_GIT_USER_NAME="..." DOTFILES_GIT_USER_EMAIL="..." ~/dotfiles/install.sh
```

If you skip `--name`/`--email` (and the env vars aren't set), everything else still installs — git identity just won't be configured. Set it manually later with `git config --global`.

## What it does

- Installs oh-my-zsh (unattended)
- Sets zsh as the user's login shell (where permissions allow)
- Drops `.alias` into `$HOME` (kubectl shortcuts + nav helpers)
- Appends a single marker-guarded source line to `~/.zshrc`
- Sets `git user.name` / `user.email` *if* provided via flag or env var

Idempotent. Re-running won't double-source or reinstall anything.
