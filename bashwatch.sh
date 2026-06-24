#!/usr/bin/env bash
# =============================================================================
#  BashWatch — Integrated Linux Security & Active Response Suite
#  Author  : Saad Ali Bajwa (078) & Shahzeb Qamar (066) | BSE 4B
#  Course  : Operating Systems (Spring-2026) | Bahria University, Islamabad
#  Teacher : Engr. Aamir Sohail
# =============================================================================
#
#  PROTECTED USER  : kali  (never blocked, killed, or locked out)
#  LOG DIR         : /home/kali/bashwatch/logs/
#  FORENSIC DIR    : /home/kali/bashwatch/forensics/
#  HONEYPOT DIR    : /home/kali/bashwatch/honeypots/
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 0. CONSTANTS & CONFIG
# ─────────────────────────────────────────────────────────────────────────────

readonly PROTECTED_USER="kali"
readonly BASE_DIR="/home/kali/bashwatch"
readonly LOG_DIR="${BASE_DIR}/logs"
readonly FORENSIC_DIR="${BASE_DIR}/forensics"
readonly HONEYPOT_DIR="/opt/bashwatch_honeypots"
readonly MAIN_LOG="${LOG_DIR}/bashwatch.log"
readonly ALERT_LOG="${LOG_DIR}/alerts.log"
readonly PID_FILE="/tmp/bashwatch.pid"

# ── Module toggles ────────────────────────────────────────────────────────────
ENABLE_NETWORK_SHIELD=true       
ENABLE_SESSION_WATCHDOG=true     
ENABLE_FILE_TRAP=true             

# ── Network Shield config ────────────────────────────────────────────────────
SSH_LOG="/var/log/auth.log"       
BRUTE_THRESHOLD=5                 
BRUTE_WINDOW=120                  

# ── Session Watchdog config ──────────────────────────────────────────────────
FORBIDDEN_CMDS=("nmap" "netcat" "rm -rf /" "python -c" "perl -e")
WATCHDOG_INTERVAL=5               

# ── File Trap config ─────────────────────────────────────────────────────────
HONEYPOT_NAMES=("secret_keys" "passwd_backup" "root_creds" "private_data")
INOTIFY_EVENTS="access,open,create,delete,modify,moved_from,moved_to"

# ─────────────────────────────────────────────────────────────────────────────
# 1. UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

_init_dirs() {
    local d
    for d in "$LOG_DIR" "$FORENSIC_DIR" "$HONEYPOT_DIR"; do
        mkdir -p "$d"
        chown -R "${PROTECTED_USER}:${PROTECTED_USER}" "$d" 2>/dev/null || true
    done
}

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${ts}] [${level}] ${msg}" | tee -a "$MAIN_LOG"
}

alert() {
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${ts}] [ALERT] ${msg}" | tee -a "$ALERT_LOG" "$MAIN_LOG"
    wall "*** BASHWATCH ALERT *** ${msg}" 2>/dev/null || true
}

