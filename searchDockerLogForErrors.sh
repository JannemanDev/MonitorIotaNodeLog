#!/bin/bash

# Check if the settings file exists
SETTINGS_FILE="settings.conf"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Error: Settings file $SETTINGS_FILE does not exist."
    exit 1
fi

# Source the settings from the configuration file
source "$SETTINGS_FILE"

# Check if a time window parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <time_window> [default_answer]"
    echo "Time window format: <number>[s|m|h|d] (seconds, minutes, hours, days)"
    echo "Optional default_answer: enter/y/Y for yes, anything else for no"
    exit 1
fi

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

# Parse the time window parameter
time_window="$1"
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

# Retrieve logs for the specified time window
sudo docker logs "$DOCKER_CONTAINER_NAME" --since "$start_time" > "$TMP_DIR/latestLog.txt"

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

# Show the number of lines in errors3.txt
line_count=$(wc -l < "$TMP_DIR/errors4.txt")
echo "Number of unique errors found for this round in the docker log since $start_time is $line_count"

# Check if a default answer is provided
default_answer="$2"

# Prompt to show the output or use the default answer
if [ -z "$default_answer" ]; then
    read -p "Do you want to display these unique errors? (enter or y or Y for yes, anything else for no): " response
else
    response="$default_answer"
fi

if [[ "$response" =~ ^(y|Y|)$ ]]; then
    format_lines "$TMP_DIR/errors4.txt"
fi
