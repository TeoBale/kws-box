#!/usr/bin/env bash
set -Eeuo pipefail

# Prepara una macchina di lavoro Ubuntu/Debian raggiunta via SSH.
# Installa Zsh, Oh My Zsh, Tmux, Docker e i principali tool di sviluppo/AI.
# - Nessun tema custom
# - Mouse attivo
# - Barra delle finestre cliccabile in basso
# - Prefix Ctrl+a
# - Auto-attach alla sessione "main" per le shell SSH interattive
# - Configurazione idempotente: lo script può essere rieseguito senza duplicare blocchi

SESSION_NAME="${TMUX_SESSION_NAME:-main}"

BASHRC="${HOME}/.bashrc"
ZSHRC="${HOME}/.zshrc"
TMUX_CONF="${HOME}/.tmux.conf"
THEME_DIR="${HOME}/.config/kws-box"
THEME_CONF="${THEME_DIR}/theme.conf"
SHELL_THEME="${THEME_DIR}/shell-theme.sh"
TMUX_THEME="${THEME_DIR}/apply-tmux-theme.sh"

PATH_START="# >>> kws-box-path managed block >>>"
PATH_END="# <<< kws-box-path managed block <<<"

SHELL_THEME_START="# >>> kws-box-shell-theme managed block >>>"
SHELL_THEME_END="# <<< kws-box-shell-theme managed block <<<"

ZSH_PLUGINS_START="# >>> kws-box-zsh-plugins managed block >>>"
ZSH_PLUGINS_END="# <<< kws-box-zsh-plugins managed block <<<"

ZSH_UTILITIES_START="# >>> kws-box-zsh-utilities managed block >>>"
ZSH_UTILITIES_END="# <<< kws-box-zsh-utilities managed block <<<"

BASH_START="# >>> tmux-autoattach managed block >>>"
BASH_END="# <<< tmux-autoattach managed block <<<"

TMUX_START="# >>> tmux-usability managed block >>>"
TMUX_END="# <<< tmux-usability managed block <<<"

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

ok() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[ATTENZIONE]\033[0m %s\n' "$*"
}

die() {
    printf '\033[1;31m[ERRORE]\033[0m %s\n' "$*" >&2
    exit 1
}

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        command -v sudo >/dev/null 2>&1 || \
            die "sudo non è disponibile: impossibile eseguire $*."
        sudo "$@"
    fi
}

