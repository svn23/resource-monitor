#!/bin/bash

# config.sh - Configuration for resource monitoring and alert scripts.

# Logging settings
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
LOG_FILE="/opt/sovan/resource.log"

# Email settings
EMAIL_TO=${EMAIL_TO:-"admin@company.com"}              # Recipient email for alerts
FROM_EMAIL=${FROM_EMAIL:-""}                            # (Optional) Sender email; msmtp config may override

# Syslog path (adjust for your distribution)
SYSLOG_PATH=${SYSLOG_PATH:-"/var/log/messages"}
if [[ ! -f "$SYSLOG_PATH" ]]; then
    # Try alternate common syslog location
    if [[ -f /var/log/syslog ]]; then
        SYSLOG_PATH="/var/log/syslog"
    fi
fi

# Resource usage thresholds and timing (override as needed)
THRESHOLD_CPU=${THRESHOLD_CPU:-90}    # CPU usage (%) to trigger alert
THRESHOLD_MEM=${THRESHOLD_MEM:-90}    # Memory usage (%) to trigger alert
INTERVAL=${INTERVAL:-60}              # Seconds between checks
COOLDOWN=${COOLDOWN:-3600}           # Seconds between repeated alerts of same type

# State directory for storing last alert timestamps
STATE_DIR=${STATE_DIR:-"/var/tmp/resource_monitor"}  # Persistent state storage (e.g., /var/tmp)
