#!/usr/bin/env bash
#
# BSSG - Post-Processing Script
# Handles final URL fixing and permission adjustments.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from post_process.sh"; exit 1; }

# Post-process all generated HTML files to fix URLs
post_process_urls() {
    echo -e "${YELLOW}Post-processing URLs with SITE_URL...${NC}"

    # Skip if SITE_URL is empty or just http://localhost (default)
    if [ -z "$SITE_URL" ] || [ "$SITE_URL" = "http://localhost" ]; then
        echo -e "${YELLOW}SITE_URL is empty or default, skipping URL post-processing${NC}"
        return 0
    fi

    # Find all HTML files in the output directory
    local html_files
    # Use find with -print0 and xargs for safety with special filenames
    find "$OUTPUT_DIR" -type f -name "*.html" -print0 | while IFS= read -r -d $'\0' file; do
        # Create a temporary file
        local temp_file
        temp_file=$(mktemp) || { echo "Failed to create temp file"; return 1; }

        # Replace href="/ with href="${SITE_URL}/ using sed
        # Use pipe as delimiter to avoid issues with slashes in SITE_URL
        # Handle potential errors during sed or mv
        if sed "s|href=\"/|href=\"${SITE_URL}/|g" "$file" > "$temp_file"; then
            local temp_file2
            temp_file2=$(mktemp) || { echo "Failed to create temp file 2"; rm -f "$temp_file"; return 1; }
            if sed "s|src=\"/|src=\"${SITE_URL}/|g" "$temp_file" > "$temp_file2"; then
                 mv "$temp_file2" "$file"
            else
                echo -e "${RED}Error processing src URLs in $file${NC}"
                rm -f "$temp_file2"
            fi
        else
             echo -e "${RED}Error processing href URLs in $file${NC}"
        fi
        # Clean up the first temp file
        rm -f "$temp_file"
    done

    # Process XML files (RSS, sitemaps)
    local xml_files
    # Use find with -print0 and xargs for safety
    find "$OUTPUT_DIR" -type f -name "*.xml" -print0 | while IFS= read -r -d $'\0' file; do
        # Create a temporary file
        local temp_file
        temp_file=$(mktemp) || { echo "Failed to create temp file for XML"; continue; }

        # Replace URLs in XML files (e.g., <loc>/</loc> -> <loc>${SITE_URL}/</loc>)
        # Combine replacements for efficiency if sed supports multiple expressions
        if sed -e "s|<loc>/</|<loc>${SITE_URL}/|g" \
               -e "s|<link>/</|<link>${SITE_URL}/|g" \
               -e "s|<guid.*>/</guid>|<guid isPermaLink=\"true\">${SITE_URL}/</guid>|g" "$file" > "$temp_file"; then # Basic guid replacement, might need refinement
            mv "$temp_file" "$file"
        else
            echo -e "${RED}Error processing XML URLs in $file${NC}"
            rm -f "$temp_file"
        fi
    done

    # Process CSS files for any url() references starting with /
    local css_files
    # Use find with -print0 and xargs for safety
    find "$OUTPUT_DIR" -type f -name "*.css" -print0 | while IFS= read -r -d $'\0' file; do
        # Create a temporary file
        local temp_file
        temp_file=$(mktemp) || { echo "Failed to create temp file for CSS"; continue; }

        # Combine replacements for efficiency
        if sed -e "s|url('/|url('${SITE_URL}/|g" \
               -e "s|url(\"/|url(\"${SITE_URL}/|g" \
               -e "s|url(/|url(${SITE_URL}/|g" "$file" > "$temp_file"; then
            mv "$temp_file" "$file"
        else
            echo -e "${RED}Error processing CSS URLs in $file${NC}"
            rm -f "$temp_file"
        fi
    done

    echo -e "${GREEN}URL post-processing complete!${NC}"
}

# Function to fix permissions in the output directory
fix_output_permissions() {
    echo "Setting proper permissions for output directory content..."

    # Check if output directory exists
    if [ ! -d "$OUTPUT_DIR" ]; then
      echo -e "${YELLOW}Output directory '$OUTPUT_DIR' not found, skipping permission fix.${NC}"
      return 0
    fi

    # Make all files readable by all users
    find "$OUTPUT_DIR" -type f -print0 | xargs -0 chmod a+r

    # Make all directories readable and executable by all users
    find "$OUTPUT_DIR" -type d -print0 | xargs -0 chmod a+rx

    echo -e "${GREEN}Permissions set successfully!${NC}"
}

# Export functions
export -f post_process_urls
export -f fix_output_permissions 