ensure_prerequisites() {
    local missing=()
    local command_name

    command -v apt-get >/dev/null 2>&1 || \
        die "Questo script richiede apt-get (Ubuntu/Debian)."

    for command_name in curl git tar unzip; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done

    if ((${#missing[@]} == 0)); then
        return 0
    fi

    info "Installo i prerequisiti: ${missing[*]}..."
    run_as_root apt-get update
    run_as_root apt-get install -y ca-certificates "${missing[@]}"
}

install_zsh() {
    if command -v zsh >/dev/null 2>&1; then
        ok "Zsh è già installato: $(zsh --version)"
        return 0
    fi

    info "Installo Zsh..."
    run_as_root apt-get update
    run_as_root apt-get install -y zsh
    ok "Zsh installato: $(zsh --version)"
}

configure_default_shell() {
    local login_user
    local current_shell
    local zsh_path

    login_user="${SUDO_USER:-$(id -un)}"
    zsh_path="$(command -v zsh)"
    current_shell="$(getent passwd "$login_user" | awk -F: '{ print $7 }')"

    if [[ "$current_shell" == "$zsh_path" ]]; then
        ok "Zsh è già la shell predefinita di ${login_user}."
        return 0
    fi

    command -v chsh >/dev/null 2>&1 || \
        die "Il comando chsh non è disponibile: impossibile impostare Zsh come shell predefinita."

    info "Imposto Zsh come shell predefinita di ${login_user}..."
    run_as_root chsh -s "$zsh_path" "$login_user"

    current_shell="$(getent passwd "$login_user" | awk -F: '{ print $7 }')"
    [[ "$current_shell" == "$zsh_path" ]] || \
        die "Zsh è installato, ma non è stato impostato come shell predefinita di ${login_user}."
    ok "Zsh impostato come shell predefinita di ${login_user}."
}

install_oh_my_zsh() {
    local install_dir="${ZSH:-${HOME}/.oh-my-zsh}"

    if [[ -d "${install_dir}/.git" ]]; then
        ok "Oh My Zsh è già installato: $install_dir"
        return 0
    fi

    info "Installo Oh My Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes ZSH="$install_dir" \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    [[ -d "${install_dir}/.git" ]] || die "Installazione di Oh My Zsh non riuscita."
    ok "Oh My Zsh installato: $install_dir"
}

refresh_user_path() {
    export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${HOME}/.opencode/bin:${HOME}/.vite-plus/bin:${PATH}"
    hash -r
}

install_with_script() {
    local command_name="$1"
    local display_name="$2"
    local url="$3"
    shift 3

    refresh_user_path
    if command -v "$command_name" >/dev/null 2>&1; then
        ok "$display_name è già installato: $(command -v "$command_name")"
        return 0
    fi

    info "Installo $display_name..."
    curl -fsSL "$url" | env "$@" bash
    refresh_user_path
    command -v "$command_name" >/dev/null 2>&1 || \
        die "$display_name risulta installato, ma il comando '$command_name' non è nel PATH."
    ok "$display_name installato: $(command -v "$command_name")"
}

backup_file() {
    local file="$1"

    [[ -e "$file" ]] || return 0

    local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$file" "$backup"
    ok "Backup creato: $backup"
}

replace_managed_block() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local block_file="$4"
    local tmp_file

    touch "$file"
    tmp_file="$(mktemp)"

    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { skipping = 1; next }
        $0 == end   { skipping = 0; next }
        !skipping   { print }
    ' "$file" > "$tmp_file"

    # Rimuove righe vuote finali, poi aggiunge una sola copia del blocco gestito.
    awk '
        { lines[NR] = $0 }
        END {
            last = NR
            while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
                last--
            }
            for (i = 1; i <= last; i++) {
                print lines[i]
            }
        }
    ' "$tmp_file" > "${tmp_file}.trimmed"

    {
        cat "${tmp_file}.trimmed"
        [[ -s "${tmp_file}.trimmed" ]] && printf '\n'
        cat "$block_file"
        printf '\n'
    } > "$file"

    rm -f -- "$tmp_file" "${tmp_file}.trimmed"
}

insert_managed_block_before() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local before_pattern="$4"
    local block_file="$5"
    local tmp_file

    touch "$file"
    tmp_file="$(mktemp)"

    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { skipping = 1; next }
        $0 == end   { skipping = 0; next }
        !skipping   { print }
    ' "$file" > "$tmp_file"

    awk -v pattern="$before_pattern" -v block_file="$block_file" '
        !inserted && $0 ~ pattern {
            while ((getline line < block_file) > 0) print line
            close(block_file)
            print ""
            inserted = 1
        }
        { print }
        END {
            if (!inserted) {
                print ""
                while ((getline line < block_file) > 0) print line
                close(block_file)
            }
        }
    ' "$tmp_file" > "$file"

    rm -f -- "$tmp_file"
}

install_zsh_plugins() {
    local install_dir="${ZSH:-${HOME}/.oh-my-zsh}"
    local custom_dir="${ZSH_CUSTOM:-${install_dir}/custom}"
    local plugin_name
    local plugin_url

    mkdir -p "${custom_dir}/plugins"

    while IFS='|' read -r plugin_name plugin_url; do
        if [[ -d "${custom_dir}/plugins/${plugin_name}/.git" ]]; then
            ok "Plugin Zsh già installato: ${plugin_name}"
            continue
        fi

        info "Installo il plugin Zsh ${plugin_name}..."
        git clone --depth 1 "$plugin_url" "${custom_dir}/plugins/${plugin_name}"
        ok "Plugin Zsh installato: ${plugin_name}"
    done <<'EOF'
zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git
zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git
EOF
}

