#!/usr/bin/env bash
#
# BSSG - Backup Script
# Backup blog posts, pages, and configuration
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

# Function to backup posts
backup_posts() {
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="backup/bssg_backup_$timestamp.tar.gz"
    
    echo -e "${YELLOW}Creating backup of all posts...${NC}"
    
    # Create tar archive with all .md and .html files in src directory
    tar -czf "$backup_file" -C "$SRC_DIR" .
    
    # Also include the drafts directory if it exists
    if [ -d "drafts" ]; then
        echo -e "${YELLOW}Including drafts in backup...${NC}"
        tar -rf "${backup_file%.gz}" -C "drafts" .
        gzip -f "${backup_file%.gz}"
    fi
    
    # Also include the pages directory if it exists
    if [ -d "pages" ]; then
        echo -e "${YELLOW}Including pages in backup...${NC}"
        tar -rf "${backup_file%.gz}" -C "pages" .
        gzip -f "${backup_file%.gz}"
    fi
    
    # Also include the config.sh.local file if it exists
    if [ -f "$LOCAL_CONFIG_FILE" ]; then
        echo -e "${YELLOW}Including local configuration in backup...${NC}"
        tar -rf "${backup_file%.gz}" "$LOCAL_CONFIG_FILE"
        gzip -f "${backup_file%.gz}"
    fi
    
    echo -e "${GREEN}Backup created: $backup_file${NC}"
    
    # Create a daily backup if it doesn't exist
    local today=$(date +%Y%m%d)
    local daily_backup="backup/bssg_daily_$today.tar.gz"
    
    if [ ! -f "$daily_backup" ]; then
        cp "$backup_file" "$daily_backup"
        echo -e "${GREEN}Daily backup created: $daily_backup${NC}"
    fi
    
    # Keep only latest 10 backups
    echo -e "${YELLOW}Cleaning old backups...${NC}"
    cd backup
    ls -t bssg_backup_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null || true
    cd ..
    
    echo -e "${GREEN}Backup process completed.${NC}"
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
    local command="backup"
    
    # Parse arguments
    if [ -n "$1" ]; then
        command="$1"
        shift
    fi
    
    case "$command" in
        backup|create)
            backup_posts
            ;;
        list)
            list_backups
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            echo -e "Usage: $0 [backup|create|list]"
            exit 1
            ;;
    esac
}

# Run the main function
main "$@" 