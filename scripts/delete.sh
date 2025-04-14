#!/usr/bin/env bash
#
# BSSG - Post Delete Script
# Delete existing blog posts
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# Load configuration (DEPRECATED - Handled centrally by bssg.sh sourcing config_loader.sh)
# CONFIG_FILE="config.sh"
# if [ -f "$CONFIG_FILE" ]; then
#     source "$CONFIG_FILE"
# else
#     echo "Error: Configuration file '$CONFIG_FILE' not found"
#     exit 1
# fi

# Load local configuration overrides if they exist (DEPRECATED - Handled centrally)
# LOCAL_CONFIG_FILE="config.sh.local"
# if [ -f "$LOCAL_CONFIG_FILE" ]; then
#     source "$LOCAL_CONFIG_FILE"
# fi

# Terminal colors (DEPRECATED - Handled centrally by config_loader.sh)
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[0;33m'
# NC='\033[0m' # No Color

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
    
    # Get the absolute path *before* deleting the file
    local absolute_file_path
    absolute_file_path=$(realpath "$post_file")

    # Create a backup of the file
    mkdir -p "backup"
    cp "$post_file" "backup/$(basename "$post_file").$(date +%Y%m%d%H%M%S).bak"
    
    # Delete the file
    rm "$post_file"
    
    echo -e "${GREEN}Post deleted: $post_file (backup created in 'backup' directory)${NC}"
    
    # Determine if the deleted file was a published post or page for build flags
    local build_command="./scripts/build/main.sh"
    local src_dir_path
    local pages_dir_path
    src_dir_path=$(realpath "$SRC_DIR")
    pages_dir_path=$(realpath "$PAGES_DIR")

    # Check if the deleted file was inside the src or pages directory
    if [[ "${absolute_file_path#$src_dir_path/}" != "$absolute_file_path" ]] || \
       [[ "${absolute_file_path#$pages_dir_path/}" != "$absolute_file_path" ]]; then
        echo "Deleted file was a published post or page. Rebuilding with --clean-output and --force-rebuild..."
        build_command+=" --clean-output --force-rebuild"
    else
        echo "Deleted file was not published (likely a draft). Rebuilding normally..."
    fi

    # Build site using the determined command
    if ! $build_command; then
        echo -e "${RED}Error: Failed to rebuild the site after deleting the post.${NC}"
        exit 1 # Exit if build fails
    fi

    echo -e "${GREEN}Site rebuilt successfully after deleting '$post_file'.${NC}"
}

# Run the delete post function
delete_post "$@" 