linux_target_triple() {
    case "$(uname -m)" in
        x86_64|amd64) printf '%s\n' 'x86_64-unknown-linux-gnu' ;;
        aarch64|arm64) printf '%s\n' 'aarch64-unknown-linux-gnu' ;;
        *) die "Architettura non supportata per eza e Yazi: $(uname -m)." ;;
    esac
}

install_eza() {
    local target
    local temp_dir

    refresh_user_path
    if command -v eza >/dev/null 2>&1; then
        ok "eza è già installato: $(eza --version | head -n 1)"
        return 0
    fi

    target="$(linux_target_triple)"
    temp_dir="$(mktemp -d)"
    info "Installo eza per ${target}..."

    curl -fsSL \
        "https://github.com/eza-community/eza/releases/latest/download/eza_${target}.tar.gz" \
        | tar -xz -C "$temp_dir"
    [[ -f "${temp_dir}/eza" ]] || die "Il pacchetto di eza non contiene il binario atteso."

    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "${temp_dir}/eza" "${HOME}/.local/bin/eza"
    rm -rf -- "$temp_dir"
    refresh_user_path
    ok "eza installato: $(eza --version | head -n 1)"
}

install_yazi() {
    local target
    local temp_dir
    local archive
    local binary
    local source_path

    refresh_user_path
    if command -v yazi >/dev/null 2>&1; then
        ok "Yazi è già installato: $(yazi --version)"
        return 0
    fi

    target="$(linux_target_triple)"
    temp_dir="$(mktemp -d)"
    archive="${temp_dir}/yazi.zip"
    info "Installo Yazi per ${target}..."

    curl -fsSL \
        "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${target}.zip" \
        -o "$archive"
    unzip -q "$archive" -d "$temp_dir"

    mkdir -p "${HOME}/.local/bin"
    for binary in yazi ya; do
        source_path="$(find "$temp_dir" -type f -name "$binary" -print -quit)"
        [[ -n "$source_path" ]] || die "Il pacchetto di Yazi non contiene il binario '${binary}'."
        install -m 0755 "$source_path" "${HOME}/.local/bin/${binary}"
    done

    rm -rf -- "$temp_dir"
    refresh_user_path
    ok "Yazi installato: $(yazi --version)"
}

configure_zsh() {
    local plugins_block
    local utilities_block

    plugins_block="$(mktemp)"
    utilities_block="$(mktemp)"

    cat > "$plugins_block" <<'EOF'
# >>> kws-box-zsh-plugins managed block >>>
# Mantiene eventuali plugin già configurati e aggiunge quelli di kws-box.
plugins=(${plugins[@]} git zsh-autosuggestions zsh-syntax-highlighting)
plugins=(${(u)plugins})
# <<< kws-box-zsh-plugins managed block <<<
EOF

    cat > "$utilities_block" <<'EOF'
# >>> kws-box-zsh-utilities managed block >>>
alias ls="eza --long --color=always --icons=always --no-user"

# Avvia Yazi e, alla chiusura, porta la shell nella directory corrente di Yazi.
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [[ "$cwd" != "$PWD" && -d "$cwd" ]] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}
# <<< kws-box-zsh-utilities managed block <<<
EOF

    insert_managed_block_before \
        "$ZSHRC" "$ZSH_PLUGINS_START" "$ZSH_PLUGINS_END" \
        '^[[:space:]]*(source|\.)[[:space:]]+.*oh-my-zsh\.sh' "$plugins_block"
    replace_managed_block \
        "$ZSHRC" "$ZSH_UTILITIES_START" "$ZSH_UTILITIES_END" "$utilities_block"

    rm -f -- "$plugins_block" "$utilities_block"
    ok "Plugin e utility Zsh configurati in: $ZSHRC"
}

install_tmux() {
    if command -v tmux >/dev/null 2>&1; then
        ok "Tmux è già installato: $(tmux -V)"
        return 0
    fi

    info "Installo Tmux..."

    run_as_root apt-get update
    run_as_root apt-get install -y tmux

    ok "Tmux installato: $(tmux -V)"
}

install_uv() {
    install_with_script uv "uv" "https://astral.sh/uv/install.sh" UV_NO_MODIFY_PATH=1
}

