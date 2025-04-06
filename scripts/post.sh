#!/usr/bin/env bash
#
# BSSG - Post Creation Script
# Create and manage blog posts
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

# Function to create a new post
create_post() {
    local html_mode=false
    local draft_mode=false
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
            *)
                if [ -f "$1" ]; then
                    draft_file="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Create drafts directory if it doesn't exist
    mkdir -p "drafts"
    
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
    
    # Get post title
    echo -e "${YELLOW}Enter post title:${NC}"
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
    date=$(date +%Y-%m-%d-%H-%M-%S)
    
    # Format date for display and metadata (keeping time with timezone)
    local display_date
    display_date=$(date +"%Y-%m-%d %H:%M:%S %z")
    
    # Create filename - use date without time for filename to keep it cleaner
    local filename="$(echo $date | cut -d'-' -f1-3)-$slug"
    
    if [ "$html_mode" = true ]; then
        filename="$filename.html"
    else
        filename="$filename.md"
    fi
    
    local output_path
    if [ "$draft_mode" = true ]; then
        output_path="drafts/$filename"
    else
        output_path="src/$filename"
    fi
    
    # Check if file already exists
    if [ -f "$output_path" ]; then
        echo -e "${RED}Error: File '$output_path' already exists${NC}"
        exit 1
    fi
    
    # Create template based on format
    if [ "$html_mode" = true ]; then
        cat > "$output_path" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$title</title>
    <meta name="tags" content="">
    <meta name="date" content="$display_date">
    <meta name="slug" content="$slug">
</head>
<body>
    <h1>$title</h1>
    <p>Your content here...</p>
</body>
</html>
EOF
    else
        cat > "$output_path" << EOF
---
title: $title
date: $display_date
tags: 
slug: $slug
image:
image_caption:
description: 
---

Your content here...
EOF
    fi
    
    # Open in editor
    edit_file "$output_path"
    
    # Build site if not a draft
    if [ "$draft_mode" = false ]; then
        echo -e "${GREEN}Building site...${NC}"
        ./scripts/build.sh
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

# Run the create post function
create_post "$@" 
