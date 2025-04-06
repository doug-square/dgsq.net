#!/usr/bin/env bash
#
# BSSG - Post Edit Script
# Edit existing blog posts
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

# Check if EDITOR is set
if [ -z "$EDITOR" ]; then
    echo -e "${YELLOW}EDITOR environment variable not set. Using nano as default.${NC}"
    EDITOR="nano"
fi

# Function to generate a slug from a title
generate_slug() {
    local title="$1"
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# Function to edit a post
edit_post() {
    local rename_mode=false
    local full_mode=false
    local post_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--new-name)
                rename_mode=true
                shift
                ;;
            -f|--full)
                full_mode=true
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
        echo -e "Usage: $0 [-n|--new-name] [-f|--full] <post_file>"
        exit 1
    fi
    
    # Check if file exists
    if [ ! -f "$post_file" ]; then
        echo -e "${RED}Error: Post file '$post_file' not found${NC}"
        exit 1
    fi
    
    # Get original timestamp for preserving file modification time
    local original_timestamp
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]]; then
        # macOS or FreeBSD
        original_timestamp=$(stat -f "%m" "$post_file")
    else
        # Linux and others
        original_timestamp=$(stat -c "%Y" "$post_file")
    fi
    
    # Store the original filename
    local original_file="$post_file"
    
    # Edit the file
    $EDITOR "$post_file"
    
    if [ "$?" -ne 0 ]; then
        echo -e "${RED}Error: Failed to edit file${NC}"
        exit 1
    fi
    
    # If rename mode is enabled, rename the file based on new title
    if [ "$rename_mode" = true ]; then
        local new_title=""
        local new_date=""
        
        # Extract title and date based on file extension
        if [[ "$post_file" == *.md ]]; then
            new_title=$(grep -m 1 "^title:" "$post_file" | cut -d ':' -f 2- | sed 's/^ *//' | tr -d \'\"\')
            new_date=$(grep -m 1 "^date:" "$post_file" | cut -d ':' -f 2- | sed 's/^ *//')
        elif [[ "$post_file" == *.html ]]; then
            new_title=$(grep -m 1 "<title>" "$post_file" | sed -e 's/<title>//' -e 's/<\/title>//' | sed 's/^ *//' | tr -d \'\"\')
            new_date=$(grep -m 1 'content="[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}"' "$post_file" | sed 's/.*content="\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)".*/\1/')
        fi
        
        # If no date found, use current date
        if [ -z "$new_date" ]; then
            new_date=$(date +"%Y-%m-%d %H:%M:%S %z")
        fi
        
        # If title found, rename the file
        if [ -n "$new_title" ]; then
            local new_slug
            new_slug=$(generate_slug "$new_title")
            
            local extension="${post_file##*.}"
            local new_filename="$new_date-$new_slug.$extension"
            
            # Determine if original file is in src or drafts directory
            local dir_path
            if [[ "$post_file" == src/* ]]; then
                dir_path="src"
            elif [[ "$post_file" == drafts/* ]]; then
                dir_path="drafts"
            else
                # If not in either, use same directory as original
                dir_path="$(dirname "$post_file")"
            fi
            
            local new_path="$dir_path/$new_filename"
            
            # Rename the file
            if [ "$new_path" != "$post_file" ]; then
                mv "$post_file" "$new_path"
                echo -e "${GREEN}Renamed to: $new_path${NC}"
                post_file="$new_path"
            fi
        else
            echo -e "${YELLOW}Could not extract title from file, not renaming.${NC}"
        fi
    fi
    
    # Restore the original timestamp
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]]; then
        # macOS or FreeBSD
        touch -t $(date -r "$original_timestamp" +"%Y%m%d%H%M.%S") "$post_file"
    else
        # Linux and other Unix-like systems
        touch --date="@$original_timestamp" "$post_file"
    fi
    
    echo -e "${GREEN}File saved: $post_file${NC}"
    
    # Build site
    echo -e "${GREEN}Building site...${NC}"
    ./scripts/build.sh
}

# Run the edit post function
edit_post "$@" 