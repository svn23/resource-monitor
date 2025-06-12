#!/bin/bash

# resource_monitor.sh - Monitor CPU/Memory usage and send alerts via email.

set -u  # Treat unset variables as an error

# Load configuration
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/config.sh"

# Ensure log directory exists and is writable
LOG_DIR="$(dirname "$LOG_FILE")"
mkdir -p "$LOG_DIR" 2>/dev/null || { echo "ERROR: Cannot create log directory $LOG_DIR"; exit 1; }
touch "$LOG_FILE" 2>/dev/null || { echo "ERROR: Cannot write to log file $LOG_FILE"; exit 1; }

# Log rotation: if log file exceeds 10MB, rotate it
MAX_LOG_SIZE=$((10 * 1024 * 1024))
if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -ge $MAX_LOG_SIZE ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Log rotated (>$MAX_LOG_SIZE bytes)" >> "$LOG_FILE"
fi

# Logging functions
log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: $*" >> "$LOG_FILE"; }
log_info()  { [[ "$LOG_LEVEL" =~ ^(INFO|DEBUG)$ ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $*" >> "$LOG_FILE"; }
log_error() { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >> "$LOG_FILE"; }

log_info "Starting resource_monitor4.sh"

# Verify required commands are available
REQUIRED_CMDS=(top free ps hostname uptime who ss netstat awk grep df head tail)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Initialize state directory and files
HOSTNAME=$(hostname)
mkdir -p "$STATE_DIR" 2>/dev/null || { log_error "Cannot create state directory $STATE_DIR"; exit 1; }
LAST_CPU_FILE="$STATE_DIR/last_cpu_alert"
LAST_MEM_FILE="$STATE_DIR/last_mem_alert"
EMAIL_SCRIPT="${EMAIL_SCRIPT:-$SCRIPT_DIR/send_alert_email3.sh}"

# Manual trigger support:
#   Usage: ./resource_monitor4.sh CPU 50
if [[ $# -eq 2 ]]; then
    TYPE=$1
    USAGE=$2
    if ! [[ "$TYPE" =~ ^(CPU|Memory)$ ]]; then
        echo "Usage: $0 [CPU|Memory] usage%"
        log_error "Invalid manual trigger type '$TYPE'."
        exit 1
    fi
    log_info "Manual trigger: $TYPE usage at ${USAGE}%"
    # Send email alert immediately
    "$EMAIL_SCRIPT" --to "$EMAIL_TO" --host "$HOSTNAME" --type "$TYPE" --usage "$USAGE" \
        --ip "$(hostname -I | awk '{print $1}')" \
        --date "$(date '+%Y-%m-%d %H:%M:%S')" \
        --load "$(uptime)" \
        --processes "$(ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | head -n 10)" \
        --ports "$(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null)" \
        --disk "$(df -h)" \
        --free_space "$(df -h / | tail -n 1 | awk '{print $4}')" \
        --uptime "$(uptime -p)" \
        --users "$(who)" \
        --syslog "$(tail -n 20 "$SYSLOG_PATH" 2>/dev/null || echo 'No syslog found')" \
        --trigger "Manual"
    exit 0
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [CPU|Memory usage%]"
    exit 1
fi

# Function to send an alert email using send_alert_email3.sh
# Arguments: TYPE, USAGE, TRIGGER
send_alert() {
    local alert_type="$1"
    local usage="$2"
    local trigger_type="$3"

    log_info "Threshold alert: $alert_type usage is ${usage}%"
    "$EMAIL_SCRIPT" --to "$EMAIL_TO" --host "$HOSTNAME" --type "$alert_type" --usage "$usage" \
        --ip "$(hostname -I | awk '{print $1}')" \
        --date "$(date '+%Y-%m-%d %H:%M:%S')" \
        --load "$(uptime)" \
        --processes "$(ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | head -n 10)" \
        --ports "$(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null)" \
        --disk "$(df -h)" \
        --free_space "$(df -h / | tail -n 1 | awk '{print $4}')" \
        --uptime "$(uptime -p)" \
        --users "$(who)" \
        --syslog "$(tail -n 20 "$SYSLOG_PATH" 2>/dev/null || echo 'No syslog found')" \
        --trigger "$trigger_type"
    if [[ $? -eq 0 ]]; then
        log_info "Alert email sent for $alert_type usage"
    else
        log_error "Failed to send alert email for $alert_type usage"
    fi
}

# Function to check usage against threshold and send alert if needed
check_and_send() {
    local type="$1"
    local value="$2"
    local last_file="$3"
    local threshold
    if [[ "$type" == "CPU" ]]; then
        threshold=$THRESHOLD_CPU
    else
        threshold=$THRESHOLD_MEM
    fi

    local current_time=$(date +%s)
    local last_time=0
    [[ -f "$last_file" ]] && last_time=$(cat "$last_file")

    log_debug "Checking $type usage: ${value}% (threshold=${threshold}%, last alert time=${last_time})"
    if (( value >= threshold )); then
        if (( current_time - last_time >= COOLDOWN )); then
            send_alert "$type" "$value" "Threshold"
            echo "$current_time" > "$last_file"
            log_info "$type alert sent; cooldown initiated"
        else
            log_debug "$type usage exceeds threshold but cooldown not elapsed"
        fi
    fi
}

# Main monitoring loop
while true; do
    # Gather current usage percentages
    CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\)/ {print 100 - $8}')
    CPU_INT=${CPU_USAGE%.*}
    MEM_USAGE=$(free | awk '/Mem:/ {printf "%.2f", $3/$2 * 100}')
    MEM_INT=${MEM_USAGE%.*}

    # Check and possibly send alerts
    check_and_send "CPU" "$CPU_INT" "$LAST_CPU_FILE"
    check_and_send "Memory" "$MEM_INT" "$LAST_MEM_FILE"

    sleep "$INTERVAL"
done
