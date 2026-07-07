---
name: change-kws-colors
description: Change, inspect, and reload the color palette on a Linux machine already configured by KWS Box. Use when updating the installed ~/.config/kws-box/theme.conf colors, applying a named or custom palette after setup, previewing current theme values, or refreshing the active Tmux theme without changing setup.sh defaults.
---

# Change KWS Box colors

Modify the installed machine, not the defaults in the repository. Use the bundled `scripts/change-colors.sh` so validation, backups, HEX-to-RGB conversion, and Tmux reload remain consistent.

## Workflow

1. Confirm that `~/.config/kws-box/theme.conf` exists. If it does not, stop and explain that KWS Box setup has not created the theme contract on this machine.
2. Inspect the current palette:

   ```bash
   bash scripts/change-colors.sh --show
   ```

3. Resolve the requested palette to six-digit HEX colors. Preserve unspecified values. Maintain readable contrast between background and foreground; use muted for secondary text and accent for prompt/Tmux emphasis.
4. Show the proposed HEX values before applying them when the user gave a subjective request such as “warmer”, “Nord-like”, or “less contrast”. Apply directly when the user supplied exact values.
5. Run the script with only the values being changed:

   ```bash
   bash scripts/change-colors.sh \
     --background '#151515' \
     --foreground '#d8d8d8' \
     --muted '#686868' \
     --accent '#f2ad66'
   ```

6. Report the backup path printed by the script and the final palette. Existing Tmux sessions are reloaded automatically. Explain that existing shell prompts need `kws-theme-reload` in the interactive shell, or a new shell.

## Guardrails

- Do not edit `setup.sh`; that changes future installation defaults and belongs to `manage-kws-theme`.
- Do not source `theme.conf` merely to parse it. Treat it as data and use the bundled script.
- Do not modify unrelated keys or comments in `theme.conf`.
- Never update `KWS_THEME_ACCENT` without synchronizing `KWS_THEME_ACCENT_RGB`; the script performs this conversion.
- Do not rerun the complete installer for a color-only change.

## Script options

- `--show`: print the current palette without modifying it.
- `--background HEX`, `--foreground HEX`, `--muted HEX`, `--accent HEX`: change selected colors.
- `--theme-file PATH`: operate on a non-default theme file, primarily for testing.
- `--no-reload`: skip reloading an active Tmux server.
- `--help`: print usage.
