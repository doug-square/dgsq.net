#!/usr/bin/env bash
#
# BSSG - Restore Script
# Restore blog posts, pages, and configuration from backups
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# Load configuration
CONFIG_FILE="config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file '$CONFIG_FILE' not found"
    exit 1
fi

# Load local configuration overrides if they exist
LOCAL_CONFIG_FILE="config.sh.local"
if [ -f "$LOCAL_CONFIG_FILE" ]; then
    source "$LOCAL_CONFIG_FILE"
fi

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Create backup directory if it doesn't exist
mkdir -p "backup"

# Function to restore from a backup
restore_backup() {
    local backup_file=""
    local restore_posts=true
    local restore_drafts=true
    local restore_pages=true
    local restore_config=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-posts)
                restore_posts=false
                shift
                ;;
            --no-drafts)
                restore_drafts=false
                shift
                ;;
            --no-pages)
                restore_pages=false
                shift
                ;;
            --no-config)
                restore_config=false
                shift
                ;;
            *)
                backup_file="$1"
                shift
                ;;
        esac
    done
    
    # If no backup file specified, use the latest
    if [ -z "$backup_file" ]; then
        # Get the latest backup file
        backup_file=$(ls -t backup/bssg_backup_*.tar.gz 2>/dev/null | head -n 1)
    fi
    
    # Check if backup file exists
    if [ -z "$backup_file" ]; then
        echo -e "${RED}Error: No backup file found${NC}"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Backup file '$backup_file' not found${NC}"
        exit 1
    fi
    
    # Confirm restoration
    echo -e "${YELLOW}Will restore:${NC}"
    $restore_posts && echo -e "${GREEN} - Posts${NC}" || echo -e "${RED} - Posts (skipped)${NC}"
    $restore_drafts && echo -e "${GREEN} - Drafts${NC}" || echo -e "${RED} - Drafts (skipped)${NC}"
    $restore_pages && echo -e "${GREEN} - Pages${NC}" || echo -e "${RED} - Pages (skipped)${NC}"
    $restore_config && echo -e "${GREEN} - Local configuration${NC}" || echo -e "${RED} - Local configuration (skipped)${NC}"
    echo -e "${YELLOW}Are you sure you want to restore from '$backup_file'? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}Restoration cancelled.${NC}"
        exit 0
    fi
    
    # Create temporary directory for extraction
    local temp_dir=$(mktemp -d)
    
    # Extract backup to temporary directory
    echo -e "${YELLOW}Extracting backup...${NC}"
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Create a pre-restore backup of current files
    local timestamp=$(date +%Y%m%d%H%M%S)
    echo -e "${YELLOW}Creating pre-restore backup...${NC}"
    
    # Backup existing files before restoring
    if $restore_posts; then
        echo -e "${YELLOW}Backing up current posts before restoring...${NC}"
        if [ -d "$SRC_DIR" ]; then
            tar -czf "backup/pre_restore_posts_$timestamp.tar.gz" -C "$SRC_DIR" .
        fi
    fi
    
    if $restore_drafts && [ -d "drafts" ]; then
        echo -e "${YELLOW}Backing up current drafts before restoring...${NC}"
        tar -czf "backup/pre_restore_drafts_$timestamp.tar.gz" -C "drafts" .
    fi
    
    if $restore_pages && [ -d "pages" ]; then
        echo -e "${YELLOW}Backing up current pages before restoring...${NC}"
        tar -czf "backup/pre_restore_pages_$timestamp.tar.gz" -C "pages" .
    fi
    
    if $restore_config && [ -f "$LOCAL_CONFIG_FILE" ]; then
        echo -e "${YELLOW}Backing up current config.sh.local before restoring...${NC}"
        cp "$LOCAL_CONFIG_FILE" "backup/pre_restore_config_$timestamp.sh.local"
    fi
    
    # Restore files
    if $restore_posts; then
        echo -e "${YELLOW}Restoring posts...${NC}"
        rm -rf "${SRC_DIR:?}"/*
        mkdir -p "$SRC_DIR"
        # Check if there are any .md or .html files at the root of the extracted backup
        if ls "$temp_dir"/*.{md,html} >/dev/null 2>&1; then
            cp -a "$temp_dir"/*.{md,html} "$SRC_DIR"/ 2>/dev/null || true
        fi
        # Copy any directories from the extracted backup to SRC_DIR
        for dir in "$temp_dir"/*/; do
            if [ -d "$dir" ] && [[ "$(basename "$dir")" != "drafts" && "$(basename "$dir")" != "pages" ]]; then
                cp -a "$dir" "$SRC_DIR"/
            fi
        done
    fi
    
    if $restore_drafts && [ -d "$temp_dir/drafts" ]; then
        echo -e "${YELLOW}Restoring drafts...${NC}"
        rm -rf "drafts"/*
        mkdir -p "drafts"
        cp -a "$temp_dir/drafts"/* "drafts"/ 2>/dev/null || true
    fi
    
    if $restore_pages && [ -d "$temp_dir/pages" ]; then
        echo -e "${YELLOW}Restoring pages...${NC}"
        rm -rf "pages"/*
        mkdir -p "pages"
        cp -a "$temp_dir/pages"/* "pages"/ 2>/dev/null || true
    fi
    
    if $restore_config && [ -f "$temp_dir/$LOCAL_CONFIG_FILE" ]; then
        echo -e "${YELLOW}Restoring local configuration...${NC}"
        cp "$temp_dir/$LOCAL_CONFIG_FILE" "./$LOCAL_CONFIG_FILE"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    # Build site
    echo -e "${GREEN}Rebuilding site with restored content...${NC}"
    ./scripts/build.sh
    
    echo -e "${GREEN}Restoration completed successfully.${NC}"
}

# Function to list available backups
list_backups() {
    echo -e "${YELLOW}Available backups:${NC}"
    
    if [ ! -d "backup" ] || [ -z "$(ls -A backup 2>/dev/null)" ]; then
        echo -e "${RED}No backups found.${NC}"
        exit 0
    fi
    
    echo -e "ID\tDate\t\tTime\t\tSize\t\tFile"
    echo -e "--\t----\t\t----\t\t----\t\t----"
    
    local counter=1
    ls -t backup/bssg_*.tar.gz 2>/dev/null | while read -r file; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local date_part=""
            local time_part=""
            
            if [[ "$filename" =~ bssg_backup_([0-9]{8})([0-9]{6})\.tar\.gz ]]; then
                # Regular backup format
                date_part="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
                time_part="${BASH_REMATCH[2]:0:2}:${BASH_REMATCH[2]:2:2}:${BASH_REMATCH[2]:4:2}"
            elif [[ "$filename" =~ bssg_daily_([0-9]{8})\.tar\.gz ]]; then
                # Daily backup format
                date_part="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
                time_part="00:00:00"
            else
                # Unknown format, show filename
                date_part="Unknown"
                time_part="Unknown"
            fi
            
            local size=$(du -h "$file" | cut -f1)
            echo -e "$counter\t$date_part\t$time_part\t$size\t\t$filename"
            counter=$((counter + 1))
        fi
    done
}

# Main function
main() {
    local backup_file=""
    
    # Check if we're listing backups
    if [ "$1" = "list" ]; then
        list_backups
        exit 0
    fi
    
    # Parse backup file argument
    if [ -n "$1" ] && [[ ! "$1" == --* ]]; then
        # If a number is provided, get the nth backup file
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            local backup_files=($(ls -t backup/bssg_*.tar.gz 2>/dev/null))
            if [ "$1" -gt 0 ] && [ "$1" -le "${#backup_files[@]}" ]; then
                backup_file="${backup_files[$1-1]}"
                shift
            else
                echo -e "${RED}Error: Invalid backup ID.${NC}"
                exit 1
            fi
        else
            # If a filename is provided, use it directly
            backup_file="$1"
            # Add prefix if not already included
            if [[ ! "$backup_file" == backup/* ]]; then
                backup_file="backup/$backup_file"
            fi
            shift
        fi
        restore_backup "$backup_file" "$@"
    else
        restore_backup "$@"
    fi
}

# Run the main function
main "$@" 