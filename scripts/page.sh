#!/usr/bin/env bash
#
# BSSG - Page Creation Script
# Create and manage static pages
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

# Function to generate a slug from a title
generate_slug() {
    local title="$1"
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# Function to create a new page
create_page() {
    local html_mode=false
    local draft_mode=false
    local secondary_mode=false
    local draft_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -html|--html)
                html_mode=true
                shift
                ;;
            -d|--draft)
                draft_mode=true
                shift
                ;;
            -s|--secondary)
                secondary_mode=true
                shift
                ;;
            *)
                if [ -f "$1" ]; then
                    draft_file="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Create drafts directory if it doesn't exist
    mkdir -p "$DRAFTS_DIR/pages"
    
    # Create pages directory if it doesn't exist
    mkdir -p "$PAGES_DIR"
    
    # If a draft file is specified, edit it
    if [ -n "$draft_file" ]; then
        # Check if file exists
        if [ ! -f "$draft_file" ]; then
            echo -e "${RED}Error: Draft file '$draft_file' not found${NC}"
            exit 1
        fi
        
        edit_file "$draft_file"
        exit 0
    fi
    
    # Get page title
    echo -e "${YELLOW}Enter page title:${NC}"
    read -r title
    
    if [ -z "$title" ]; then
        echo -e "${RED}Error: Title cannot be empty${NC}"
        exit 1
    fi
    
    # Generate slug
    local slug
    slug=$(generate_slug "$title")
    
    # Get current date
    local date
    date=$(date +"%Y-%m-%d %H:%M:%S %z")
    
    # Create filename
    local filename="$slug"
    
    if [ "$html_mode" = true ]; then
        filename="$filename.html"
    else
        filename="$filename.md"
    fi
    
    local output_path
    if [ "$draft_mode" = true ]; then
        output_path="$DRAFTS_DIR/pages/$filename"
    else
        output_path="$PAGES_DIR/$filename"
    fi
    
    # Check if file already exists
    if [ -f "$output_path" ]; then
        echo -e "${RED}Error: File '$output_path' already exists${NC}"
        exit 1
    fi
    
    # Define the vi easter egg message with actual newlines
    local vi_message=$(cat <<-EOM
Looks like you're using vi because nano wasn't around. Don't panic!
To save and exit: Press Esc, then type :wq and press Enter.
To exit without saving: Press Esc, then type :q! and press Enter.
Good luck!

EOM
    )

    # Create template based on format
    if [ "$html_mode" = true ]; then
        local initial_content="<p>Your content here...</p>"
        if [ "$VI_FALLBACK" = true ]; then
             # Embed the message directly within pre tags
            initial_content="<pre>${vi_message}</pre>"
        fi
        cat > "$output_path" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$title</title>
    <meta name="date" content="$date">
    <meta name="lastmod" content="$date">
    <meta name="slug" content="$slug">
    <meta name="secondary" content="$([ "$secondary_mode" = true ] && echo "true" || echo "false")">
</head>
<body>
    <h1>$title</h1>
    $initial_content
</body>
</html>
EOF
    else
        local initial_content="Your content here..."
        if [ "$VI_FALLBACK" = true ]; then
            # Assign the message directly
            initial_content="$vi_message"
        fi
        cat > "$output_path" << EOF
---
title: $title
date: $date
lastmod: $date
slug: $slug
secondary: $([ "$secondary_mode" = true ] && echo "true" || echo "false")
---

$initial_content
EOF
    fi
    
    # Open in editor
    edit_file "$output_path"
    
    # Build site if not a draft
    if [ "$draft_mode" = false ]; then
        echo "New page created. Performing full site rebuild (clean + force)..."
        if ! ./scripts/build/main.sh --clean-output --force-rebuild; then
            echo -e "${RED}Error: Failed to build the site after creating the page.${NC}"
            exit 1
        fi
        echo -e "${GREEN}Page '$title' created successfully and site rebuilt.${NC}"
    else
        echo -e "${GREEN}Draft page '$title' saved successfully.${NC}"
    fi
}

# Function to edit a file
edit_file() {
    local file="$1"
    
    $EDITOR "$file"
    
    if [ "$?" -eq 0 ]; then
        echo -e "${GREEN}File saved: $file${NC}"
    else
        echo -e "${RED}Error: Failed to edit file${NC}"
        exit 1
    fi
}

# Run the create page function
create_page "$@" 
