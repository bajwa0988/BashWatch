# BashWatch — Integrated Linux Security & Active Response Suite

**Course:** Operating Systems (Spring-2026) — Bahria University, Islamabad  
**Teacher:** Engr. Aamir Sohail  
**Group:** Saad Ali Bajwa (078) & Shahzeb Qamar (066) | BSE 4B

---

## What is BashWatch?

BashWatch is a lightweight, native Linux security daemon written entirely in
Bash. It transitions from passive logging to **active defense** — it detects
threats and responds automatically, even with no administrator online.

**Protected user:** `kali` — this account is **never** blocked, killed, or
locked out by any module.

---

## Prerequisites

### System Requirements

- **OS:** Linux (Kali Linux recommended)
- **Root Access:** Required for installation and daemon operation
- **Python:** 3.7 or higher
- **Disk Space:** Minimum 100 MB free

### Required Packages

The installer will automatically install the following:

- `python3` - Python runtime
- `python3-venv` - Python virtual environments
- `python3-pip` - Python package manager
- `inotify-tools` - File system monitoring
- `lsof` - List open files
- `psmisc` - Process utilities
- `net-tools` - Network utilities

### Optional for Remote Access

For accessing the web UI remotely, ensure:
- Port 5000 is accessible (check firewall)
- Network connectivity to the target machine

---

## Architecture

```
bashwatch.sh  (main daemon)
│
├── Module A: Network Shield      [default: OFF]
│   └── Monitors SSH auth.log → iptables-blocks brute-force IPs
│
├── Module B: Session Watchdog    [default: OFF]
│   └── Scans process list → kills forbidden commands (nmap, nc, …)
│
└── Module C: File Trap           [default: ON  ✓]
    └── inotifywait on honeypot dirs → locks offending accounts
        + collects forensic bundle
```

All modules feed into a shared **Forensic Evidence Collector** that captures:
- Process tree snapshot (`ps auxf`)
- Open network sockets (`ss -tulpn`)
- Files opened by the offender (`lsof`)
- Active sessions (`who`, `last`)
- Auth log tail

---

## Installation

### Quick Start (Automated)

```bash
# 1. Navigate to the installation directory
cd /path/to/files

# 2. Run the installer as root (handles everything automatically)
sudo bash install.sh
```

The installer will:
- ✓ Install Python 3 and system dependencies
- ✓ Create directory structure at `/home/kali/bashwatch`
- ✓ Set up Python virtual environment
- ✓ Install Flask and dependencies
- ✓ Create the web dashboard UI
- ✓ Copy BashWatch daemon script
- ✓ Install systemd service
- ✓ Set proper permissions and ownership

### Manual Installation (if needed)

```bash
# 1. Clone / copy the project folder onto your Kali machine
# 2. Run the installer as root
sudo bash install.sh
```

The installer will:
1. Install dependencies (`inotify-tools`, `lsof`, `psmisc`, `net-tools`)
2. Copy files to `/home/kali/bashwatch/`
3. Register & enable the systemd service (auto-start on boot)
4. Start BashWatch immediately

---

## Directory Layout (after install)

```
/home/kali/bashwatch/
├── bashwatch.sh          ← main daemon (owned root, executable)
├── app.py                ← Flask web UI application
├── venv/                 ← Python virtual environment
├── logs/
│   ├── bashwatch.log     ← timestamped event log
│   └── alerts.log        ← high-priority alerts only
├── forensics/            ← compressed .tar.gz bundles per incident
├── templates/
│   └── index.html        ← web UI dashboard
└── honeypots/
    ├── secret_keys/      ← decoy files (id_rsa, .env, …)
    ├── passwd_backup/
    ├── root_creds/
    └── private_data/
```

---

## Running the Web UI

After installation, the Flask-based web dashboard is available for remote monitoring and control of the BashWatch daemon.

### Starting the Web UI

**Method 1: Manual Start (for development/testing)**

```bash
# Activate the Python virtual environment
source /home/kali/bashwatch/venv/bin/activate

# Navigate to the installation directory
cd /home/kali/bashwatch

# Start the Flask application
python app.py
```

The web UI will start on `http://localhost:5000`

**Method 2: Systemd Service (recommended for production)**

The installer automatically configures BashWatch as a systemd service. The daemon runs automatically on boot:

```bash
# Check the daemon status
sudo systemctl status bashwatch

# Start the daemon (if not already running)
sudo systemctl start bashwatch

# Stop the daemon
sudo systemctl stop bashwatch

# Restart the daemon
sudo systemctl restart bashwatch
```

The daemon operates independently in the background and does **not** require the web UI to function.

### Accessing the Web Dashboard

1. **Local Access:**
   - Open your browser and navigate to: `http://localhost:5000`

2. **Remote Access:**
   - From another machine on the network: `http://<target-ip>:5000`
   - Ensure the firewall allows traffic on port 5000