install_bun() {
    install_with_script bun "Bun" "https://bun.sh/install"
}

install_vite_plus() {
    install_with_script vp "Vite+" "https://vite.plus" VP_NODE_MANAGER=yes

    info "Configuro Vite+ come gestore delle versioni Node.js..."
    vp env setup --refresh
    vp env on
    ok "Vite+ gestirà Node.js e il package manager per ogni progetto."
}

install_docker() {
    local installer
    local login_user

    if command -v docker >/dev/null 2>&1; then
        ok "Docker è già installato: $(docker --version)"
    else
        info "Installo Docker Engine..."
        installer="$(mktemp)"
        curl -fsSL https://get.docker.com -o "$installer"
        run_as_root sh "$installer"
        rm -f -- "$installer"
        command -v docker >/dev/null 2>&1 || die "Installazione di Docker non riuscita."
        ok "Docker installato: $(docker --version)"
    fi

    # Consente all'utente corrente di usare Docker dalla prossima sessione.
    login_user="$(id -un)"
    if [[ "$(id -u)" -ne 0 ]] && ! id -nG "$login_user" | tr ' ' '\n' | grep -qx docker; then
        run_as_root usermod -aG docker "$login_user"
        warn "Utente aggiunto al gruppo docker; la modifica sarà attiva al prossimo login."
    fi
}

install_ai_clis() {
    install_with_script agy "Agy CLI" "https://antigravity.google/cli/install.sh"
    install_with_script codex "Codex CLI" "https://chatgpt.com/codex/install.sh" CODEX_NON_INTERACTIVE=1
    install_with_script opencode "OpenCode" "https://opencode.ai/install"
    install_with_script pi "Pi" "https://pi.dev/install.sh"
}

configure_global_theme() {
    local block

    mkdir -p "$THEME_DIR"
    if [[ ! -e "$THEME_CONF" ]]; then
        cat > "$THEME_CONF" <<'EOF'
# Palette globale kws-box. I valori HEX sono riutilizzabili da altri applicativi.
KWS_THEME_BACKGROUND="#151515"
KWS_THEME_FOREGROUND="#d8d8d8"
KWS_THEME_MUTED="#686868"
KWS_THEME_ACCENT="#f2ad66"

# Equivalente RGB dell'accento, usato dal prompt Bash.
KWS_THEME_ACCENT_RGB="242;173;102"
EOF
        ok "Palette globale creata: $THEME_CONF"
    else
        ok "Palette globale già presente: $THEME_CONF"
    fi

    cat > "$SHELL_THEME" <<'EOF'
# Caricato dai file rc di Bash e Zsh.
[[ -r "$HOME/.config/kws-box/theme.conf" ]] || return 0
. "$HOME/.config/kws-box/theme.conf"

if [[ -n "${ZSH_VERSION:-}" ]]; then
    PROMPT="%F{${KWS_THEME_ACCENT}}%n@%m%f:%F{${KWS_THEME_FOREGROUND}}%~%f%F{${KWS_THEME_ACCENT}}%#%f "
elif [[ -n "${BASH_VERSION:-}" ]]; then
    PS1="\[\e[38;2;${KWS_THEME_ACCENT_RGB}m\]\u@\h\[\e[0m\]:\[\e[38;2;${KWS_THEME_ACCENT_RGB}m\]\w\[\e[0m\]\$ "
fi

kws-theme-reload() {
    . "$HOME/.config/kws-box/shell-theme.sh"
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
        "$HOME/.config/kws-box/apply-tmux-theme.sh"
    fi
}
EOF

    cat > "$TMUX_THEME" <<'EOF'
#!/usr/bin/env bash
set -eu
. "$HOME/.config/kws-box/theme.conf"

tmux set -g status-style "bg=${KWS_THEME_BACKGROUND},fg=${KWS_THEME_MUTED}"
tmux set -g status-left-length 40
tmux set -g status-left "#[bg=${KWS_THEME_ACCENT},fg=${KWS_THEME_BACKGROUND},bold] #H #[bg=${KWS_THEME_BACKGROUND},fg=${KWS_THEME_ACCENT},bold] #S "
tmux set -g status-right-length 60
tmux set -g status-right "#[bg=${KWS_THEME_ACCENT},fg=${KWS_THEME_BACKGROUND},bold] CPU #(LC_ALL=C top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%.0f%%\", 100-\$8}') · MEM #(free | awk '/Mem:/ {printf \"%.0f%%\", \$3/\$2*100}') "
tmux set-window-option -g window-status-separator " "
tmux set-window-option -g window-status-format "#[fg=${KWS_THEME_MUTED}]#I:#W"
tmux set-window-option -g window-status-current-format "#[fg=${KWS_THEME_ACCENT},bold]#I:#W"
EOF
    chmod 0755 "$TMUX_THEME"

    block="$(mktemp)"
    cat > "$block" <<'EOF'
# >>> kws-box-shell-theme managed block >>>
[[ -r "$HOME/.config/kws-box/shell-theme.sh" ]] && . "$HOME/.config/kws-box/shell-theme.sh"
# <<< kws-box-shell-theme managed block <<<
EOF
    replace_managed_block "$BASHRC" "$SHELL_THEME_START" "$SHELL_THEME_END" "$block"
    replace_managed_block "$ZSHRC" "$SHELL_THEME_START" "$SHELL_THEME_END" "$block"
    rm -f -- "$block"

    ok "Tema shell configurato in Bash e Zsh."
}

