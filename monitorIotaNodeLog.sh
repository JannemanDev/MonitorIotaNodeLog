#!/bin/bash

# Check if the settings file exists
SETTINGS_FILE="settings.conf"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Error: Settings file $SETTINGS_FILE does not exist."
    exit 1
fi

# Source the settings from the configuration file
source "$SETTINGS_FILE"
# Set a flag to indicate that settings.sh has been loaded
SETTINGS_LOADED="true"

source common_functions.sh

# return false if push notification was not sent because of rate limitation
send_pushover_notification_rate_limited() {
    local message="$1"
    local rate_limited=1
    local send_result=0
    
    if (( push_notifications_sent < MAX_PUSH_NOTIFICATIONS_PER_ROUND )) && (( total_push_notifications_sent < MAX_PUSH_NOTIFICATIONS_TOTAL )); then
        # when not rate limited:
        $(send_pushover_notification "$message")
        send_result=$?
        
        if [ $send_result -eq 0 ]; then
            ((push_notifications_sent++))
            ((total_push_notifications_sent++))
            
            echo "Push notification sent ($push_notifications_sent/$MAX_PUSH_NOTIFICATIONS_PER_ROUND) ($total_push_notifications_sent/$MAX_PUSH_NOTIFICATIONS_TOTAL)!"
        fi
    else
        rate_limited=0
        
        rate_limited_msg="Can not sent push notification! Max limit reached for this round ($push_notifications_sent/$MAX_PUSH_NOTIFICATIONS_PER_ROUND) or total ($total_push_notifications_sent/$MAX_PUSH_NOTIFICATIONS_TOTAL)."
        echo "$rate_limited_msg"
        send_pushover_notification "$rate_limited_msg"
    fi

    return $((!rate_limited))
}

send_pushover_notification_not_rate_limited() {
    local message="$1"
    local send_result
    
    send_result=$(send_pushover_notification "$message")
        
    if [ send_result ]; then
        echo "Push notification sent with message:"
        echo "\"$message\""
    fi
    
    return $send_result
}

# Function to be executed on script exit
cleanup() {
    local msg

    rm -f "$LOCKFILE"

    echo
    msg="Script ended $INSTANCE_DESCRIPTION"
    send_pushover_notification_not_rate_limited "$msg"
    echo "$msg"
    
    exit 0
}

usage() {
    echo "Usage: $0 -t <time_window_first_round> -l <loop_frequency>"
    echo "Loop frequency format (required): <number>[s|m|h|d] (seconds, minutes, hours, days)"
    echo "Time window format    (optional): <number>[s|m|h|d] (seconds, minutes, hours, days)"
}

