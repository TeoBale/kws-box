---
name: manage-kws-theme
description: Maintain and extend the shared KWS Box color palette across shell, Tmux, and future applications. Use when changing theme colors, prompt styling, generated theme adapters, reload behavior, or adding another application to the global theme system in setup.sh.
---

# Manage the KWS Box theme

Treat `~/.config/kws-box/theme.conf` as the installed machine's color source of truth and `configure_global_theme` in `setup.sh` as its installer.

## Workflow

1. Inspect `configure_global_theme`, `configure_tmux`, and the managed shell blocks in `setup.sh`.
2. Preserve existing user palettes: create `theme.conf` only when it does not exist.
3. Keep reusable colors in `theme.conf`; do not hardcode an application-specific copy when the shared value is suitable.
4. Add thin application adapters under `~/.config/kws-box/`. Source `theme.conf` from each adapter and translate values only where the application requires another format.
5. Add the adapter to the application's managed configuration block. Do not replace unrelated user configuration.
6. Make reload behavior explicit. Shells use `kws-theme-reload`; Tmux can also use `tmux source-file ~/.tmux.conf`.
7. Update the README when adding palette keys, supported applications, or user-facing commands.

## Palette contract

Keep these variables stable:

- `KWS_THEME_BACKGROUND`
- `KWS_THEME_FOREGROUND`
- `KWS_THEME_MUTED`
- `KWS_THEME_ACCENT`
- `KWS_THEME_ACCENT_RGB` (Bash true-color representation of the accent)

When changing the default accent, update its HEX and RGB forms together. New applications should prefer the HEX values unless their format requires a conversion.

## Validation

Run:

```bash
bash -n setup.sh
git diff --check
python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" .codex/skills/manage-kws-theme
```

When a reachable test host is explicitly in scope, apply only the relevant configuration functions, reload the target application, and verify the resolved colors. Avoid rerunning the complete installer merely to test a theme change.
