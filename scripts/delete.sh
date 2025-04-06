#!/usr/bin/env bash
#
# BSSG - Post Delete Script
# Delete existing blog posts
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

# Function to delete a post
delete_post() {
    local post_file=""
    local force_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                force_mode=true
                shift
                ;;
            *)
                post_file="$1"
                shift
                ;;
        esac
    done
    
    # Check if post file is provided
    if [ -z "$post_file" ]; then
        echo -e "${RED}Error: No post file specified${NC}"
        echo -e "Usage: $0 [-f|--force] <post_file>"
        exit 1
    fi
    
    # Check if file exists
    if [ ! -f "$post_file" ]; then
        echo -e "${RED}Error: Post file '$post_file' not found${NC}"
        exit 1
    fi
    
    # Confirm deletion unless force mode is enabled
    if [ "$force_mode" = false ]; then
        echo -e "${YELLOW}Are you sure you want to delete '$post_file'? (y/N)${NC}"
        read -r confirm
        
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${GREEN}Deletion cancelled.${NC}"
            exit 0
        fi
    fi
    
    # Create a backup of the file
    mkdir -p "backup"
    cp "$post_file" "backup/$(basename "$post_file").$(date +%Y%m%d%H%M%S).bak"
    
    # Delete the file
    rm "$post_file"
    
    echo -e "${GREEN}Post deleted: $post_file (backup created in 'backup' directory)${NC}"
    
    # Build site
    echo -e "${GREEN}Building site...${NC}"
    ./scripts/build.sh
    
    echo -e "${GREEN}Done.${NC}"
}

# Run the delete post function
delete_post "$@" 