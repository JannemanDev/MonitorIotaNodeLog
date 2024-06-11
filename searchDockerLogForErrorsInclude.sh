source common_functions.sh

usage() {
    echo "Usage: $0 [-t <time_window>] [-d default_answer] [-f use_docker_log_file_as_input]"
    echo "Time window format          (optional): <number>[s|m|h|d] (seconds, minutes, hours, days)"
    echo "Default answer              (optional): enter/y/Y for yes, anything else for no"
    echo "Use Docker logfile as input (optional): path to the log file"
  # echo "Usage: $0 -t <time_window_first_round> -l <loop_frequency>"
  # echo "Loop frequency format (required): <number>[s|m|h|d] (seconds, minutes, hours, days)"
  # echo "Time window format    (optional): <number>[s|m|h|d] (seconds, minutes, hours, days)"
}

searchDockerLogForErrors() {
    # Check if the settings file exists
    SETTINGS_FILE="settings.conf"
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "Error: Settings file $SETTINGS_FILE does not exist."
        exit 1
    fi

    echo "node_id=$node_id"
    # exit
    if [ -z "$SETTINGS_LOADED" ]; then
        echo "Loading settings"
        # Source the settings from the configuration file
        source "$SETTINGS_FILE"
    else
        echo "Settings were already loaded"
    fi

    # Initialize variables
    time_window=""
    default_answer=""
    use_docker_log_file_as_input=""
    show_help=false

    echo "params=$#"
    # Parse parameters
    while [[ $# -gt 0 ]]; do
        echo "value=$1"
        case $1 in
            -t)
                time_window=$2
                shift 2
                ;;
            -d)
                default_answer=$2
                shift 2
                ;;
            -f)
                use_docker_log_file_as_input=$2
                shift 2
                ;;
            -h)
                show_help=true
                shift
                ;;
            *)
                echo "Invalid option: $1" >&2
                return 1
                ;;
        esac
    done

    echo "time_window=$time_window"
    echo "default_answer=$default_answer"
    echo "use_docker_log_file_as_input=$use_docker_log_file_as_input"
    echo "show_help=$show_help"
    
    # If -h option is provided, show help and exit
    if [ "$show_help" = true ]; then
        usage
        exit 0
    fi

    # Parse the time window parameter if provided
    if [ -n "$time_window" ]; then
        # Validate time format for time_window_first_round
        validate_time_format "$time_window" "time_window (-t)"

        time_format=$(echo "$time_window" | sed 's/[0-9]*//g')
        time_value=$(echo "$time_window" | sed 's/[s|m|h|d]//g')

        # Convert time window to seconds
        case "$time_format" in
            s) time_window_seconds="$time_value";;
            m) time_window_seconds="$((time_value * 60))";;
            h) time_window_seconds="$((time_value * 3600))";;
            d) time_window_seconds="$((time_value * 86400))";;
            *) echo "Invalid time format"; exit 1;;
        esac

        # Calculate the start time for log retrieval
        start_time=$(date -d "-$time_window_seconds seconds" +%Y-%m-%dT%H:%M:%S)
        start_time_epoch=$(date -d "$start_time" +%s)

        # echo "Start time: $start_time"
        # echo "Start time (epoch): $start_time_epoch"
    fi

    # Retrieve logs for the specified time window or filter the provided log file
    if [ -z "$use_docker_log_file_as_input" ]; then
        if [ -n "$time_window" ]; then
            sudo docker logs "$DOCKER_CONTAINER_NAME" --since "$start_time" > "$TMP_DIR/latestLog.txt"
        else
            sudo docker logs "$DOCKER_CONTAINER_NAME" > "$TMP_DIR/latestLog.txt"
        fi
    else
        if [ -n "$time_window" ]; then
            awk -v start_time_epoch="$start_time_epoch" '
            function to_epoch(datetime) {
                gsub(/T|Z/, " ", datetime)          # Replace T and Z with spaces
                datetime = substr(datetime, 1, 19)  # Ensure the format YYYY-MM-DD HH:MM:SS
                gsub(/-/, " ", datetime)            # Replace - with spaces
                gsub(/:/, " ", datetime)            # Replace : with spaces
                return mktime(datetime)
            }
            BEGIN {
                found = 0
            }
            {
                if (!found) {
                    match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/)
                    if (RSTART != 0) {
                        log_time = substr($0, RSTART, RLENGTH)
                        log_time_epoch = to_epoch(log_time)
                        if (log_time_epoch >= start_time_epoch) {
                            found = 1
                        }
                    }
                }
                if (found) {
                    print
                }
            }
            ' "$use_docker_log_file_as_input" > "$TMP_DIR/latestLog.txt"
        else
            cp "$use_docker_log_file_as_input" "$TMP_DIR/latestLog.txt"
        fi
    fi

    # Filter lines containing any of the search words (case insensitive)
    grep -iE "$(IFS='|'; echo "${SEARCH_WORDS[*]}")" "$TMP_DIR/latestLog.txt" > "$TMP_DIR/errors1.txt"

    # Apply SED patterns from the settings file
    cp "$TMP_DIR/errors1.txt" "$TMP_DIR/errors2.txt"
    for pattern in "${SED_PATTERNS[@]}"; do
        sed -i -E "$pattern" "$TMP_DIR/errors2.txt"
    done

    # All consecutive whitespace replace with one space
    sed 's/[[:space:]]\+/ /g' "$TMP_DIR/errors2.txt" > "$TMP_DIR/errors3.txt"

    # Remove duplicate lines and save to errors4.txt
    sort -u "$TMP_DIR/errors3.txt" > "$TMP_DIR/errors4.txt"

    # Show the number of lines in errors4.txt
    line_count=$(wc -l < "$TMP_DIR/errors4.txt")
    echo "Number of unique errors found for this round in the docker log since $start_time is $line_count"

    # Prompt to show the output or use the default answer
    if [ -z "$default_answer" ]; then
        read -p "Do you want to display these unique errors? (enter or y or Y for yes, anything else for no): " response
    else
        response="$default_answer"
    fi

    if [[ "$response" =~ ^(y|Y|)$ ]]; then
        format_lines "$TMP_DIR/errors4.txt"
    fi
}
