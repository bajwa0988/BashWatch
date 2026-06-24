#!/usr/bin/env bash

# =============================================================================
#  BashWatch — Complete Installation Script
#  Installs: Python environment, Web UI, Daemon script, and systemd service
#  Run as root: sudo bash install.sh
# =============================================================================

set -euo pipefail

# ─── Color Codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Functions ─────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[✓]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[⚠]${NC}      $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; exit 1; }
header()  { echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"; }

# ─── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/home/kali/bashwatch"
VENV_DIR="${INSTALL_DIR}/venv"
SERVICE_FILE="/etc/systemd/system/bashwatch.service"
HONEYPOT_DIR="/opt/bashwatch_honeypots"

# ─── Validate root ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "Run this installer as root: sudo bash install.sh"

header "BashWatch — Complete Installation Suite"
echo -e "${CYAN}Bahria University | BSE 4B | Spring-2026${NC}"
echo -e "${CYAN}Integrated Linux Security & Active Response${NC}\n"

# ─── Step 1: Install system dependencies ──────────────────────────────────────
header "Step 1: Installing System Dependencies"
info "Updating package lists..."
apt-get update -qq 2>/dev/null || warn "apt-get update failed"

info "Installing required packages..."
PACKAGES=(
    "python3"
    "python3-venv"
    "python3-pip"
    "inotify-tools"
    "lsof"
    "psmisc"
    "net-tools"
    "procps"
    "curl"
    "wget"
)

for pkg in "${PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii.*$pkg"; then
        success "$pkg is already installed"
    else
        apt-get install -y "$pkg" 2>/dev/null && success "$pkg installed" || warn "Failed to install $pkg"
    fi
done

# ─── Step 2: Create directory structure ────────────────────────────────────────
header "Step 2: Creating Directory Structure"
info "Creating bashwatch directories..."

mkdir -p "${INSTALL_DIR}"/{logs,forensics,templates}
mkdir -p "${HONEYPOT_DIR}"/{passwd_backup,private_data,root_creds,secret_keys}

success "Directories created at ${INSTALL_DIR}"
success "Honeypot directories created at ${HONEYPOT_DIR}"

# ─── Step 3: Copy files from installation source ───────────────────────────────
header "Step 3: Copying BashWatch Files"

info "Copying main daemon script..."
if [[ -f "$SCRIPT_DIR/bashwatch.sh" ]]; then
    cp "$SCRIPT_DIR/bashwatch.sh" "${INSTALL_DIR}/bashwatch.sh"
    chmod 750 "${INSTALL_DIR}/bashwatch.sh"
    success "bashwatch.sh copied"
else
    error "bashwatch.sh not found in $SCRIPT_DIR"
fi

# ─── Step 4: Set up Python virtual environment ─────────────────────────────────
header "Step 4: Setting Up Python Virtual Environment"

if [[ -d "$VENV_DIR" ]]; then
    warn "Virtual environment already exists, skipping..."
else
    info "Creating Python 3 virtual environment..."
    python3 -m venv "$VENV_DIR"
    success "Virtual environment created at $VENV_DIR"
fi

# ─── Step 5: Install Python dependencies ──────────────────────────────────────
header "Step 5: Installing Python Dependencies"

info "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

info "Upgrading pip, setuptools, and wheel..."
pip install --quiet --upgrade pip setuptools wheel 2>/dev/null && success "Pip upgraded" || warn "Pip upgrade had issues"

info "Installing Flask and Werkzeug..."
pip install --quiet flask==2.3.2 werkzeug==2.3.6 2>/dev/null && success "Python packages installed" || error "Failed to install Python packages"

deactivate
success "Python environment ready"

# ─── Step 6: Copy/Create web application files ─────────────────────────────────
header "Step 6: Setting Up Web Application"

# Create main Flask app
cat > "${INSTALL_DIR}/app.py" << 'FLASK_APP_EOF'
import subprocess
import re
from flask import Flask, render_template, jsonify, request
import os

app = Flask(__name__)

SCRIPT_PATH = "/home/kali/bashwatch/bashwatch.sh"
LOG_PATH = "/home/kali/bashwatch/logs/bashwatch.log"

def get_service_status():
    try:
        res = subprocess.run(["systemctl", "is-active", "bashwatch"], capture_output=True, text=True)
        return res.stdout.strip()
    except Exception:
        return "unknown"

def get_module_states():
    states = {"network_shield": False, "session_watchdog": False, "file_trap": False}
    try:
        with open(SCRIPT_PATH, "r") as f:
            content = f.read()
            states["network_shield"] = "ENABLE_NETWORK_SHIELD=true" in content
            states["session_watchdog"] = "ENABLE_SESSION_WATCHDOG=true" in content
            states["file_trap"] = "ENABLE_FILE_TRAP=true" in content
    except Exception as e:
        print(f"Error reading script config: {e}")
    return states

def toggle_module_in_script(module_var, enable):
    try:
        with open(SCRIPT_PATH, "r") as f:
            content = f.read()
        
        old_line = f"{module_var}={'true' if not enable else 'false'}"
        new_line = f"{module_var}={'true' if enable else 'false'}"
        
        if old_line not in content and f"{module_var} = {'true' if not enable else 'false'}" in content:
            old_line = f"{module_var} = {'true' if not enable else 'false'}"
            new_line = f"{module_var} = {'true' if enable else 'false'}"

        updated_content = content.replace(old_line, new_line)
        
        with open(SCRIPT_PATH, "w") as f:
            f.write(updated_content)
        return True
    except Exception as e:
        print(f"Error updating configuration: {e}")
        return False

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status", methods=["GET"])
def api_status():
    return jsonify({
        "service": get_service_status(),
        "modules": get_module_states()
    })

@app.route("/api/service/<action>", methods=["POST"])
def api_service_control(action):
    if action in ["start", "stop", "restart"]:
        subprocess.run(["sudo", "systemctl", action, "bashwatch"])
        return jsonify({"status": "success", "service": get_service_status()})
    return jsonify({"status": "error", "message": "Invalid action"}), 400

@app.route("/api/module/<name>", methods=["POST"])
def api_module_control(name):
    data = request.json
    enable = data.get("enable", False)
    
    mapping = {
        "network_shield": "ENABLE_NETWORK_SHIELD",
        "session_watchdog": "ENABLE_SESSION_WATCHDOG",
        "file_trap": "ENABLE_FILE_TRAP"
    }
    
    if name in mapping:
        if toggle_module_in_script(mapping[name], enable):
            subprocess.run(["sudo", "systemctl", "restart", "bashwatch"])
            return jsonify({"status": "success", "modules": get_module_states()})
    return jsonify({"status": "error", "message": "Failed to toggle module"}), 500

@app.route("/api/logs", methods=["GET"])
def api_logs():
    try:
        with open(LOG_PATH, "r") as f:
            lines = f.readlines()
            return jsonify({"logs": "".join(lines[-30:])})
    except Exception:
        return jsonify({"logs": "No logs available or log file missing."})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
FLASK_APP_EOF
chmod 755 "${INSTALL_DIR}/app.py"
success "Flask application created"

# ─── Step 7: Create HTML template ──────────────────────────────────────────────
info "Creating web UI template..."
mkdir -p "${INSTALL_DIR}/templates"

cat > "${INSTALL_DIR}/templates/index.html" << 'HTML_TEMPLATE_EOF'
<!DOCTYPE html>
<html lang="en" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BashWatch Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;600&family=Plus+Jakarta+Sans:wght@400;600;800&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Plus Jakarta Sans', sans-serif; }
        .mono { font-family: 'JetBrains Mono', monospace; }
    </style>
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen flex flex-col">
    <header class="border-b border-slate-900 bg-slate-900/50 backdrop-blur sticky top-0 z-50 px-6 py-4">
        <div class="max-w-7xl mx-auto flex justify-between items-center">
            <div>
                <h1 class="text-2xl font-extrabold tracking-tight bg-gradient-to-r from-emerald-400 to-cyan-400 bg-clip-text text-transparent">BashWatch</h1>
                <p class="text-xs text-slate-400 mt-0.5">Active Security Engine Monitor</p>
            </div>
            <div class="flex items-center gap-3">
                <span class="text-sm text-slate-400">Global Daemon Status:</span>
                <span id="service-badge" class="px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider bg-slate-800 text-slate-400 animate-pulse">Checking...</span>
            </div>
        </div>
    </header>

    <main class="flex-1 max-w-7xl w-full mx-auto p-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-1 flex flex-col gap-6">
            <div class="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <h2 class="text-lg font-bold mb-4 flex items-center gap-2">🕹️ Core Engine Controls</h2>
                <div class="grid grid-cols-3 gap-3">
                    <button onclick="controlService('start')" class="bg-emerald-600 hover:bg-emerald-500 text-white font-semibold py-2.5 px-4 rounded-xl transition text-sm shadow-lg shadow-emerald-900/20">Start</button>
                    <button onclick="controlService('stop')" class="bg-rose-600 hover:bg-rose-500 text-white font-semibold py-2.5 px-4 rounded-xl transition text-sm shadow-lg shadow-rose-900/20">Stop</button>
                    <button onclick="controlService('restart')" class="bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 font-semibold py-2.5 px-4 rounded-xl transition text-sm">Restart</button>
                </div>
            </div>

            <div class="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl flex flex-col gap-4">
                <h2 class="text-lg font-bold mb-1">🛡️ Defensive Component Modules</h2>
                <p class="text-xs text-slate-400 mb-2">Toggling a module automatically applies parameters and resets the monitoring lifecycle.</p>
                
                <div class="flex items-center justify-between p-3.5 bg-slate-950 rounded-xl border border-slate-800/60">
                    <div>
                        <h3 class="text-sm font-semibold">Network Shield</h3>
                        <p class="text-xxs text-slate-500">IP Table Brute-Force Ban</p>
                    </div>
                    <button id="btn-network_shield" onclick="toggleModule('network_shield')" class="w-12 h-6 rounded-full bg-slate-800 relative transition-colors duration-200 focus:outline-none"><span class="w-4 h-4 rounded-full bg-slate-400 absolute left-1 top-1 transition-transform duration-200"></span></button>
                </div>

                <div class="flex items-center justify-between p-3.5 bg-slate-950 rounded-xl border border-slate-800/60">
                    <div>
                        <h3 class="text-sm font-semibold">Session Watchdog</h3>
                        <p class="text-xxs text-slate-500">Forbidden Command Guard</p>
                    </div>
                    <button id="btn-session_watchdog" onclick="toggleModule('session_watchdog')" class="w-12 h-6 rounded-full bg-slate-800 relative transition-colors duration-200 focus:outline-none"><span class="w-4 h-4 rounded-full bg-slate-400 absolute left-1 top-1 transition-transform duration-200"></span></button>
                </div>

                <div class="flex items-center justify-between p-3.5 bg-slate-950 rounded-xl border border-slate-800/60">
                    <div>
                        <h3 class="text-sm font-semibold">File Integrity Trap</h3>
                        <p class="text-xxs text-slate-500">Inotify File Honeypot Detections</p>
                    </div>
                    <button id="btn-file_trap" onclick="toggleModule('file_trap')" class="w-12 h-6 rounded-full bg-slate-800 relative transition-colors duration-200 focus:outline-none"><span class="w-4 h-4 rounded-full bg-slate-400 absolute left-1 top-1 transition-transform duration-200"></span></button>
                </div>
            </div>
        </div>

        <div class="lg:col-span-2 flex flex-col h-full min-h-[450px]">
            <div class="bg-slate-900 border border-slate-800 rounded-2xl flex flex-col flex-1 shadow-xl overflow-hidden">
                <div class="px-5 py-4 border-b border-slate-800 bg-slate-900/80 flex justify-between items-center">
                    <h2 class="text-lg font-bold flex items-center gap-2">📟 Live Real-time System Log Output</h2>
                    <span class="h-2 w-2 rounded-full bg-emerald-500 animate-ping"></span>
                </div>
                <div class="p-4 flex-1 bg-slate-950 overflow-y-auto font-mono text-xs text-slate-300 leading-relaxed max-h-[500px]" id="logs-terminal">
                    Loading console stream execution variables...
                </div>
            </div>
        </div>
    </main>

    <footer class="text-center py-4 text-xs text-slate-600 border-t border-slate-900 mt-6">
        Bahria University Security Laboratory Systems — Spring 2026
    </footer>

    <script>
        let moduleStates = {};

        async function refreshStatus() {
            fetch('/api/status').then(r => r.json()).then(data => {
                const badge = document.getElementById('service-badge');
                badge.innerText = data.service.toUpperCase();
                badge.className = "px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider transition-all ";
                if (data.service === 'active') {
                    badge.classList.add('bg-emerald-900/30', 'text-emerald-400');
                } else {
                    badge.classList.add('bg-rose-900/30', 'text-rose-400');
                }
                moduleStates = data.modules;
                updateModuleButtons();
            });
            refreshLogs();
        }

        function updateModuleButtons() {
            for (const [mod, enabled] of Object.entries(moduleStates)) {
                const btn = document.getElementById(`btn-${mod}`);
                if (btn) {
                    const span = btn.querySelector('span');
                    btn.classList.toggle('bg-emerald-600', enabled);
                    btn.classList.toggle('bg-slate-800', !enabled);
                    span.classList.toggle('left-6', enabled);
                    span.classList.toggle('left-1', !enabled);
                }
            }
        }

        async function controlService(action) {
            fetch(`/api/service/${action}`, { method: 'POST' }).then(() => refreshStatus());
        }

        async function toggleModule(name) {
            const newState = !moduleStates[name];
            fetch(`/api/module/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ enable: newState })
            }).then(() => refreshStatus());
        }

        function refreshLogs() {
            fetch('/api/logs').then(r => r.json()).then(data => {
                document.getElementById('logs-terminal').innerText = data.logs || 'Waiting for logs...';
            });
        }

        setInterval(refreshStatus, 3000);
        refreshStatus();
    </script>
</body>
</html>
HTML_TEMPLATE_EOF
success "Web UI template created"

# ─── Step 8: Install systemd service ──────────────────────────────────────────
header "Step 8: Installing Systemd Service"

if [[ -f "$SCRIPT_DIR/bashwatch.service" ]]; then
    cp "$SCRIPT_DIR/bashwatch.service" "$SERVICE_FILE"
    success "Service file installed"
else
    warn "bashwatch.service not found, creating default service..."
    cat > "$SERVICE_FILE" << 'SERVICE_EOF'
[Unit]
Description=BashWatch — Integrated Linux Security & Active Response Suite
After=network.target rsyslog.service
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/home/kali/bashwatch
ExecStart=/bin/bash /home/kali/bashwatch/bashwatch.sh
ExecStop=/bin/kill -SIGTERM $MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    success "Default service file created"
fi

# ─── Step 9: Set ownership and permissions ────────────────────────────────────
header "Step 9: Setting File Ownership and Permissions"

chown -R root:kali "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}/bashwatch.sh"
chmod 755 "${INSTALL_DIR}/app.py"
chmod 755 "${INSTALL_DIR}/templates"
chmod -R 755 "${HONEYPOT_DIR}"

success "Permissions set correctly"

# ─── Step 10: Reload systemd and display final instructions ─────────────────────
header "Step 10: Finalizing Installation"

systemctl daemon-reload
success "Systemd configuration reloaded"

# ─── Installation Complete ────────────────────────────────────────────────────
header "Installation Complete! 🎉"

cat << COMPLETION_MSG

Configuration Summary:
┌─────────────────────────────────────────────────────────────┐
│ BashWatch Installation Directory: ${INSTALL_DIR}
│ Python Virtual Environment:        ${VENV_DIR}
│ Systemd Service:                   ${SERVICE_FILE}
│ Honeypot Directory:                ${HONEYPOT_DIR}
│ Web Dashboard Port:                5000
└─────────────────────────────────────────────────────────────┘

Next Steps:

1. Enable and start the BashWatch daemon:
   ${CYAN}sudo systemctl enable bashwatch${NC}
   ${CYAN}sudo systemctl start bashwatch${NC}

2. Start the web dashboard (as regular user):
   ${CYAN}cd ${INSTALL_DIR}${NC}
   ${CYAN}source venv/bin/activate${NC}
   ${CYAN}python3 app.py${NC}

3. Access the web interface:
   ${CYAN}http://localhost:5000${NC}

4. Monitor the BashWatch daemon status:
   ${CYAN}systemctl status bashwatch${NC}

5. View logs:
   ${CYAN}tail -f ${INSTALL_DIR}/logs/bashwatch.log${NC}

COMPLETION_MSG

echo ""
success "BashWatch installation is ready!"

chmod 750 "${INSTALL_DIR}"
# Logs & forensics readable by kali
chown -R root:kali "${INSTALL_DIR}/logs" "${INSTALL_DIR}/forensics"
chmod -R 750 "${INSTALL_DIR}/logs" "${INSTALL_DIR}/forensics"
success "Permissions set (root owns, kali group readable)."

# ── 5. Install & enable systemd service ──────────────────────────────────────
info "Installing systemd service..."
[[ -f "$SERVICE_SRC" ]] || error "bashwatch.service not found at ${SERVICE_SRC}"
cp "$SERVICE_SRC" "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

systemctl daemon-reload
systemctl enable bashwatch.service
success "Service enabled (auto-start on boot)."

# ── 6. Start immediately ──────────────────────────────────────────────────────
info "Starting BashWatch now..."
systemctl start bashwatch.service && success "BashWatch is running!" || \
    warn "Could not start service — check: journalctl -u bashwatch -e"

# ── 7. Status summary ─────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────"
systemctl status bashwatch.service --no-pager -l 2>/dev/null || true
echo "────────────────────────────────────────────────"
echo ""
success "Installation complete!"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status  bashwatch    # Check status"
echo "    sudo systemctl stop    bashwatch    # Stop daemon"
echo "    sudo systemctl restart bashwatch    # Restart daemon"
echo "    sudo journalctl -u bashwatch -f     # Live journal logs"
echo "    tail -f ${INSTALL_DIR}/logs/bashwatch.log   # BashWatch log"
echo "    tail -f ${INSTALL_DIR}/logs/alerts.log      # Alerts only"
echo ""