run_process_logs() {
    # Set default parameters
    search_params=(-d "$default_answer")

    # Check if first round flag is true
    if [ "$first_round_flag" = true ]; then
        # Check if time window for first round is given
        if [ -n "$time_window_first_round" ]; then
            time_window_param="$time_window_seconds_first_round"
        fi
    else
        time_window_param="$loop_freq_seconds"
    fi

    # Add time window parameter to search_params if applicable
    if [ -n "$time_window_first_round" ] || [ "$first_round_flag" = false ]; then
        # Adjust the time window parameter if needed
        adjusted_time_window_param=$((time_window_param + 60))
        search_params+=(-t "$adjusted_time_window_param""s")
    fi

    # Call searchDockerLogForErrors.sh script with adjusted parameters
    source searchDockerLogForErrorsInclude.sh

    echo "Contents of search_params array:"
    for search_param in "${search_params[@]}"; do
        echo "search_param=$search_param"
    done

    searchDockerLogForErrors "${search_params[@]}"
    # if ! searchDockerLogForErrors "${search_params[@]}"; then
        # echo "searchDockerLogForErrors.sh failed"
        # return
    # fi

    # be sure to remove any empty/blank/only whitespace lines before comparing
    grep -vE '^\s*$' "$TMP_DIR/errors4.txt" > "$TMP_DIR/errors4.txt.tmp" && mv "$TMP_DIR/errors4.txt.tmp" "$TMP_DIR/errors4.txt"

    # Check if already exists
    allUniqueErrorsFile="allUniqueErrors_$node_id.txt"
    echo "allUniqueErrorsFile=$allUniqueErrorsFile"
    if [ -f "$TMP_DIR/$allUniqueErrorsFile" ]; then
        # be sure to remove any empty/blank/only whitespace lines before comparing
        grep -vE '^\s*$' "$TMP_DIR/$allUniqueErrorsFile" > "$TMP_DIR/$allUniqueErrorsFile.tmp" && mv "$TMP_DIR/$allUniqueErrorsFile.tmp" "$TMP_DIR/$allUniqueErrorsFile"
        # Compare the new errors with the all previous ones and save to new (unique) errors
        comm -13 <(sort "$TMP_DIR/$allUniqueErrorsFile") <(sort "$TMP_DIR/errors4.txt") > "$TMP_DIR/newErrors.txt"
    else
        # first round so all errors are new and copied to $allUniqueErrorsFile
        cp "$TMP_DIR/errors4.txt" "$TMP_DIR/newErrors.txt"
    fi

    line_count=$(wc -l < "$TMP_DIR/newErrors.txt")
    echo "Number of NEW unique errors in this round: $line_count"

    format_lines "$TMP_DIR/newErrors.txt"

    cat "$TMP_DIR/newErrors.txt" >> "$TMP_DIR/$allUniqueErrorsFile"

    line_count=$(wc -l < "$TMP_DIR/$allUniqueErrorsFile")
    echo "All unique errors so far: $line_count"

    # Send a Pushover notification for each new error in newErrors.txt
    while IFS= read -r error; do
        if [ -n "$error" ]; then
            if ! send_pushover_notification_rate_limited "$error"; then
                break
            fi
        fi
    done < "$TMP_DIR/newErrors.txt"
}

generate_instance_description(){
    local instance_description
    
    network_info=($(get_network_info))
    local_ip=network_info[0]
    remote_ip=network_info[0]
    hostname=network_info[0]

    current_path=$(pwd)
    instance_description="for $DOCKER_CONTAINER_NAME running from path \"$current_path\" on:<br>Hostname: $hostname<br>Local IP: $local_ip<br>Remote IP: $remote_ip"
    
    echo "$instance_description"
}

create_lockfile(){
    local lockfile="$1"
    
    # Check if lockfile exists
    if [ -e "$lockfile" ]; then
        echo "Error: Lockfile $lockfile exists. Another instance of the script is running."
        exit 1
    fi

    # Create lockfile
    touch "$lockfile"
}

### Start of main program ###

if ! running_as_root; then
    echo "This script must be run as root/sudo"
    exit 1
fi

if ! docker_running; then
    echo "Docker is not running."
    exit 1
fi

# Catch signals and execute cleanup function
trap cleanup SIGINT SIGTERM SIGHUP SIGQUIT

# Create temporary directory if it does not exist
mkdir -p "$TMP_DIR"

# Initialize variables
time_window_first_round="$TIME_WINDOW_FIRST_ROUND"
loop_frequency="$LOOP_FREQUENCY"
default_answer="n"
show_help=false

# echo "time_window_first_round=$time_window_first_round"
# echo "loop_frequency=$loop_frequency"

# Parse options
while getopts ":t:l:h" opt; do
    case ${opt} in
        t )
            time_window_first_round=$OPTARG
            ;;
        l )
            loop_frequency=$OPTARG
            ;;
        h )
            show_help=true
            ;;            
        \? )
            echo "Invalid option: $OPTARG" 1>&2
            exit 1
            ;;
        : )
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# echo "time_window_first_round=$time_window_first_round"
# echo "loop_frequency=$loop_frequency"

# If -h option is provided, show help and exit
if [ "$show_help" = true ]; then
    usage
    exit 0
fi

# Check if time window parameters and frequency parameter are provided
if [ -z "$loop_frequency" ]; then
    usage
    exit 1
