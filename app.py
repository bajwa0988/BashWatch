import subprocess
import re
from flask import Flask, render_template, jsonify, request

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
            lines = f.readlines()
        
        target_value = "true" if enable else "false"
        old_value = "false" if enable else "true"
        
        updated = False
        for i, line in enumerate(lines):
            # Match pattern with flexible spaces: VAR=value or VAR = value
            if re.match(rf"^{re.escape(module_var)}\s*=\s*{old_value}\b", line):
                # Replace with new value, preserving trailing content (comments, spaces)
                lines[i] = re.sub(
                    rf"^{re.escape(module_var)}\s*=\s*{old_value}",
                    f"{module_var}={target_value}",
                    line
                )
                updated = True
                break
        
        if updated:
            with open(SCRIPT_PATH, "w") as f:
                f.writelines(lines)
            return True
        else:
            print(f"Warning: Could not find {module_var}={old_value} in script")
            return False
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
            # Apply configuration updates to systemd dynamically
            subprocess.run(["sudo", "systemctl", "restart", "bashwatch"])
            return jsonify({"status": "success", "modules": get_module_states()})
    return jsonify({"status": "error", "message": "Failed to toggle module"}), 500

@app.route("/api/logs", methods=["GET"])
def api_logs():
    try:
        with open(LOG_PATH, "r") as f:
            lines = f.readlines()
            return jsonify({"logs": "".join(lines[-30:])}) # Send last 30 log lines
    except Exception:
        return jsonify({"logs": "No logs available or log file missing."})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
