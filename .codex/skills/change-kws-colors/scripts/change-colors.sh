#!/usr/bin/env bash
set -Eeuo pipefail

theme_file="${HOME}/.config/kws-box/theme.conf"
reload_tmux=1
show_only=0
background=""
foreground=""
muted=""
accent=""

usage() {
    cat <<'EOF'
Usage: change-colors.sh [options]

Options:
  --show                 Show the current palette without changing it
  --background HEX       Set the background color
  --foreground HEX       Set the foreground color
  --muted HEX            Set the muted color
  --accent HEX           Set the accent color and derive its RGB value
  --theme-file PATH      Use a theme file other than ~/.config/kws-box/theme.conf
  --no-reload            Do not reload active Tmux sessions
  --help                 Show this help
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

normalize_hex() {
    local value="$1"
    value="${value#\#}"
    [[ "$value" =~ ^[[:xdigit:]]{6}$ ]] || die "Invalid HEX color: $1"
    printf '#%s\n' "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
}

read_value() {
    local key="$1"
    awk -F= -v key="$key" '
        $1 == key {
            value = substr($0, index($0, "=") + 1)
            gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "$theme_file"
}

show_palette() {
    local key
    for key in \
        KWS_THEME_BACKGROUND \
        KWS_THEME_FOREGROUND \
        KWS_THEME_MUTED \
        KWS_THEME_ACCENT \
        KWS_THEME_ACCENT_RGB; do
        printf '%s=%s\n' "$key" "$(read_value "$key")"
    done
}

while (($# > 0)); do
    case "$1" in
        --show) show_only=1; shift ;;
        --background|--foreground|--muted|--accent|--theme-file)
            (($# >= 2)) || die "$1 requires a value."
            case "$1" in
                --background) background="$2" ;;
                --foreground) foreground="$2" ;;
                --muted) muted="$2" ;;
                --accent) accent="$2" ;;
                --theme-file) theme_file="$2" ;;
            esac
            shift 2
            ;;
        --no-reload) reload_tmux=0; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ -f "$theme_file" ]] || die "Theme file not found: $theme_file. Run KWS Box setup first."

if ((show_only)); then
    [[ -z "$background$foreground$muted$accent" ]] || \
        die "--show cannot be combined with color changes."
    show_palette
    exit 0
fi

[[ -n "$background$foreground$muted$accent" ]] || die "Specify at least one color or use --show."

[[ -z "$background" ]] || background="$(normalize_hex "$background")"
[[ -z "$foreground" ]] || foreground="$(normalize_hex "$foreground")"
[[ -z "$muted" ]] || muted="$(normalize_hex "$muted")"
[[ -z "$accent" ]] || accent="$(normalize_hex "$accent")"

accent_rgb=""
if [[ -n "$accent" ]]; then
    accent_rgb="$((16#${accent:1:2}));$((16#${accent:3:2}));$((16#${accent:5:2}))"
fi

backup="${theme_file}.backup.$(date +%Y%m%d-%H%M%S).$$"
temp_file="$(mktemp "${theme_file}.tmp.XXXXXX")"
trap 'rm -f -- "$temp_file"' EXIT
cp -a -- "$theme_file" "$backup"

awk \
    -v background="$background" \
    -v foreground="$foreground" \
    -v muted="$muted" \
    -v accent="$accent" \
    -v accent_rgb="$accent_rgb" '
    /^KWS_THEME_BACKGROUND=/ && background != "" {
        print "KWS_THEME_BACKGROUND=\"" background "\""; next
    }
    /^KWS_THEME_FOREGROUND=/ && foreground != "" {
        print "KWS_THEME_FOREGROUND=\"" foreground "\""; next
    }
    /^KWS_THEME_MUTED=/ && muted != "" {
        print "KWS_THEME_MUTED=\"" muted "\""; next
    }
    /^KWS_THEME_ACCENT=/ && accent != "" {
        print "KWS_THEME_ACCENT=\"" accent "\""; next
    }
    /^KWS_THEME_ACCENT_RGB=/ && accent_rgb != "" {
        print "KWS_THEME_ACCENT_RGB=\"" accent_rgb "\""; next
    }
    { print }
' "$theme_file" > "$temp_file"

cat "$temp_file" > "$theme_file"
rm -f -- "$temp_file"
trap - EXIT

printf 'Backup: %s\n' "$backup"
printf 'Palette updated: %s\n' "$theme_file"
show_palette

tmux_theme="$(dirname "$theme_file")/apply-tmux-theme.sh"
if ((reload_tmux)) && command -v tmux >/dev/null 2>&1 && \
        tmux list-sessions >/dev/null 2>&1 && [[ -x "$tmux_theme" ]]; then
    "$tmux_theme"
    printf 'Active Tmux theme reloaded.\n'
fi

printf 'Run kws-theme-reload in each existing interactive shell, or start a new shell.\n'
