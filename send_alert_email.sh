#!/bin/bash

# send_alert_email.sh - Sends an alert email for high resource usage.

set -u  # Treat unset variables as an error

# Load configuration
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/config.sh"

# Ensure log directory exists and is writable
LOG_DIR="$(dirname "$LOG_FILE")"
mkdir -p "$LOG_DIR" 2>/dev/null || { echo "ERROR: Cannot create log directory $LOG_DIR"; exit 1; }
touch "$LOG_FILE" 2>/dev/null || { echo "ERROR: Cannot write to log file $LOG_FILE"; exit 1; }

# Logging functions
log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: $*" >> "$LOG_FILE"; }
log_info()  { [[ "$LOG_LEVEL" =~ ^(INFO|DEBUG)$ ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $*" >> "$LOG_FILE"; }
log_error() { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >> "$LOG_FILE"; }

# Verify required commands
REQUIRED_CMDS=(msmtp awk sed)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

log_info "Starting send_alert_email3.sh"

# Determine FROM_EMAIL: use msmtp default if available, else fallback to config or default
if [[ -f /etc/msmtprc ]]; then
    msmtp_from=$(awk '
      BEGIN { in_default=0 }
      /^\s*account\s+default\s*$/ { in_default=1; next }
      /^\s*account\s+/      { in_default=0 }
      in_default && /^\s*from\s+/ {
        gsub(/^from[ \t]+/, "", $0)
        print $0
        exit
      }
    ' /etc/msmtprc)
    if [[ -n "$msmtp_from" ]]; then
        FROM_EMAIL="$msmtp_from"
    fi
fi
FROM_EMAIL=${FROM_EMAIL:-"alert@example.com"}
log_debug "Using FROM_EMAIL: $FROM_EMAIL"

# Print usage message
print_usage() {
  cat <<EOF
Usage: $0 --to email --host hostname --type (CPU|Memory) --usage percentage \\
          --ip ip_address --date timestamp --load load_avg --processes processes_list \\
          --ports port_list [--disk disk_usage] [--free_space free_space_value] \\
          [--uptime uptime_value] [--users user_list] [--syslog syslog_snippets] [--trigger TriggerType]
EOF
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)         TO="$2"; shift 2 ;;
    --host)       HOST="$2"; shift 2 ;;
    --type)       TYPE="$2"; shift 2 ;;
    --usage)      USAGE="$2"; shift 2 ;;
    --ip)         IP="$2"; shift 2 ;;
    --date)       DATE="$2"; shift 2 ;;
    --load)       LOAD="$2"; shift 2 ;;
    --processes)  PROCESSES="$2"; shift 2 ;;
    --ports)      PORTS="$2"; shift 2 ;;
    --disk)       DISK="$2"; shift 2 ;;
    --free_space) FREE_SPACE="$2"; shift 2 ;;
    --uptime)     UPTIME="$2"; shift 2 ;;
    --users)      USERS="$2"; shift 2 ;;
    --syslog)     SYSLOG_SNIPPETS="$2"; shift 2 ;;
    --trigger)    TRIGGER="$2"; shift 2 ;;
    *)            print_usage ;;
  esac
done

# Validate required parameters
if [[ -z "${TO:-}" || -z "${HOST:-}" || -z "${TYPE:-}" || -z "${USAGE:-}" || -z "${IP:-}" || -z "${DATE:-}" || -z "${LOAD:-}" || -z "${PROCESSES:-}" || -z "${PORTS:-}" ]]; then
    log_error "Missing required arguments."
    print_usage
fi

# Default any missing optional arguments
DISK=${DISK:-""}
FREE_SPACE=${FREE_SPACE:-""}
UPTIME=${UPTIME:-""}
USERS=${USERS:-""}
SYSLOG_SNIPPETS=${SYSLOG_SNIPPETS:-""}
TRIGGER=${TRIGGER:-"Threshold"}

# HTML-escape function
html_escape() {
  echo "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' \
                -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

PROCESSES_HTML=$(html_escape "$PROCESSES" | sed 's/$/<br>/g')
PORTS_HTML=$(html_escape "$PORTS" | sed 's/$/<br>/g')
DISK_HTML=$(html_escape "$DISK" | sed 's/$/<br>/g')
USERS_HTML=$(html_escape "$USERS" | sed 's/$/<br>/g')
SYSLOG_HTML=$(html_escape "$SYSLOG_SNIPPETS" | sed 's/$/<br>/g')

EMAIL_SUBJECT="High $TYPE Usage Alert on $HOST"
read -r -d '' EMAIL_BODY <<EOF
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; }
    h2 { color: #d9534f; }
    pre { background: #f8f9fa; border: 1px solid #ddd; padding: 10px; }
  </style>
</head>
<body>
  <h2>High $TYPE Usage Alert on $HOST</h2>
  <p><strong>Date:</strong> $DATE</p>
  <p><strong>Triggered by:</strong> $TRIGGER</p>
  <p><strong>IP Address:</strong> $IP</p>
  <p><strong>$TYPE Usage:</strong> $USAGE%</p>
  <p><strong>System Load:</strong> $LOAD</p>
  <h3>Top Processes (by CPU):</h3>
  <pre>$PROCESSES_HTML</pre>
  <h3>Listening Ports:</h3>
  <pre>$PORTS_HTML</pre>
EOF

if [[ -n "$DISK" ]]; then
    EMAIL_BODY+="<h3>Disk Usage:</h3><pre>$DISK_HTML</pre>"
fi
if [[ -n "$FREE_SPACE" ]]; then
    EMAIL_BODY+="<p><strong>Free Space (/):</strong> $FREE_SPACE</p>"
fi
if [[ -n "$UPTIME" ]]; then
    EMAIL_BODY+="<p><strong>Uptime:</strong> $UPTIME</p>"
fi
if [[ -n "$USERS" ]]; then
    EMAIL_BODY+="<h3>Logged-in Users:</h3><pre>$USERS_HTML</pre>"
fi
if [[ -n "$SYSLOG_SNIPPETS" ]]; then
    EMAIL_BODY+="<h3>Last Syslog Entries:</h3><pre>$SYSLOG_HTML</pre>"
fi

EMAIL_BODY+="
</body>
</html>"

log_info "Sending alert email to $TO"

# Send the email using msmtp
{
  echo "From: $FROM_EMAIL"
  echo "To: $TO"
  echo "Subject: $EMAIL_SUBJECT"
  echo "MIME-Version: 1.0"
  echo "Content-Type: text/html; charset=UTF-8"
  echo ""
  echo "$EMAIL_BODY"
} | msmtp --debug --from="$FROM_EMAIL" -t >> "$LOG_FILE" 2>&1

if [[ ${PIPESTATUS[1]} -eq 0 ]]; then
    log_info "Email sent successfully to $TO"
else
    log_error "Failed to send email to $TO"
fi