configure_user_path() {
    local block
    block="$(mktemp)"

    cat > "$block" <<'EOF'
# >>> kws-box-path managed block >>>
# Binari installati localmente da uv, Bun, Vite+ e dai CLI di coding.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.opencode/bin:$HOME/.vite-plus/bin:$PATH"
# <<< kws-box-path managed block <<<
EOF

    replace_managed_block "$BASHRC" "$PATH_START" "$PATH_END" "$block"
    replace_managed_block "$ZSHRC" "$PATH_START" "$PATH_END" "$block"
    rm -f -- "$block"
    ok "PATH degli strumenti configurato in: $BASHRC e $ZSHRC"
}

configure_tmux() {
    local block
    block="$(mktemp)"

    cat > "$block" <<'EOF'
# >>> tmux-usability managed block >>>

##### GENERALE #################################################

# Mouse: selezione finestre/pannelli, resize e scroll
set -g mouse on

# Migliore supporto ai colori
set -g default-terminal "tmux-256color"

# Riconosce combinazioni di tasti modificate, incluso Enter con modificatori
set -g extended-keys on

# Riduce il ritardo dopo il prefix
set -sg escape-time 10

# Cronologia lunga
set -g history-limit 100000

# Barra delle finestre in basso
set -g status-position bottom
set -g status-interval 5

# Tutti i colori arrivano dalla palette globale ~/.config/kws-box/theme.conf
run-shell "$HOME/.config/kws-box/apply-tmux-theme.sh"

##### NUMERAZIONE ###############################################

# Finestre da 1 invece che da 0
set -g base-index 1

# Anche i pannelli partono da 1
setw -g pane-base-index 1

# Riordina i numeri dopo la chiusura di una finestra
set -g renumber-windows on

##### PREFIX PIÙ COMODO #########################################

# Ctrl+a al posto del classico Ctrl+b
unbind C-b
set -g prefix C-a
bind C-a send-prefix

##### NUOVE FINESTRE ############################################

# Nuova finestra mantenendo la directory corrente
bind c new-window -c "#{pane_current_path}"

##### DIVISIONE DELLO SCHERMO ###################################

# Ctrl+a poi |
bind | split-window -h -c "#{pane_current_path}"

# Ctrl+a poi -
bind - split-window -v -c "#{pane_current_path}"

##### NAVIGAZIONE TRA PANNELLI ##################################

# Ctrl+a poi h/j/k/l
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

##### RIDIMENSIONAMENTO #########################################

# Ctrl+a poi Shift+h/j/k/l
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

##### RICARICA CONFIGURAZIONE ###################################

# Ctrl+a poi r
bind r source-file ~/.tmux.conf \; display-message "Configurazione Tmux ricaricata"

# <<< tmux-usability managed block <<<
EOF

    backup_file "$TMUX_CONF"
    replace_managed_block "$TMUX_CONF" "$TMUX_START" "$TMUX_END" "$block"
    rm -f -- "$block"

    ok "Configurazione Tmux aggiornata: $TMUX_CONF"
}

