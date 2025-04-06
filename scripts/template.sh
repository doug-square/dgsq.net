#!/usr/bin/env bash
#
# BSSG - Template Processing Script
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

# Source the theme script to get theme variables
. "$SCRIPT_DIR/theme.sh"

# Prepare template variables in a POSIX-compatible way
prepare_template_variables() {
    # Use space-separated list of variables
    variables=""
    
    # Basic site information
    variables="$variables site_name:$SITE_NAME"
    variables="$variables site_description:$SITE_DESCRIPTION"
    variables="$variables site_url:$SITE_URL"
    variables="$variables author_name:$AUTHOR_NAME"
    variables="$variables author_email:$AUTHOR_EMAIL"
    
    # Current date - use portable date command
    current_year=$(date +%Y)
    current_date=$(date +'%Y-%m-%d')
    variables="$variables current_year:$current_year"
    variables="$variables current_date:$current_date"
    
    # Archives link
    if [ "$ENABLE_ARCHIVES" = "true" ]; then
        variables="$variables enable_archives:true"
    fi
    
    # Add all theme variables from theme.sh
    variables="$variables $theme_variables"
    
    echo "$variables"
}

# Replace template variables with their values
process_template() {
    local template="$1"
    local variables="$2"
    local output="$template"
    
    # Replace variables - use for loop instead of array iteration
    for var in $variables; do
        key="${var%%:*}"
        value="${var#*:}"
        
        # Handle boolean values for conditionals using POSIX-compatible patterns
        if [ "$value" = "true" ]; then
            # Replace {{#key}}content{{/key}} with content using sed
            output=$(echo "$output" | sed "s|{{#$key}}|OPEN_$key|g")
            output=$(echo "$output" | sed "s|{{/$key}}|CLOSE_$key|g")
            output=$(echo "$output" | sed "s|OPEN_$key\(.*\)CLOSE_$key|\1|g")
            
            # Replace {{^key}}content{{/key}} with nothing
            output=$(echo "$output" | sed "s|{{^$key}}|OPEN_NOT_$key|g")
            output=$(echo "$output" | sed "s|{{/$key}}|CLOSE_NOT_$key|g")
            output=$(echo "$output" | sed "s|OPEN_NOT_$key.*CLOSE_NOT_$key||g")
        elif [ "$value" = "false" ]; then
            # Replace {{#key}}content{{/key}} with nothing
            output=$(echo "$output" | sed "s|{{#$key}}|OPEN_$key|g")
            output=$(echo "$output" | sed "s|{{/$key}}|CLOSE_$key|g")
            output=$(echo "$output" | sed "s|OPEN_$key.*CLOSE_$key||g")
            
            # Replace {{^key}}content{{/key}} with content
            output=$(echo "$output" | sed "s|{{^$key}}|OPEN_NOT_$key|g")
            output=$(echo "$output" | sed "s|{{/$key}}|CLOSE_NOT_$key|g")
            output=$(echo "$output" | sed "s|OPEN_NOT_$key\(.*\)CLOSE_NOT_$key|\1|g")
        else
            # Replace {{key}} with value
            output=$(echo "$output" | sed "s|{{$key}}|$value|g")
        fi
    done
    
    echo "$output"
}

# If this script is executed directly, show a message
if [ "${0##*/}" = "template.sh" ] || [ "${0##*/}" = "$(basename "$0")" ]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi 
