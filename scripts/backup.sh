#!/usr/bin/env bash
#
# BSSG - Backup Script
# Backup blog posts, pages, and configuration
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

# This script RELIES on environment variables set by config_loader.sh
# It should be called via the main bssg.sh script.

set -e

# Source utilities needed for logging (ensure they are available)
# Determine the directory of the main bssg script if BSSG_SCRIPT_DIR is set
SCRIPT_DIR="${BSSG_SCRIPT_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/..}"
UTILS_SCRIPT="${SCRIPT_DIR}/scripts/build/utils.sh"

if [ -f "$UTILS_SCRIPT" ]; then
    # shellcheck source=scripts/build/utils.sh
    source "$UTILS_SCRIPT"
else
    # Minimal fallback if utils not found
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    print_error() { echo -e "${RED}Error: $1${NC}" >&2; }
    print_warning() { echo -e "${YELLOW}Warning: $1${NC}"; }
    print_success() { echo -e "${GREEN}Success: $1${NC}"; }
    print_info() { echo -e "Info: $1"; }
    print_error "Utilities script not found at '$UTILS_SCRIPT'. Using fallback logging."
fi

# Check essential variables are set (they should be exported by config_loader.sh)
: "${CONFIG_FILE:?Error: CONFIG_FILE environment variable not set. Run via bssg.sh}"
: "${SRC_DIR:?Error: SRC_DIR environment variable not set. Run via bssg.sh}"
: "${BACKUP_DIR:?Error: BACKUP_DIR environment variable not set. Run via bssg.sh}"
: "${LOCAL_CONFIG_FILE:?Error: LOCAL_CONFIG_FILE environment variable not set. Run via bssg.sh}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to backup site content and configuration
create_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local backup_filename="bssg_backup_$timestamp.tar.gz"
    local backup_filepath="${BACKUP_DIR}/${backup_filename}"

    print_info "Creating backup..."

    # Prepare list of tar options (-C dir file)
    local tar_opts=()

    # Function to safely add item to tar options
    add_item_to_backup() {
        local item_path="$1"
        local item_type="$2" # 'file' or 'dir'
        
        if [ "$item_type" == "file" ] && [ ! -f "$item_path" ]; then
            print_warning "File '$item_path' not found, skipping."
            return
        elif [ "$item_type" == "dir" ] && [ ! -d "$item_path" ]; then
            print_warning "Directory '$item_path' not found, skipping."
            return
        elif [ "$item_type" != "file" ] && [ "$item_type" != "dir" ]; then
             print_error "Internal error: Invalid item type '$item_type' for $item_path"
             return
        fi
        
        local dir
        local base
        dir=$(dirname "$item_path")
        base=$(basename "$item_path")
        tar_opts+=("-C" "$dir" "$base")
        print_info "Adding $item_type '$base' from '$dir' to backup."
    }

    # Add main config file
    add_item_to_backup "$CONFIG_FILE" "file"

    # Add local config file
    add_item_to_backup "$LOCAL_CONFIG_FILE" "file"

    # Add source directory
    add_item_to_backup "$SRC_DIR" "dir"

    # Add drafts directory (if defined)
    if [ -n "${DRAFTS_DIR:-}" ]; then
        add_item_to_backup "$DRAFTS_DIR" "dir"
    fi

    # Add pages directory (if defined)
    # Check if it's the same as SRC_DIR to avoid adding twice
    if [ -n "${PAGES_DIR:-}" ]; then
        if [[ "$(cd "$SRC_DIR" && pwd)" != "$(cd "$PAGES_DIR" && pwd)" ]]; then
             add_item_to_backup "$PAGES_DIR" "dir"
        else
             print_info "Pages directory '$PAGES_DIR' is same as source directory '$SRC_DIR', skipping duplicate add."
        fi
    fi
    
    # Check if there are items to back up
    # We check tar_opts length / 2 because each item adds two elements (-C and path)
    if [ ${#tar_opts[@]} -eq 0 ]; then
        print_error "No items found to back up. Please check configuration and file/directory existence."
        return 1
    fi

    # Create the tar archive
    print_info "Archiving items to $backup_filepath"
    # The items added via -C will be relative to the archive root
    tar -czf "$backup_filepath" "${tar_opts[@]}"

    if [ $? -eq 0 ]; then
        print_success "Backup created: $backup_filepath"
    else
        print_error "Failed to create backup archive."
        return 1
    fi

    # Manage daily backup and cleanup
    manage_backup_rotation "$backup_filepath"

    print_success "Backup process completed."
}

# Function to manage daily backups and rotation
manage_backup_rotation() {
    local latest_backup_filepath="$1"
    local today
    today=$(date +%Y%m%d)
    local daily_backup_filename="bssg_daily_$today.tar.gz"
    local daily_backup_filepath="${BACKUP_DIR}/${daily_backup_filename}"

    # Create a daily backup if it doesn't exist or if the latest is newer
    if [ ! -f "$daily_backup_filepath" ] || [ "$latest_backup_filepath" -nt "$daily_backup_filepath" ]; then
        cp "$latest_backup_filepath" "$daily_backup_filepath"
        print_success "Daily backup created/updated: $daily_backup_filepath"
    fi

    # Keep only latest 10 timestamped backups (excluding daily backups)
    print_info "Cleaning old timestamped backups (keeping latest 10)..."
    
    # Portable way to list, sort by time, skip 10 newest, and delete the rest
    # Use null delimiter with ls/tail/xargs if available (safer), otherwise newline
    local file_list
    local count=0
    
    # Count the number of backups first to avoid errors with tail if less than 11
    count=$(ls -1 "${BACKUP_DIR}"/bssg_backup_*.tar.gz 2>/dev/null | wc -l)
    
    if [ "$count" -gt 10 ]; then
        # List files sorted by modification time (newest first), get all except the first 10
        # Use process substitution to avoid issues with subshells and xargs
        # Use xargs -I {} rm -f "{}" for basic portability with spaces
        ls -t "${BACKUP_DIR}"/bssg_backup_*.tar.gz 2>/dev/null | tail -n +11 | xargs -I {} rm -f "{}"
        if [ $? -ne 0 ]; then
            print_warning "Potentially failed to clean some old backups. Please check manually."
        fi
    else
        print_info "Fewer than 11 timestamped backups found, no cleanup needed."
    fi
    
    print_info "Backup cleanup finished."
}

# Function to list available backups
list_backups() {
    print_info "Available backups in ${BACKUP_DIR}:${NC}"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_error "No backups found.${NC}"
        return 0
    fi

    echo -e "ID\tDate\t\tTime\t\tSize\t\tFile"
    echo -e "--\t----\t\t----\t\t----\t\t----"

    local counter=1
    # Use find to handle filenames safely
    find "$BACKUP_DIR" -maxdepth 1 -name 'bssg_*.tar.gz' -printf '%T@ %p\n' | \
        sort -nr | \
        cut -d' ' -f2- | \
        while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename
            filename=$(basename "$file")
            local date_part=""
            local time_part=""

            # Match timestamped backup
            if [[ "$filename" =~ bssg_backup_([0-9]{8})([0-9]{6})\.tar\.gz ]]; then
                date_part="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
                time_part="${BASH_REMATCH[2]:0:2}:${BASH_REMATCH[2]:2:2}:${BASH_REMATCH[2]:4:2}"
            # Match daily backup
            elif [[ "$filename" =~ bssg_daily_([0-9]{8})\.tar\.gz ]]; then
                date_part="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
                time_part="Daily"
            else
                date_part="Unknown"
                time_part="Format"
            fi

            local size
            size=$(du -h "$file" | cut -f1)
            # Use printf for safer, more consistent formatting
            printf "%s\t%s\t%s\t%s\t%s\n" "$counter" "$date_part" "$time_part" "$size" "$filename"
            counter=$((counter + 1))
        fi
    done
}

# Main function
main() {
    local command="backup"

    # Parse arguments
    if [ -n "$1" ]; then
        command="$1"
        shift
    fi

    case "$command" in
        backup|create)
            create_backup
            ;;
        list)
            list_backups
            ;;
        *)
            print_error "Unknown command '$command'"
            echo -e "Usage: $0 [backup|create|list]"
            exit 1
            ;;
    esac
}

# Run the main function
main "$@" 