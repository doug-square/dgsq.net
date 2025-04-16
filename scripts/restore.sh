#!/usr/bin/env bash
#
# BSSG - Restore Script
# Restore blog posts, pages, and configuration from backups
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

# This script RELIES on environment variables set by config_loader.sh
# It should be called via the main bssg.sh script.

set -e

# Source utilities needed for logging (ensure they are available)
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

# Check essential variables are set
: "${CONFIG_FILE:?Error: CONFIG_FILE environment variable not set. Run via bssg.sh}"
: "${SRC_DIR:?Error: SRC_DIR environment variable not set. Run via bssg.sh}"
: "${BACKUP_DIR:?Error: BACKUP_DIR environment variable not set. Run via bssg.sh}"
: "${LOCAL_CONFIG_FILE:?Error: LOCAL_CONFIG_FILE environment variable not set. Run via bssg.sh}"

# Ensure the backup directory exists (though listing/restore might fail naturally)
mkdir -p "$BACKUP_DIR"

# Function to restore from a backup
restore_backup() {
    local backup_filepath="$1"
    shift # Remove backup file path from arguments
    local restore_content=true
    local restore_config=true

    # Parse remaining arguments for flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-content)
                restore_content=false
                print_info "Will skip restoring content (src, drafts, pages)."
                shift
                ;;
            --no-config)
                restore_config=false
                print_info "Will skip restoring config files (config.sh, config.sh.local)."
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # If both flags are set, nothing to do
    if ! $restore_content && ! $restore_config; then
        print_warning "Both --no-content and --no-config specified. Nothing to restore."
        exit 0
    fi

    # Check if backup file exists
    if [ ! -f "$backup_filepath" ]; then
        print_error "Backup file '$backup_filepath' not found."
        exit 1
    fi

    # Confirm restoration
    print_warning "About to restore from: $(basename "$backup_filepath")"
    echo "Restore components:"
    $restore_content && echo -e "  ${GREEN}[X] Content (src, drafts, pages)${NC}" || echo -e "  ${RED}[ ] Content (skipped)${NC}"
    $restore_config && echo -e "  ${GREEN}[X] Configuration Files${NC}" || echo -e "  ${RED}[ ] Configuration Files (skipped)${NC}"
    echo -e "${YELLOW}This will overwrite existing files! Are you sure? (y/N)${NC}"
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_success "Restoration cancelled."
        exit 0
    fi

    # Create temporary directory for extraction
    local temp_dir
    temp_dir=$(mktemp -d)
    # Ensure temp dir is cleaned up on exit
    trap 'rm -rf "$temp_dir"' EXIT

    # Extract backup to temporary directory
    print_info "Extracting backup to temporary directory..."
    if ! tar -xzf "$backup_filepath" -C "$temp_dir"; then
        print_error "Failed to extract backup archive '$backup_filepath'."
        exit 1
    fi
    print_success "Extraction complete."

    # --- Pre-restore backup --- (Simplified: Backup the things we MIGHT overwrite)
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local pre_restore_backup_file="${BACKUP_DIR}/pre_restore_backup_${timestamp}.tar.gz"
    local pre_restore_items=()
    print_info "Creating pre-restore backup of potentially overwritten files..."

    if $restore_config; then
        [ -f "$CONFIG_FILE" ] && pre_restore_items+=("$CONFIG_FILE")
        [ -f "$LOCAL_CONFIG_FILE" ] && pre_restore_items+=("$LOCAL_CONFIG_FILE")
    fi
    if $restore_content; then
        [ -d "$SRC_DIR" ] && pre_restore_items+=("$SRC_DIR")
        [ -n "${DRAFTS_DIR:-}" ] && [ -d "$DRAFTS_DIR" ] && pre_restore_items+=("$DRAFTS_DIR")
        # Only add PAGES_DIR if it exists and is outside SRC_DIR (avoid duplication)
        if [ -n "${PAGES_DIR:-}" ] && [ -d "$PAGES_DIR" ]; then
             local pages_path_relative_to_src
             pages_path_relative_to_src=$(realpath --relative-to="$SRC_DIR" "$PAGES_DIR" 2>/dev/null || echo "")
             if [[ -z "$pages_path_relative_to_src" || "$pages_path_relative_to_src" == ".." || "$pages_path_relative_to_src" == ../* ]]; then
                  pre_restore_items+=("$PAGES_DIR")
             fi
        fi
    fi

    if [ ${#pre_restore_items[@]} -gt 0 ]; then
        if tar -czf "$pre_restore_backup_file" "${pre_restore_items[@]}"; then
            print_success "Pre-restore backup created: $pre_restore_backup_file"
        else
            print_warning "Failed to create pre-restore backup."
            # Optionally ask user if they want to continue? For now, just warn.
        fi
    else
        print_info "Nothing to create pre-restore backup for."
    fi 

    # --- Restore files --- 
    print_info "Starting restore process..."

    # Restore configuration files
    if $restore_config; then
        # Config files are expected at the root of the archive
        local temp_config_file="$temp_dir/$(basename "$CONFIG_FILE")"
        local temp_local_config_file="$temp_dir/$(basename "$LOCAL_CONFIG_FILE")"
        
        if [ -f "$temp_config_file" ]; then
            print_info "Restoring $CONFIG_FILE..."
            # Ensure target directory exists (might be outside project root in complex configs)
            mkdir -p "$(dirname "$CONFIG_FILE")"
            cp -a "$temp_config_file" "$CONFIG_FILE"
        else
            print_warning "Config file '$(basename "$CONFIG_FILE")' not found in backup archive, skipping."
        fi
        
        if [ -f "$temp_local_config_file" ]; then
            print_info "Restoring $LOCAL_CONFIG_FILE..."
            mkdir -p "$(dirname "$LOCAL_CONFIG_FILE")"
            cp -a "$temp_local_config_file" "$LOCAL_CONFIG_FILE"
        else
            # This is less critical, might not exist
            print_info "Local config file '$(basename "$LOCAL_CONFIG_FILE")' not found in backup archive, skipping."
        fi
    fi

    # Restore content directories
    if $restore_content; then
        # Restore SRC_DIR (expects a directory named like SRC_DIR in the archive)
        local src_basename
        src_basename=$(basename "$SRC_DIR")
        local temp_src_path="$temp_dir/$src_basename"
        if [ -e "$temp_src_path" ]; then # Use -e to check for file or directory
            print_info "Restoring content to $SRC_DIR..."
            # Remove existing content first
            rm -rf "${SRC_DIR:?}"
            # Ensure parent directory exists
            mkdir -p "$(dirname "$SRC_DIR")"
            # Copy the directory from the archive
            cp -a "$temp_src_path" "$SRC_DIR"
        else
            print_warning "Source directory/content '$src_basename' not found in backup archive."
        fi
            
        # Restore DRAFTS_DIR (if defined and exists in backup)
        if [ -n "${DRAFTS_DIR:-}" ]; then
            local drafts_basename
            drafts_basename=$(basename "$DRAFTS_DIR")
            local temp_drafts_path="$temp_dir/$drafts_basename"
            if [ -e "$temp_drafts_path" ]; then
                print_info "Restoring drafts to $DRAFTS_DIR..."
                rm -rf "${DRAFTS_DIR:?}"
                mkdir -p "$(dirname "$DRAFTS_DIR")"
                cp -a "$temp_drafts_path" "$DRAFTS_DIR"
            else
                print_info "Drafts directory '$drafts_basename' not found in backup archive, skipping."
            fi
        fi

        # Restore PAGES_DIR (if defined and exists in backup)
        if [ -n "${PAGES_DIR:-}" ]; then
            local pages_basename
            pages_basename=$(basename "$PAGES_DIR")
            local temp_pages_path="$temp_dir/$pages_basename"
            # Avoid restoring if it's the same path as SRC_DIR (already handled)
            if [[ "$SRC_DIR" != "$PAGES_DIR" ]] && [ -e "$temp_pages_path" ]; then 
                print_info "Restoring pages to $PAGES_DIR..."
                rm -rf "${PAGES_DIR:?}"
                mkdir -p "$(dirname "$PAGES_DIR")"
                cp -a "$temp_pages_path" "$PAGES_DIR"
            elif [ -e "$temp_pages_path" ]; then
                print_info "Pages directory '$pages_basename' is same as source directory, already restored."
            else
                print_info "Pages directory '$pages_basename' not found in backup archive, skipping."
            fi
        fi
    fi

    # Clean up temporary directory (redundant due to trap, but safe)
    rm -rf "$temp_dir"
    trap - EXIT # Remove trap

    # Build site only if content was restored
    if $restore_content; then
        print_success "Rebuilding site with restored content..."
        # Assume build script is accessible relative to main script dir or via PATH
        local build_script="${SCRIPT_DIR}/scripts/build/main.sh"
        if [ -x "$build_script" ]; then
             "$build_script"
        else
             print_error "Build script '$build_script' not found or not executable. Cannot rebuild site."
        fi
    else
        print_info "Skipping site rebuild as content was not restored."
    fi

    print_success "Restoration completed successfully."
}

# Function to list available backups (Copied from backup.sh, ensure consistency)
list_backups() {
    print_info "Available backups in ${BACKUP_DIR}:${NC}"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_error "No backups found.${NC}"
        return 0
    fi

    echo -e "ID\tDate\t\tTime\t\tSize\t\tFile"
    echo -e "--\t----\t\t----\t\t----\t\t----"

    local counter=1
    find "$BACKUP_DIR" -maxdepth 1 -name 'bssg_*.tar.gz' -printf '%T@ %p\n' | \
        sort -nr | \
        cut -d' ' -f2- | \
        while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename
            filename=$(basename "$file")
            local date_part=""
            local time_part=""

            if [[ "$filename" =~ bssg_backup_([0-9]{8})([0-9]{6})\.tar\.gz ]]; then
                date_part="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
                time_part="${BASH_REMATCH[2]:0:2}:${BASH_REMATCH[2]:2:2}:${BASH_REMATCH[2]:4:2}"
            elif [[ "$filename" =~ bssg_daily_([0-9]{8})\.tar\.gz ]]; then
                date_part="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
                time_part="Daily"
            else
                date_part="Unknown"
                time_part="Format"
            fi

            local size
            size=$(du -h "$file" | cut -f1)
            printf "%s\t%s\t%s\t%s\t%s\n" "$counter" "$date_part" "$time_part" "$size" "$filename"
            counter=$((counter + 1))
        fi
    done
}

# Main function
main() {
    # Check if we're listing backups
    if [ "$1" = "list" ]; then
        list_backups
        exit 0
    fi

    local backup_target="$1"
    local backup_filepath=""

    if [ -z "$backup_target" ]; then
        print_info "No backup specified, attempting to use the latest timestamped backup."
        # Find the latest bssg_backup_*.tar.gz file using portable ls -t
        backup_filepath=$(ls -t "${BACKUP_DIR}"/bssg_backup_*.tar.gz 2>/dev/null | head -n 1)
        if [ -z "$backup_filepath" ]; then
            print_error "No timestamped backups found in $BACKUP_DIR."
            exit 1
        fi
    elif [[ "$backup_target" =~ ^[0-9]+$ ]]; then
        local backup_id=$backup_target
        # Find the nth backup file (1-based index) using portable ls -t and sed
        # Note: sed index is 1-based
        backup_filepath=$(ls -t "${BACKUP_DIR}"/bssg_backup_*.tar.gz 2>/dev/null | sed -n "${backup_id}p")
        if [ -z "$backup_filepath" ]; then
            print_error "Invalid backup ID: $backup_id. Use './bssg backups' to see available IDs."
            exit 1
        fi
        shift # Shift off the ID
    else
        # Assume it's a filename (relative to BACKUP_DIR or full path)
        if [[ "$backup_target" == */* ]]; then 
            # Looks like a path
            backup_filepath="$backup_target"
        else 
            # Assume filename within BACKUP_DIR
            backup_filepath="${BACKUP_DIR}/${backup_target}"
        fi
        if [ ! -f "$backup_filepath" ]; then
             print_error "Backup file not found: '$backup_filepath'"
             exit 1
        fi
        shift # Shift off the filename
    fi

    # Pass the resolved filepath and remaining flags to restore_backup
    restore_backup "$backup_filepath" "$@"

}

# Run the main function
main "$@" 