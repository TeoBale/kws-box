# KWS Box

KWS Box turns a fresh Ubuntu/Debian host into a comfortable SSH development
machine. It installs Zsh, Oh My Zsh, Tmux, Docker, uv, Bun, and common AI coding
CLIs, then configures an automatically attached Tmux workspace.

The setup is idempotent: existing tools and user-defined theme colors are
preserved when the installer runs again.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/TeoBale/kws-box/main/setup.sh | bash
```

Reconnect after installation. Interactive SSH sessions automatically attach to
the `main` Tmux session. To bypass auto-attach once:

```bash
TMUX_DISABLE_AUTOATTACH=1 ssh user@host
```

## What it configures

- Zsh and Oh My Zsh
- Tmux with mouse support, `Ctrl+a` prefix, useful splits, and SSH auto-attach
- Docker Engine and access through the `docker` group
- uv, Bun, Agy CLI, Codex CLI, OpenCode, and Pi
- Shared Bash, Zsh, and Tmux colors
- User-local binary paths in `~/.bashrc`

## Shared color theme

The global palette lives on the installed machine at:

```text
~/.config/kws-box/theme.conf
```

It is the source of truth for Bash, Zsh, Tmux, and future application adapters.
Edit the palette, keeping `KWS_THEME_ACCENT` and `KWS_THEME_ACCENT_RGB` in sync,
then reload it:

```bash
kws-theme-reload
```

Alternatively, start a new shell. Tmux alone can be refreshed with:

```bash
tmux source-file ~/.tmux.conf
```

Application-specific adapters are generated in `~/.config/kws-box/`. The
installer creates `theme.conf` only when it is missing, so local palette choices
survive subsequent runs.

## Main Tmux shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+a c` | Create a window in the current directory |
| `Ctrl+a \|` | Split vertically |
| `Ctrl+a -` | Split horizontally |
| `Ctrl+a h/j/k/l` | Move between panes |
| `Ctrl+a H/J/K/L` | Resize panes |
| `Ctrl+a z` | Toggle pane zoom |
| `Ctrl+a d` | Detach without stopping the session |
| `Ctrl+a r` | Reload `~/.tmux.conf` |

## Theme maintenance for agents

The project-local skill at
`.codex/skills/manage-kws-theme/SKILL.md` documents how to change the palette or
extend the theme to another application without introducing duplicated color
configuration.