### Web UI Features

The dashboard displays and allows control of:

- **Service Status:** View if the BashWatch daemon is running
- **Module States:** Check if Network Shield, Session Watchdog, and File Trap are enabled
- **Service Control:** Start, stop, or restart the daemon
- **Module Management:** Toggle individual security modules on/off
- **Live Logs:** View the last 30 log entries in real-time
- **Configuration:** Modify BashWatch settings through the UI

### Web UI Architecture

```
Flask Application (app.py)
│
├── Routes:
│   ├── GET  /                      → Display dashboard (index.html)
│   ├── GET  /api/status            → Get service and module states
│   ├── POST /api/service/<action>  → Control daemon (start/stop/restart)
│   ├── POST /api/module/<name>     → Toggle modules
│   └── GET  /api/logs              → Retrieve latest log entries
│
└── Backend:
    ├── Reads /home/kali/bashwatch/bashwatch.sh for configuration
    ├── Interacts with systemctl for service control
    └── Monitors /home/kali/bashwatch/logs/bashwatch.log
```

---

## Configuration

All settings live at the top of `bashwatch.sh`:

| Variable | Default | Description |
|---|---|---|
| `PROTECTED_USER` | `kali` | Account never touched by any module |
| `ENABLE_NETWORK_SHIELD` | `false` | Enable anti-brute-force module |
| `ENABLE_SESSION_WATCHDOG` | `false` | Enable forbidden-command killer |
| `ENABLE_FILE_TRAP` | `true` | Enable honeypot / inotify module |
| `BRUTE_THRESHOLD` | `5` | SSH failures before IP ban |
| `BRUTE_WINDOW` | `120` | Seconds to look back in auth.log |
| `FORBIDDEN_CMDS` | nmap, nc, … | Commands that trigger session kill |
| `WATCHDOG_INTERVAL` | `5` | Seconds between process scans |
| `HONEYPOT_NAMES` | 4 dirs | Names of honeypot trap directories |

To enable optional modules, open `bashwatch.sh` and flip the toggle:

```bash
ENABLE_NETWORK_SHIELD=true
ENABLE_SESSION_WATCHDOG=true
```

Then restart: `sudo systemctl restart bashwatch`

---

## Useful Commands

### Service & Daemon Management

```bash
# Check daemon status
sudo systemctl status bashwatch

# Service control
sudo systemctl stop    bashwatch
sudo systemctl start   bashwatch
sudo systemctl restart bashwatch

# Enable/disable auto-start on boot
sudo systemctl enable  bashwatch
sudo systemctl disable bashwatch
```

### Web UI Management

```bash
# Start the Flask web UI (development mode)
source /home/kali/bashwatch/venv/bin/activate
cd /home/kali/bashwatch
python app.py

# Access the dashboard
# http://localhost:5000  (local)
# http://<target-ip>:5000 (remote)

# View Flask application logs
tail -f /var/log/bashwatch_web.log (if configured)
```

### Logging & Monitoring

```bash
# View daemon logs in real-time
tail -f /home/kali/bashwatch/logs/bashwatch.log

# View high-priority alerts only
tail -f /home/kali/bashwatch/logs/alerts.log

# View systemd journal for the service
sudo journalctl -u bashwatch -f
sudo journalctl -u bashwatch -n 100  # Last 100 lines
sudo journalctl -u bashwatch --since "2 hours ago"

# Search for specific events in logs
grep "TRAP_FIRED" /home/kali/bashwatch/logs/bashwatch.log
grep "BLOCKED" /home/kali/bashwatch/logs/alerts.log
```

### Forensics & Evidence

```bash
# List all forensic bundles
ls -lh /home/kali/bashwatch/forensics/

# Extract a forensic bundle
tar -xzf /home/kali/bashwatch/forensics/<bundle>.tar.gz -C /tmp/

# View contents of a forensic bundle without extracting
tar -tzf /home/kali/bashwatch/forensics/<bundle>.tar.gz

# Find all forensic bundles from a specific date
find /home/kali/bashwatch/forensics/ -name "*2026-06*" -type f
```

### Configuration Management

```bash
# Edit BashWatch configuration
sudo nano /home/kali/bashwatch/bashwatch.sh
# Modify variables at the top of the script, then restart

# Apply configuration changes
sudo systemctl restart bashwatch

# Verify configuration changes took effect
grep "ENABLE_" /home/kali/bashwatch/bashwatch.sh | head -3
```

### Troubleshooting

```bash
# Check if dependencies are installed
which inotifywait lsof psmisc ss

# Verify service file is properly registered
systemctl cat bashwatch

# Check current firewall rules (if Network Shield enabled)
sudo iptables -L -n | grep -i "bashwatch\|INPUT"

# Monitor real-time events
watch -n 1 'tail -20 /home/kali/bashwatch/logs/bashwatch.log'
```

