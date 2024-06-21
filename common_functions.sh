#!/bin/bash
# shellcheck disable=SC2317  # Don't warn about unreachable commands in this file

format_lines() {
    local filename="$1"

    # Check if the file exists
    if [ ! -f "$filename" ]; then
        echo "File not found!"
        exit 1
    fi

    # Read the file line by line
    local line_number=1
    while IFS= read -r line; do
        echo " [$line_number] = \"$line\""
        line_number=$((line_number + 1))
    done <"$filename"
}

validate_time_format() {
    local time_str="$1"
    local param_name="$2"
    if [[ ! "$time_str" =~ ^[0-9]+[smhd]$ ]]; then
        echo "Error: Invalid time format for $param_name: $time_str. Please use format <number>[s|m|h|d]."
        exit 1
    fi
}

# Function to convert time format s(econds), m(inutes), h(ours), d(ays) to seconds
# For example: 2m -> 120
convert_to_seconds() {
    local time_str="$1"
    local time_format
    local time_value

    time_format="${time_str//[^smhd]/}"
    time_value="${time_str//[smhd]/}"

    case "$time_format" in
    s) echo "$time_value" ;;
    m) echo "$((time_value * 60))" ;;
    h) echo "$((time_value * 3600))" ;;
    d) echo "$((time_value * 86400))" ;;
    *)
        echo "Invalid time format"
        exit 1
        ;;
    esac
}

# Returns retrieve network and host information as array
get_network_info() {
    local local_ip
    local remote_ip
    local hostname

    local_ip=$(hostname -I | awk '{print $1}')
    remote_ip=$(curl -s ifconfig.me)
    hostname=$(hostname)

    echo "$local_ip"
    echo "$remote_ip"
    echo "$hostname"
}

# to make it more responsive to SIGTERM
# sleep duration parameter in seconds
custom_sleep() {
    local duration=$1
    local i

    for ((i = 0; i < duration; i++)); do
        sleep 1
    done
}

extract_node_id_from_docker_container() {
    local docker_name="$1"
    local node_id
    # Run docker logs command and capture the output
    docker_logs_output=$(sudo docker exec "$docker_name" /app/iota-core tools p2pidentity-extract --identityPrivateKeyFilePath data/p2p/identity.key)

    # Define the regex pattern to match a container ID
    regex="PeerID:\s+([a-zA-Z0-9]+)"

    # Extract the container ID from the Docker logs output
    if [[ $docker_logs_output =~ $regex ]]; then
        node_id="${BASH_REMATCH[1]}"
        echo "$node_id"
    else
        echo ""
    fi
}

get_node_health_from_docker_container() {
    local docker_name="$1"
    local is_healthy
    node_info_output=$(sudo docker exec "$docker_name" /app/iota-core tools node-info 2>/dev/null)
    is_healthy=$(echo "$node_info_output" | grep "IsHealthy:" | awk '{print $2}')
    echo "$is_healthy"
}

running_as_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0 # True, script is run as root
    else
        return 1 # False, script is not run as root
    fi
}

docker_running() {
    if sudo docker info >/dev/null 2>&1; then
        return 0 # Docker is running
    else
        return 1 # Docker is not running
    fi
}

# returns state_health_status and state_status as array
get_container_state() {
    local docker_name="$1"
    local docker_inspect_json_output
    local state_health_status
    local state_status

    docker_inspect_json_output=$(sudo docker inspect "$docker_name" 2>/dev/null)

    # Parse JSON data (quote the result string using -r)
    state_health_status=$(echo "$docker_inspect_json_output" | jq -r '.[0].State.Health.Status')
    state_status=$(echo "$docker_inspect_json_output" | jq -r '.[0].State.Status')

    echo "$state_health_status"
    echo "$state_status"
}

send_pushover_notification() {
    local message="$1"

    # Run curl command and check if it failed
    if ! curl_output=$(curl -s \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "message=$message" \
        --form-string "html=1" \
        https://api.pushover.net/1/messages.json); then

        echo "Error curl command failed: $curl_output"
        return 1
    fi

    return 0
}