configure_ssh_autoattach() {
    local block
    block="$(mktemp)"

    cat > "$block" <<EOF
# >>> tmux-autoattach managed block >>>
# Alcuni client (per esempio Ghostty) possono inviare un TERM non presente
# nel database terminfo del server. Usa un fallback compatibile per tutti i
# comandi della sessione SSH, incluso un avvio manuale di Tmux.
if [[ \$- == *i* && -n "\${SSH_TTY:-}" ]] && \
        ! infocmp "\${TERM:-}" >/dev/null 2>&1; then
    export TERM=xterm-256color
fi

# Entra automaticamente nella sessione Tmux "${SESSION_NAME}"
# solo per shell SSH interattive e solo se non siamo già dentro Tmux.
# Per saltare temporaneamente l'auto-attach:
#   TMUX_DISABLE_AUTOATTACH=1 ssh utente@host
if [[ \$- == *i* \
      && -n "\${SSH_TTY:-}" \
      && -z "\${TMUX:-}" \
      && "\${TMUX_DISABLE_AUTOATTACH:-0}" != "1" ]]; then
    exec tmux new-session -A -s "${SESSION_NAME}"
fi
# <<< tmux-autoattach managed block <<<
EOF

    backup_file "$BASHRC"
    backup_file "$ZSHRC"
    replace_managed_block "$BASHRC" "$BASH_START" "$BASH_END" "$block"
    replace_managed_block "$ZSHRC" "$BASH_START" "$BASH_END" "$block"
    rm -f -- "$block"

    ok "Auto-attach SSH configurato in: $BASHRC e $ZSHRC"
}

reload_tmux_if_running() {
    if tmux list-sessions >/dev/null 2>&1; then
        if tmux source-file "$TMUX_CONF"; then
            ok "Configurazione ricaricata nelle sessioni Tmux attive."
        else
            warn "Tmux è attivo, ma non sono riuscito a ricaricare automaticamente la configurazione."
        fi
    fi
}

print_summary() {
    cat <<EOF

============================================================
Configurazione completata
============================================================

Sessione SSH automatica : ${SESSION_NAME}
File Tmux               : ${TMUX_CONF}
Auto-attach SSH         : ${BASHRC}
Palette globale         : ${THEME_CONF}

Strumenti installati/verificati:
  zsh, oh-my-zsh, eza, yazi, tmux, uv, bun, vite+, docker, agy, codex, opencode, pi

Scorciatoie principali:
  Ctrl+a, c      Nuova finestra
  clic in basso  Seleziona una finestra
  Ctrl+a, n/p    Finestra successiva/precedente
  Ctrl+a, 1..9   Vai a una finestra
  Ctrl+a, |      Split verticale
  Ctrl+a, -      Split orizzontale
  Ctrl+a, h/j/k/l Cambia pannello
  Ctrl+a, z      Zoom pannello
  Ctrl+a, d      Disconnetti da Tmux senza chiuderlo
  Ctrl+a, r      Ricarica ~/.tmux.conf

Per provare subito:
  1. Chiudi la connessione SSH corrente.
  2. Ricollegati normalmente.
  3. Verrai collegato automaticamente alla sessione "${SESSION_NAME}".

Per saltare l'auto-attach una sola volta:
  TMUX_DISABLE_AUTOATTACH=1 ssh utente@host

============================================================
EOF
}

main() {
    info "Avvio configurazione automatica della macchina."
    ensure_prerequisites
    install_zsh
    configure_default_shell
    install_oh_my_zsh
    install_zsh_plugins
    install_eza
    install_yazi
    install_tmux
    install_uv
    install_bun
    install_vite_plus
    install_docker
    install_ai_clis
    configure_zsh
    configure_global_theme
    configure_user_path
    configure_tmux
    configure_ssh_autoattach
    reload_tmux_if_running
    print_summary
}

main "$@"
