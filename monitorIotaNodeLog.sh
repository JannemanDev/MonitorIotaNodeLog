#!/bin/bash

# Check if the settings file exists
SETTINGS_FILE="settings.conf"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Error: Settings file $SETTINGS_FILE does not exist."
    exit 1
fi

# Source the settings from the configuration file
source "$SETTINGS_FILE"

# Check if time window parameters and frequency parameter are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <time_window_first_round> <loop_frequency> [default_answer]"
    echo "Time window format: <number>[s|m|h|d] (seconds, minutes, hours, days)"
    echo "Loop frequency format: <number>[s|m|h|d] (seconds, minutes, hours, days)"
    echo "Optional default_answer: enter/y/Y for yes, anything else for no"
    exit 1
fi

# Function to convert time window or loop frequency to seconds
convert_to_seconds() {
    local time_str="$1"
    local time_format=$(echo "$time_str" | sed 's/[0-9]*//g')
    local time_value=$(echo "$time_str" | sed 's/[s|m|h|d]//g')

    case "$time_format" in
        s) echo "$time_value";;
        m) echo "$((time_value * 60))";;
        h) echo "$((time_value * 3600))";;
        d) echo "$((time_value * 86400))";;
        *) echo "Invalid time format"; exit 1;;
    esac
}

# Function to send a Pushover notification
send_pushover_notification() {
    local message="$1"
    curl -s \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "message=$message" \
        --form-string "html=1" \
        https://api.pushover.net/1/messages.json
    ((push_notifications_sent++))
    ((total_push_notifications_sent++))
    echo
}

# Function to retrieve network information
get_network_info() {
    local_ip=$(hostname -I | awk '{print $1}')
    remote_ip=$(curl -s ifconfig.me)
    hostname=$(hostname)
}

format_lines() {
    local filename="$1"

    # Check if the file exists
    if [ ! -f "$filename" ]; then
        echo "File not found!"
        return 1
    fi

    # Read the file line by line
    local line_number=1
    while IFS= read -r line; do
        echo " [$line_number] = \"$line\""
        line_number=$((line_number + 1))
    done < "$filename"
}

# Function to run the process logs script
run_process_logs() {
    # Check if it's the first round
    if [ "$first_round_flag" = true ]; then
        time_window_param="$time_window_seconds_first_round"
    else
        time_window_param="$loop_freq_seconds"
    fi
    
    # Add 1 minute (60 seconds) to the time frequency for calling process_logs.sh
    adjusted_time_window_param=$((time_window_param + 60))
   
    # Run the process_logs.sh script
    ./searchDockerLogForErrors.sh "${adjusted_time_window_param}s" "$default_answer"

    # be sure to remove any empty/blank/only whitespace lines before comparing
    grep -vE '^\s*$' "$TMP_DIR/errors4.txt" > "$TMP_DIR/errors4.txt.tmp" && mv "$TMP_DIR/errors4.txt.tmp" "$TMP_DIR/errors4.txt"
    grep -vE '^\s*$' "$TMP_DIR/allUniqueErrors.txt" > "$TMP_DIR/allUniqueErrors.txt.tmp" && mv "$TMP_DIR/allUniqueErrors.txt.tmp" "$TMP_DIR/allUniqueErrors.txt"

    # Check if already exists
    if [ -f "$TMP_DIR/allUniqueErrors.txt" ]; then
        # Compare the new errors with the all previous ones and save to new (unique) errors
        comm -13 <(sort "$TMP_DIR/allUniqueErrors.txt") <(sort "$TMP_DIR/errors4.txt") > "$TMP_DIR/newErrors.txt"
    else
        # first round so all errors are new and copied to allUniqueErrors.txt
        cp "$TMP_DIR/errors4.txt" "$TMP_DIR/newErrors.txt"
    fi

    line_count=$(wc -l < "$TMP_DIR/newErrors.txt")
    echo "Number of NEW unique errors in this round: $line_count"

    format_lines "$TMP_DIR/newErrors.txt"

    cat "$TMP_DIR/newErrors.txt" >> "$TMP_DIR/allUniqueErrors.txt"

    line_count=$(wc -l < "$TMP_DIR/allUniqueErrors.txt")
    echo "All unique errors so far: $line_count"

    # Send a Pushover notification for each new error in newErrors.txt
    while IFS= read -r error; do
        if [ -n "$error" ]; then
            if (( push_notifications_sent < MAX_PUSH_NOTIFICATIONS_PER_ROUND )) && (( total_push_notifications_sent < MAX_PUSH_NOTIFICATIONS_TOTAL )); then
                send_pushover_notification "$error"
            else
                msg="Max push notifications limit reached for this round ($push_notifications_sent/$MAX_PUSH_NOTIFICATIONS_PER_ROUND) or total ($total_push_notifications_sent/$MAX_PUSH_NOTIFICATIONS_TOTAL)."
                echo "$msg"
                send_pushover_notification "$msg"
                break
            fi
        fi
    done < "$TMP_DIR/newErrors.txt"
}

# Function to be executed on script exit
cleanup() {
    echo
    msg="Script ended."
    send_pushover_notification "$msg"
    echo "$msg"
    exit 0
}

# to make it more responsive to SIGTERM
custom_sleep() {
    local duration=$1
    local i

    for ((i=0; i<duration; i++)); do
        sleep 1
    done
}

# Catch signals and execute cleanup function
trap cleanup SIGINT SIGTERM SIGHUP SIGQUIT

# Create temporary directory if it does not exist
mkdir -p "$TMP_DIR"

# Parse the time window parameters and loop frequency
time_window_first_round="$1"
loop_frequency="$2"
default_answer="$3"

# Convert time windows and loop frequency to seconds
time_window_seconds_first_round=$(convert_to_seconds "$time_window_first_round")
loop_freq_seconds=$(convert_to_seconds "$loop_frequency")

get_network_info
startup_message="Monitoring errors in logfile for $DOCKER_CONTAINER_NAME on:<br>Hostname: $hostname<br>Local IP: $local_ip<br>Remote IP: $remote_ip"
send_pushover_notification "$startup_message"

first_round_flag=true
push_notifications_sent=0
total_push_notifications_sent=0

# Run indefinitely
while true; do
    run_process_logs
    first_round_flag=false
    next_round_time=$(date -d "+$loop_freq_seconds seconds" +"%Y-%m-%d %H:%M:%S")
    echo "Waiting for next round which will start at $next_round_time"
    echo
    custom_sleep "$loop_freq_seconds"
    push_notifications_sent=0
done
