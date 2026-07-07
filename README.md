# KWS Box

KWS Box turns a fresh Ubuntu/Debian host into a comfortable SSH development
machine. It installs Zsh, Oh My Zsh, eza, Yazi, Tmux, Docker, uv, Bun, Vite+,
and common AI coding CLIs, then configures an automatically attached Tmux
workspace.

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

- Zsh as the default login shell, with Oh My Zsh, `git`, `zsh-autosuggestions`, and
  `zsh-syntax-highlighting`
- eza and Yazi, with an `eza`-powered `ls` alias and the `y` shell helper
- Tmux with mouse support, `Ctrl+a` prefix, useful splits, and SSH auto-attach
- Docker Engine and access through the `docker` group
- uv, Bun, Vite+, Agy CLI, Codex CLI, OpenCode, and Pi
- Vite+ managed mode for automatic Node.js and package-manager version selection
- Shared Bash, Zsh, and Tmux colors
- User-local binary paths in `~/.bashrc` and `~/.zshrc`

## Node.js versions with Vite+

Vite+ installs the `vp` command and manages the global Node.js runtime by
default. It resolves a project's version from `.node-version`,
`devEngines.runtime`, or `engines.node`, falling back to the global default and
then the latest LTS release.

```bash
vp env current       # Show the resolved Node.js version
vp env pin lts       # Pin the current project to the latest LTS
vp env default lts   # Set the global default
vp env doctor        # Diagnose the environment configuration
```

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

After setup, use `.codex/skills/change-kws-colors/SKILL.md` to inspect or change
the palette on an installed machine. Its bundled script validates HEX colors,
creates a backup, keeps the accent RGB value synchronized, and reloads active
Tmux sessions.
