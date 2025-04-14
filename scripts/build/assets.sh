#!/usr/bin/env bash
#
# BSSG - Asset Handling
# Handles copying static assets and processing CSS.
#

# Source dependencies (optional, but good practice if utils are needed)
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from assets.sh"; exit 1; }

copy_static_files() {
    # Source utilities if needed for colors (already done above)

    if [ -d "$STATIC_DIR" ]; then
        echo "Copying static files from $STATIC_DIR to $OUTPUT_DIR..."
        # Use rsync for efficiency if available, otherwise cp
        if command -v rsync > /dev/null 2>&1; then
            # Ensure source ends with / if copying contents
            rsync -a --checksum --exclude='.DS_Store' --exclude='._*' "${STATIC_DIR}/" "$OUTPUT_DIR/"
        else
            # Simple copy (less efficient, might overwrite newer)
            # Ensure target exists
            mkdir -p "$OUTPUT_DIR"
            # Using cp -R instead of -r for better compatibility, -p preserves timestamps
            cp -Rp "$STATIC_DIR/." "$OUTPUT_DIR/"
        fi
        echo -e "${GREEN}Static files copied.${NC}"
    else
        echo -e "${YELLOW}Static directory '$STATIC_DIR' not found, skipping copy.${NC}"
    fi
}

# Create CSS directory and copy theme CSS
create_css() {
    local output_dir="$1"
    local theme="$2"
    local css_dir="${output_dir}/css"
    
    mkdir -p "${css_dir}"
    
    # Check if theme directory exists
    local theme_dir="${THEMES_DIR}/${theme}"
    if [ ! -d "$theme_dir" ]; then
        echo -e "${RED}Error: Theme directory '$theme_dir' (using THEMES_DIR='${THEMES_DIR}') not found.${NC}"
        # Decide if this is fatal. For now, just warn and skip CSS copy.
        return 1 # Return error code
    fi

    # Check if style.css exists in the theme directory
    if [ ! -f "$theme_dir/style.css" ]; then
        echo -e "${RED}Error: style.css not found in theme directory '$theme_dir'.${NC}"
        # Decide if this is fatal. For now, just warn and skip CSS copy.
        return 1 # Return error code
    fi
    
    # Copy the theme CSS file
    cp "$theme_dir/style.css" "${css_dir}/style.css"
    
    echo "CSS file copied to ${css_dir}"
}

# Export functions
export -f copy_static_files
export -f create_css 
