#!/usr/bin/env bash
set -Eeuo pipefail

# Prepara una macchina di lavoro Ubuntu/Debian raggiunta via SSH.
# Installa Tmux, Docker e i principali tool di sviluppo/AI.
# - Nessun tema custom
# - Mouse attivo
# - Barra delle finestre cliccabile in basso
# - Prefix Ctrl+a
# - Auto-attach alla sessione "main" per le shell SSH interattive
# - Configurazione idempotente: lo script può essere rieseguito senza duplicare blocchi

SESSION_NAME="${TMUX_SESSION_NAME:-main}"

BASHRC="${HOME}/.bashrc"
TMUX_CONF="${HOME}/.tmux.conf"

PATH_START="# >>> kws-box-path managed block >>>"
PATH_END="# <<< kws-box-path managed block <<<"

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

    for command_name in curl unzip; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done

    if ((${#missing[@]} == 0)); then
        return 0
    fi

    info "Installo i prerequisiti: ${missing[*]}..."
    run_as_root apt-get update
    run_as_root apt-get install -y ca-certificates "${missing[@]}"
}

refresh_user_path() {
    export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${HOME}/.opencode/bin:${PATH}"
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

configure_user_path() {
    local block
    block="$(mktemp)"

    cat > "$block" <<'EOF'
# >>> kws-box-path managed block >>>
# Binari installati localmente da uv, Bun e dai CLI di coding.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.opencode/bin:$PATH"
# <<< kws-box-path managed block <<<
EOF

    replace_managed_block "$BASHRC" "$PATH_START" "$PATH_END" "$block"
    rm -f -- "$block"
    ok "PATH degli strumenti configurato in: $BASHRC"
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

# Riduce il ritardo dopo il prefix
set -sg escape-time 10

# Cronologia lunga
set -g history-limit 100000

# Barra delle finestre in basso
set -g status-position bottom
set -g status-interval 5

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
    replace_managed_block "$BASHRC" "$BASH_START" "$BASH_END" "$block"
    rm -f -- "$block"

    ok "Auto-attach SSH configurato in: $BASHRC"
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
Tema custom             : NON installato

Strumenti installati/verificati:
  tmux, uv, bun, docker, agy, codex, opencode, pi

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
    install_tmux
    install_uv
    install_bun
    install_docker
    install_ai_clis
    configure_user_path
    configure_tmux
    configure_ssh_autoattach
    reload_tmux_if_running
    print_summary
}

main "$@"