_rotate_logs() {
    local f
    for f in "$MAIN_LOG" "$ALERT_LOG"; do
        if [[ -f "$f" ]] && (( $(stat -c%s "$f" 2>/dev/null || echo 0) > 10485760 )); then
            mv "$f" "${f}.$(date +%Y%m%d%H%M%S).bak"
            log "INFO" "Log rotated: $f"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. FORENSIC EVIDENCE COLLECTOR
# ─────────────────────────────────────────────────────────────────────────────

collect_forensics() {
    local event_type="$1"
    local subject="$2"
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local bundle_dir="${FORENSIC_DIR}/${event_type}_${subject//\//_}_${ts}"

    mkdir -p "$bundle_dir"
    log "INFO" "Collecting forensic evidence → ${bundle_dir}"

    ps auxf > "${bundle_dir}/process_tree.txt"           2>/dev/null || true
    ss -tulpn > "${bundle_dir}/network_state.txt"        2>/dev/null || true
    netstat -tulpn >> "${bundle_dir}/network_state.txt"  2>/dev/null || true

    if id "$subject" &>/dev/null; then
        lsof -u "$subject" > "${bundle_dir}/open_files.txt" 2>/dev/null || true
    fi

    who > "${bundle_dir}/active_sessions.txt"            2>/dev/null || true
    last -n 20 >> "${bundle_dir}/active_sessions.txt"    2>/dev/null || true

    if [[ -r "$SSH_LOG" ]]; then
        tail -n 50 "$SSH_LOG" > "${bundle_dir}/auth_log_tail.txt" 2>/dev/null || true
    fi

    local tarball="${FORENSIC_DIR}/${event_type}_${subject//\//_}_${ts}.tar.gz"
    tar -czf "$tarball" -C "$FORENSIC_DIR" "$(basename "$bundle_dir")" 2>/dev/null && rm -rf "$bundle_dir" || true

    alert "Forensic bundle saved → ${tarball}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. MODULE A — NETWORK SHIELD
# ─────────────────────────────────────────────────────────────────────────────

_get_brute_ips() {
    local cutoff
    cutoff=$(date -d "-${BRUTE_WINDOW} seconds" '+%b %e %H:%M:%S' 2>/dev/null || date -v"-${BRUTE_WINDOW}S" '+%b %e %H:%M:%S' 2>/dev/null || echo "")

    if [[ -z "$cutoff" ]] || [[ ! -r "$SSH_LOG" ]]; then
        return
    fi

    grep "Failed password" "$SSH_LOG" 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | awk -v thresh="$BRUTE_THRESHOLD" '$1 >= thresh {print $2}' || true
}

_block_ip() {
    local ip="$1"
    if iptables -C INPUT -s "$ip" -j DROP &>/dev/null; then
        return
    fi
    iptables -I INPUT -s "$ip" -j DROP || true
    alert "Network Shield: BLOCKED IP ${ip}"
    collect_forensics "brute_force" "$ip"
}

module_network_shield() {
    log "INFO" "Module started: Network Shield"
    while true; do
        _rotate_logs
        while IFS= read -r ip; do
            if [[ -n "$ip" ]]; then
                _block_ip "$ip"
            fi
        done < <(_get_brute_ips) || true
        sleep 30
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. MODULE B — SESSION WATCHDOG
# ─────────────────────────────────────────────────────────────────────────────

_find_forbidden_procs() {
    local pattern="$1"
    
    ps -eo pid,user,args --no-headers 2>/dev/null | while read -r pid user args; do
        if [[ -z "$pid" ]]; then continue; fi
        if [[ "$user" == "$PROTECTED_USER" ]]; then continue; fi
        if [[ "$pid" == "$$" || "$pid" == "$BASHPID" ]]; then continue; fi
        if [[ "$args" == *"_find_forbidden_procs"* || "$args" == *"grep"* ]]; then continue; fi
        
        # Convert arguments to lowercase for case-insensitivity
        local lower_args="${args,,}"
        local lower_pattern="${pattern,,}"
        
        # FIX: Check if the pattern matches as a distinct word boundary (\b equivalent)
        # This matches if it's at the start, end, or surrounded by spaces/slashes
        if [[ " $lower_args " == *" $lower_pattern "* || " $lower_args " == *"/${lower_pattern} "* ]]; then
            echo "$pid $user"
        fi
    done || true

}
_kill_session() {
    local pid="$1"
    local user="$2"
    local cmd="$3"

    # Double check we are NEVER acting on the protected user
    local proc_user
    proc_user=$(ps -o user= -p "$pid" 2>/dev/null || echo "")
    if [[ "$proc_user" == "$PROTECTED_USER" ]]; then
        return
    fi

    alert "Session Watchdog: Forbidden command '${cmd}' detected (PID ${pid}, user ${user})"

    # Broadcast a warning notification to the offending user's active session
    if command -v write &>/dev/null && who | grep -q "^${user} "; then
        echo "*** SECURITY VIOLATION: Forbidden command '${cmd}' detected. MANDATORY LOGOUT ENFORCED. ***" | write "$user" 2>/dev/null || true
    fi

    sleep 1

    # Kill the malicious command process itself
    kill -SIGKILL "$pid" 2>/dev/null || true

    # ── ULTIMATE EVICITON LOGIC ───────────────────────────────────────────────
    # Send SIGKILL (-9) to every single process currently executing under the target user's identity.
    # This tears down their desktop session provider, shell environment, and window manager,
    # immediately dropping them back to the system's display manager login page.
    log "INFO" "Session Watchdog: Evicting user '${user}' from the operating system entirely."
    pkill -u "$user" -9 2>/dev/null || true

    collect_forensics "forbidden_cmd_hard_logout" "$user"
}

 
module_session_watchdog() {
    log "INFO" "Module started: Session Watchdog"
    while true; do
        local cmd_pattern
        for cmd_pattern in "${FORBIDDEN_CMDS[@]}"; do
            while IFS=' ' read -r pid user; do
                if [[ -n "$pid" ]]; then
                    _kill_session "$pid" "$user" "$cmd_pattern"
                fi
            done < <(_find_forbidden_procs "$cmd_pattern") || true
        done
        sleep "$WATCHDOG_INTERVAL"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. MODULE C — FILE TRAP
# ─────────────────────────────────────────────────────────────────────────────

_setup_honeypots() {
    log "INFO" "Setting up honeypot directories..."
    local name
    for name in "${HONEYPOT_NAMES[@]}"; do
        local trap_dir="${HONEYPOT_DIR}/${name}"
        mkdir -p "$trap_dir"

        echo "root:x:0:0:root:/root:/bin/bash"            > "${trap_dir}/passwd.bak"   2>/dev/null || true
        echo "-----BEGIN RSA PRIVATE KEY-----"            > "${trap_dir}/id_rsa"       2>/dev/null || true
        echo "DECOY_API_KEY=sk-fake-key-bashwatch-trap"   > "${trap_dir}/.env"         2>/dev/null || true
        echo "server_password=totally_real_password_123"  > "${trap_dir}/config.conf"  2>/dev/null || true

        chmod 755 "$trap_dir" || true
        chmod 644 "${trap_dir}/"* 2>/dev/null || true
    done
    chmod 755 "$HONEYPOT_DIR" || true
}

_handle_trap_event() {
    local watched_dir="$1"
    local event="$2"
    local filename="$3"

    if [[ "$event" == *"ISDIR"* ]]; then
        return
    fi

    local accessor="unknown"
    local accessing_pid=""
    
    if [[ -n "$filename" ]]; then
        accessing_pid=$(lsof -t "${watched_dir}/${filename}" 2>/dev/null | head -n 1) || true
    else
        accessing_pid=$(lsof -t "$watched_dir" 2>/dev/null | head -n 1) || true
    fi

    if [[ -n "$accessing_pid" ]]; then
        accessor=$(ps -o user= -p "$accessing_pid" 2>/dev/null | tr -d ' ') || true
        if [[ -z "$accessor" ]]; then accessor="unknown"; fi
    fi

    if [[ "$accessor" == "$PROTECTED_USER" ]]; then
        return
    fi

    alert "File Trap TRIGGERED: ${event} on '${watched_dir}/${filename}' by user '${accessor}'"
    collect_forensics "honeypot_access" "${accessor}"

    if [[ "$accessor" != "unknown" ]] && id "$accessor" &>/dev/null; then
        passwd -l "$accessor" 2>/dev/null || true
    fi
}

module_file_trap() {
    log "INFO" "Module started: File Trap"
    if ! command -v inotifywait &>/dev/null; then
        log "ERROR" "inotifywait missing."
        exit 1
    fi

    _setup_honeypots

    inotifywait -m -r --format '%w %e %f' --event "$INOTIFY_EVENTS" "$HONEYPOT_DIR" 2>/dev/null | while IFS=' ' read -r dir event file; do
        _handle_trap_event "$dir" "$event" "$file"
    done || true
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. STARTUP / SHUTDOWN LOGIC
# ─────────────────────────────────────────────────────────────────────────────

_check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Run as root."
        exit 1
    fi
}

_check_dependencies() {
    command -v inotifywait &>/dev/null || true
    command -v iptables    &>/dev/null || true
    command -v lsof        &>/dev/null || true
    command -v pstree      &>/dev/null || true
}

_graceful_shutdown() {
    jobs -p | xargs -r kill 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 0
}

trap '_graceful_shutdown' SIGTERM SIGINT SIGQUIT

_start() {
    _check_root
    _init_dirs
    _check_dependencies

    echo $$ > "$PID_FILE"

    if [[ "$ENABLE_NETWORK_SHIELD" == true ]]; then module_network_shield & fi
    if [[ "$ENABLE_SESSION_WATCHDOG" == true ]]; then module_session_watchdog & fi
    if [[ "$ENABLE_FILE_TRAP" == true ]]; then module_file_trap & fi

    while true; do
        _rotate_logs
        sleep 60
    done
}

_start