---

## OS Concepts Demonstrated

| Concept | Where used |
|---|---|
| **Signal handling** | `trap` for SIGTERM/SIGINT; SIGHUP/SIGKILL to kill sessions |
| **Process management** | `ps`, `pkill`, background job control, sub-shells |
| **File descriptors** | `inotifywait`, `lsof`, log redirection |
| **Kernel networking** | `iptables` INPUT chain manipulation |
| **IPC / Sockets** | `ss`, `netstat` for network state capture |
| **File system events** | `inotifywait` (kernel inotify API) |
| **Systemd / init** | Service unit, dependency ordering, restart policy |
| **Capabilities** | `CAP_NET_ADMIN`, `CAP_KILL` instead of full root exposure |

---

## Uninstall

```bash
sudo bash uninstall.sh
```

This will:
- Stop the BashWatch service
- Disable the systemd unit
- Remove all BashWatch files from `/home/kali/bashwatch/`
- Restore system permissions

---

## Troubleshooting

### Common Issues

**Issue: Permission denied when running installer**
```bash
# Solution: Ensure you have root privileges
sudo bash install.sh
```

**Issue: Web UI not accessible on localhost:5000**
```bash
# Check if Flask app is running
ps aux | grep python
ps aux | grep app.py

# Check if port 5000 is in use
sudo lsof -i :5000

# Activate venv and start manually
source /home/kali/bashwatch/venv/bin/activate
cd /home/kali/bashwatch
python app.py
```

**Issue: Daemon not starting automatically**
```bash
# Check service status
sudo systemctl status bashwatch

# View error logs
sudo journalctl -u bashwatch -e

# Try manual restart
sudo systemctl restart bashwatch
```

**Issue: inotifywait or other dependencies not found**
```bash
# Reinstall dependencies
sudo apt-get install inotify-tools lsof psmisc net-tools

# Rerun installer
sudo bash install.sh
```

**Issue: File trap not triggering on honeypot access**
```bash
# Verify honeypot directories exist
ls -la /home/kali/bashwatch/honeypots/

# Check file permissions
stat /home/kali/bashwatch/honeypots/secret_keys/

# Manually test inotifywait
inotifywait -m /home/kali/bashwatch/honeypots/secret_keys/ &
touch /home/kali/bashwatch/honeypots/secret_keys/test.txt
```

### Getting Help

- Check daemon logs: `tail -f /home/kali/bashwatch/logs/bashwatch.log`
- Review systemd journal: `sudo journalctl -u bashwatch -n 50`
- Verify configuration: `cat /home/kali/bashwatch/bashwatch.sh | head -30`

---

## Notes

## Notes

### Implementation Details

- The script is heavily commented and structured into named functions to
  clearly map each function to the OS concept it demonstrates.
- The `kali` protection check appears in **every** destructive code path
  (firewall block, session kill, account lock).
- Log rotation is built-in (files > 10 MB are archived automatically).
- The forensic collector is event-driven — it runs only when a threat fires,
  not in a polling loop, keeping CPU usage near zero at idle.
- The Flask web UI (`app.py`) runs in `debug=True` mode during development;
  set to `debug=False` for production deployments.

---

## Project Information

- **Language:** Bash (daemon) + Python (web UI)
- **Framework:** Flask 2.3.2
- **License:** GNU General Public License v3.0
- **Author(s):** Saad Ali Bajwa (078), Shahzeb Qamar (066)
- **Institution:** Bahria University, Islamabad
- **Course:** Operating Systems (Spring-2026)
- **Instructor:** Engr. Aamir Sohail

---

## Related Resources

- [Kali Linux Documentation](https://www.kali.org/docs/)
- [Linux Systemd Documentation](https://www.freedesktop.org/software/systemd/man/systemctl.html)
- [Flask Official Documentation](https://flask.palletsprojects.com/)
- [inotify-tools Manual](https://www.mankier.com/1/inotifywait)
- [iptables Guide](https://wiki.archlinux.org/title/iptables)

---

## Security Considerations

⚠️ **Important Notes:**

- This tool performs aggressive system actions (blocking IPs, killing processes, locking accounts). Use only in controlled environments.
- The `kali` user account is always protected to prevent accidental system lockout.
- The daemon runs with **full root privileges**. Audit the code before deploying in production.
- Enable only the modules you need (File Trap is enabled by default; others are opt-in).
- Keep regular backups of configuration before making changes.
- Monitor forensic bundles to avoid disk space issues during extended operation.

---

## Contributing

This project was developed as part of an operating systems course. Pull requests, issues, and suggestions are welcome.

---

## Disclaimer

BashWatch is provided **as-is** for educational purposes. The authors are not responsible for any damage or disruption caused by its use. Always test in a non-production environment first.

---

**Last Updated:** June 2026
