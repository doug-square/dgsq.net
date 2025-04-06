#!/usr/bin/env bash
#
# BSSG - CSS Handling Script
# Manages CSS file processing for the static site generator
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net

# Create CSS directory and copy theme CSS
create_css() {
    local output_dir="$1"
    local theme="$2"
    local css_dir="${output_dir}/css"
    
    mkdir -p "${css_dir}"
    
    # Handle random theme selection
    if [ "$theme" = "random" ]; then
        # Source the theme script to get a random theme
        THEME="random"
        source "$(dirname "$0")/theme.sh"
        echo "Using theme: $current_theme"
    else
        # Use the specified theme directly
        cp "themes/${theme}/style.css" "${css_dir}/style.css"
    fi
    
    echo "CSS files copied to ${css_dir}"
}

copy_static_files() { if [ -d "$STATIC_DIR" ]; then mkdir -p "$OUTPUT_DIR"; if [ "$(ls -A $STATIC_DIR 2>/dev/null)" ]; then cp -r "$STATIC_DIR/"* "$OUTPUT_DIR/"; fi; fi; }