fi

# Validate time format for loop_frequency
validate_time_format "$loop_frequency" "loop_frequency (-l)"

# Convert time window to seconds only if time_window_first_round is given
if [ -n "$time_window_first_round" ]; then
    # Validate time format for time_window_first_round
    validate_time_format "$time_window_first_round" "time_window_first_round (-t)"

    time_window_seconds_first_round=$(convert_to_seconds "$time_window_first_round")
fi
loop_freq_seconds=$(convert_to_seconds "$loop_frequency")

# Get the name of the running script
SCRIPT_NAME=$(basename "$0")
# Define lockfile in the current directory
LOCKFILE="./${SCRIPT_NAME}.lock"

create_lockfile "$LOCKFILE"

INSTANCE_DESCRIPTION=$(generate_instance_description)
startup_message="Monitoring errors in logfile $INSTANCE_DESCRIPTION"
send_pushover_notification_not_rate_limited "$startup_message"

first_round_flag=true
push_notifications_sent=0
total_push_notifications_sent=0

# Initialize previous state variables
previous_state_health_status=""
previous_state_status=""
previous_node_id=""
previous_node_is_healthy=""

health_check_frequency_seconds=$(convert_to_seconds "$HEALTH_CHECK_FREQUENCY")

# start first run immediately (health and run_process_logs)
next_health_check=$(date +%s)
next_run_process_logs=$(date +%s)

echo "next_health_check=$next_health_check"
echo "next_run_process_logs=$next_run_process_logs"

while true; do
    while true; do
        container_state=($(get_container_state "$DOCKER_CONTAINER_NAME"))
        state_health_status="${container_state[0]}"
        state_status="${container_state[1]}"

        if [ "$state_health_status" != "$previous_state_health_status" ] || [ "$state_status" != "$previous_state_status" ]; then
            if [ -n "$previous_state_health_status" ] || [ -n "$previous_state_status" ]; then
                msg="Docker container state changed to:<br>Health: $state_health_status<br>Status: $state_status"
            else
                msg="Docker container current initial state:<br>Health: $state_health_status<br>Status: $state_status"
            fi
            previous_state_health_status="$state_health_status"
            previous_state_status="$state_status"
            send_pushover_notification_not_rate_limited "$msg"
        fi
        
        node_id=$(extract_node_id_from_docker_container "$DOCKER_CONTAINER_NAME")
        if [ "$node_id" != "$previous_node_id" ]; then
            if [ -n "$previous_node_id" ]; then
                msg="Node ID changed to:<br>$node_id"
            else
                msg="Node ID current initial value:<br>$node_id"
            fi
            previous_node_id="$node_id"
            send_pushover_notification_not_rate_limited "$msg"
        fi
        echo "node_id=$node_id"
        
        if [ "$state_health_status" = "healthy" ] && [ "$state_status" = "running" ]; then
            break
        fi

        # retry after 1 second
        custom_sleep 1
    done
  
    if (( $(date +%s) >= next_health_check )); then
        node_is_healthy=$(get_node_health_from_docker_container "$DOCKER_CONTAINER_NAME")
        if [ "$node_is_healthy" != "$previous_node_is_healthy" ]; then
            if [ -n "$previous_node_is_healthy" ]; then
                msg="Node is_healthy changed to:<br>$node_is_healthy"
            else
                msg="Node is_healthy current initial value:<br>$node_is_healthy"
            fi
            previous_node_is_healthy="$node_is_healthy"
            send_pushover_notification_not_rate_limited "$msg"
        fi
        next_health_check=$(( $(date +%s) + health_check_frequency_seconds ))
        echo "next_health_check=$next_health_check"
    fi
    
    if (( $(date +%s) >= next_run_process_logs )); then
        push_notifications_sent=0
        run_process_logs
        first_round_flag=false
        next_run_process_logs=$(( $(date +%s) + loop_freq_seconds ))
        echo "next_run_process_logs=$next_run_process_logs"        
    fi
    
    custom_sleep 1
done
