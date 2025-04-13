#!/usr/bin/env bash
#
# BSSG - Theme Management Script
# Cross-platform compatible (Linux, macOS, FreeBSD, OpenBSD, NetBSD)
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

# Get script directory in a more compatible way
if [ -z "${BASH_VERSION:-}" ]; then
  # For POSIX shells without BASH_SOURCE
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
else
  # For Bash
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

# Set the theme directory first
THEME_DIR="$SCRIPT_DIR/../themes"
CSS_DIR="$SCRIPT_DIR/../output/css"

# Get the theme name from the config
current_theme=${THEME:-"default"}

# Support for random theme selection
if [ "$current_theme" = "random" ]; then
    # Get a list of all themes
    available_themes=()
    
    # Use a more reliable method to get available themes
    while IFS= read -r theme_dir; do
        if [ -d "$theme_dir" ] && [ -f "$theme_dir/style.css" ]; then
            theme_name=$(basename "$theme_dir")
            available_themes+=("$theme_name")
        fi
    done < <(find "$THEME_DIR" -mindepth 1 -maxdepth 1 -type d)
    
    # Make sure we found some themes
    if [ ${#available_themes[@]} -eq 0 ]; then
        echo "No themes found, using default"
        current_theme="default"
    else
        # Select a random theme from the list
        # Use a more portable method for generating random numbers
        if command -v shuf &> /dev/null; then
            # If shuf is available (Linux)
            random_index=$(shuf -i 0-$((${#available_themes[@]} - 1)) -n 1)
        else
            # Fallback to RANDOM for bash or a date-based method for POSIX
            if [ -n "$BASH_VERSION" ]; then
                random_index=$((RANDOM % ${#available_themes[@]}))
            else
                # POSIX-compatible way to get a random number using date
                random_index=$(($(date +%s) % ${#available_themes[@]}))
            fi
        fi
        
        current_theme=${available_themes[$random_index]}
        echo "Randomly selected theme: $current_theme"
    fi
fi

# Create theme-specific variables for templates
# Use posix compatible arrays
theme_variables=""
theme_variables="$theme_variables theme_${current_theme}:true"
theme_variables="$theme_variables theme_is_${current_theme}:true"

# Current time for BlackBerry status bar - use more portable date command
current_time=$(date +"%H:%M")
theme_variables="$theme_variables current_time:$current_time"

# Ensure CSS directory exists
mkdir -p "$CSS_DIR"

# Function to update the CSS file based on the selected theme
update_css() {
    echo "Theme CSS updated!"
    echo "Theme '${current_theme}' applied!"
    cp "${THEME_DIR}/${current_theme}/style.css" "${CSS_DIR}/style.css"
}

# Export theme variables as JSON in a more portable way
export_theme_variables() {
    local json="{"
    # Process space-separated list of key:value pairs
    for pair in $theme_variables; do
        key="${pair%%:*}"
        value="${pair#*:}"
        
        # Quote string values, leave boolean values as-is
        if [ "$value" = "true" ] || [ "$value" = "false" ]; then
            json="${json}\"$key\":${value},"
        else
            json="${json}\"$key\":\"${value}\","
        fi
    done
    
    # Remove trailing comma if there are elements
    if [ "$json" != "{" ]; then
        json=$(echo "$json" | sed 's/,$//')
    fi
    json="${json}}"
    echo "$json"
}

# If this script is sourced, just define the functions
# If executed directly, update the CSS
if [ "${0##*/}" = "theme.sh" ] || [ "${0##*/}" = "$(basename "$0")" ]; then
    update_css
fi 
