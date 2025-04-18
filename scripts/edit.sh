#!/usr/bin/env bash
#
# BSSG - Post Edit Script
# Edit existing blog posts
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

# Flag to track if vi is used as fallback
VI_FALLBACK=false

# Check if EDITOR is set, otherwise default to nano or vi
# Use inherited color variables (e.g. $YELLOW, $NC)
if [ -z "$EDITOR" ]; then
    if command -v nano &> /dev/null; then
        echo -e "${YELLOW}EDITOR environment variable not set. Using nano as default.${NC}" # Use inherited vars
        EDITOR="nano"
    elif command -v vi &> /dev/null; then
        echo -e "${YELLOW}EDITOR environment variable not set and nano not found. Using vi as default.${NC}" # Use inherited vars
        EDITOR="vi"
        VI_FALLBACK=true
    else
        echo -e "${RED}Error: EDITOR environment variable not set, and neither nano nor vi could be found.${NC}" # Use inherited vars
        exit 1
    fi
fi

# Check OS type for sed compatibility
sed_inplace_arg=""
sed_requires_backup_cleanup=false
if [[ "$(uname)" == "Linux" ]]; then
    sed_inplace_arg="-i" # GNU sed: -i without arg
else
    # BSD sed: -i with extension immediately following
    sed_inplace_arg="-i.bak"
    sed_requires_backup_cleanup=true
fi

# Function to generate a slug from a title
generate_slug() {
    local title="$1"
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# Function to edit a post
edit_post() {
    local rename_mode=false
    local post_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--new-name)
                rename_mode=true
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
        echo -e "Usage: $0 [-n|--new-name] <post_file>"
        exit 1
    fi
    
    # Check if file exists
    if [ ! -f "$post_file" ]; then
        echo -e "${RED}Error: Post file '$post_file' not found${NC}"
        exit 1
    fi
    
    # Store the original filename
    local original_file="$post_file"
    
    # Update lastmod timestamp before editing
    local current_datetime
    current_datetime=$(date +"%Y-%m-%d %H:%M:%S %z")
    
    echo -e "${YELLOW}Updating lastmod timestamp to $current_datetime...${NC}"
    
    # Determine file type based on extension
    file_ext="${post_file##*.}"

    # Use sed to update the lastmod line/meta tag based on file type
    case "$file_ext" in
        md)
            # Check if lastmod line exists before trying to replace it
            if grep -q "^lastmod:" "$post_file"; then
                sed "$sed_inplace_arg" "s/^lastmod:.*/lastmod: $current_datetime/" "$post_file" && \
                if [ "$sed_requires_backup_cleanup" = true ]; then rm -f "$post_file.bak"; fi
            else
                echo "DEBUG: lastmod line not found in $post_file, skipping update." >&2 # Debug
            fi
            ;;
        html)
            # Check if lastmod meta tag exists before trying to replace it
            if grep -q '<meta name="lastmod"' "$post_file"; then
                sed "$sed_inplace_arg" "s|<meta name=\"lastmod\" content=\".*\"\>|<meta name=\"lastmod\" content=\"$current_datetime\"\>|" "$post_file" && \
                if [ "$sed_requires_backup_cleanup" = true ]; then rm -f "$post_file.bak"; fi
            else
                echo "DEBUG: lastmod meta tag not found in $post_file, skipping update." >&2 # Debug
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown file type for '$post_file'. Cannot automatically update lastmod.${NC}"
            ;;
    esac
    
    # If vi is the fallback, show the easter egg message and wait for user
    if [ "$VI_FALLBACK" = true ]; then
        local vi_message="Looks like you're using vi because nano wasn't around. Don't panic!\nTo save and exit: Press Esc, then type :wq and press Enter.\nTo exit without saving: Press Esc, then type :q! and press Enter.\nGood luck!"
        echo -e "${YELLOW}${vi_message}${NC}"
        read -p "Press Enter to open the file in vi..." </dev/tty
    fi
    
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
            
            # Determine the directory path based on the original file location
            local dir_path
            local original_dir
            original_dir=$(dirname "$post_file")

            # Normalize paths for comparison (remove trailing slashes if any)
            local src_dir_norm=${SRC_DIR%/}
            local drafts_dir_norm=${DRAFTS_DIR%/}
            local pages_dir_norm=${PAGES_DIR%/}
            local drafts_pages_dir_norm=${DRAFTS_DIR%/}/pages
            original_dir_norm=${original_dir%/}

            # Check against normalized paths
            if [[ "$original_dir_norm" == "$src_dir_norm" ]]; then
                dir_path="$SRC_DIR"
            elif [[ "$original_dir_norm" == "$drafts_dir_norm" ]]; then
                dir_path="$DRAFTS_DIR"
            elif [[ "$original_dir_norm" == "$pages_dir_norm" ]]; then
                dir_path="$PAGES_DIR"
            elif [[ "$original_dir_norm" == "$drafts_pages_dir_norm" ]]; then
                dir_path="$DRAFTS_DIR/pages"
            else
                # If not in a standard directory, use the original directory
                dir_path="$original_dir"
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
    
    echo -e "${GREEN}File saved: $post_file${NC}"
    
    # Build site if REBUILD_AFTER_EDIT is true
    if [ "$REBUILD_AFTER_EDIT" = true ]; then
        echo "Rebuilding the site (REBUILD_AFTER_EDIT=true)..."
        if ! ./scripts/build/main.sh; then
            echo -e "${RED}Error: Failed to rebuild the site after editing the post.${NC}"
            # Consider exiting or just warning
            exit 1
        fi
        echo -e "${GREEN}Site rebuilt successfully.${NC}"
    else
        echo -e "${YELLOW}Rebuild skipped (REBUILD_AFTER_EDIT=false).${NC}"
    fi
}

# Run the edit post function
edit_post "$@" 
