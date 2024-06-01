#!/bin/bash

# Check if the settings file exists
SETTINGS_FILE="settings.conf"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Error: Settings file $SETTINGS_FILE does not exist."
    exit 1
fi

# Source the settings from the configuration file
source "$SETTINGS_FILE"

# Check if the required settings are set
if [ -z "$TIME_WINDOW_FIRST_ROUND" ] || [ -z "$LOOP_FREQUENCY" ]; then
    echo "Error: TIME_WINDOW_FIRST_ROUND and LOOP_FREQUENCY must be set in $SETTINGS_FILE."
    exit 1
fi

# Start the monitor script in a detached screen session
sudo screen -d -m -S MonitorIotaNodeLog ./monitorIotaNodeLog.sh "$TIME_WINDOW_FIRST_ROUND" "$LOOP_FREQUENCY" n

# Detach from Linux Screen Session: Ctrl+a d
# List screens: sudo screen -ls
# Restore screen: sudo screen -r MonitorIotaNodeLog
