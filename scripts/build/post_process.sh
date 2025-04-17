#!/usr/bin/env bash
#
# BSSG - Post-Processing Script 
# Handles final URL fixing and permission adjustments.
#

# Source common utilities
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from post_process.sh"; exit 1; }

# --- URL Post-Processing ---

# Replaces absolute URLs (starting with /) with the full SITE_URL
# in HTML, XML, and CSS files within the OUTPUT_DIR.
post_process_urls() {
    echo "Post-processing URLs with SITE_URL..."
    local site_url="$SITE_URL" # Use local var

    # 1. Check if processing is needed
    if [ -z "$site_url" ] || [[ "$site_url" == *"//localhost"* ]] || [[ "$site_url" == *"//127.0.0.1"* ]]; then
        echo -e "${YELLOW}SITE_URL is not set or is localhost. Skipping URL post-processing.${NC}"
        return 0
    fi

    # 2. Ensure SITE_URL ends with a slash (unless it's just "/")
    if [[ "$site_url" != "/" && "${site_url: -1}" != "/" ]]; then
        site_url="${site_url}/"
        echo "Appended trailing slash to SITE_URL: $site_url"
    fi

    # 3. Determine sed command parts based on OS for in-place editing
    local sed_cmd_base=(sed) # Use array for command parts
    echo "Current OSTYPE: $OSTYPE"
    if [[ $OSTYPE == "darwin"* ]] || [[ $OSTYPE == *"bsd"* ]] || [[ $OSTYPE == "FreeBSD"* ]]; then
        echo "Detected macOS/BSD, using sed -i ''"
        sed_cmd_base+=(-i '') # Add -i and '' separately for BSD/macOS sed
    else
        echo "Detected Linux or other, using sed -i"
        sed_cmd_base+=(-i) # Add -i as a single element for GNU sed
    fi

    # 4. Escape SITE_URL for use in sed \'s\' command (handles / and &)\n    local escaped_site_url\n    # Use printf \'%s\' (no newline), sed to escape / and &, and tr -d \'\\n\' to be sure\n    escaped_site_url=$(printf \'%s\' \"$site_url\" | sed -e \'s/[\\/&]/\\\\&/g\' | tr -d \'\\n\')\n\n    # Further escape for sed replacement part: escape \'$\'\n    local sed_final_escaped_site_url=${escaped_site_url//\$/\\\\$}\n\n    # 5. Define processing function using find | while read loop\n    local error_occurred=0\n    process_files_with_sed() {\n        local file_pattern=\"$1\"\n        local description=\"$2\"\n        # Remaining arguments are sed expressions (using the final escaped URL)\n        shift 2\n        local sed_expressions_templates=(\"$@\") # These are now templates\n\n        echo \"Processing $description files ($file_pattern)...\"\n        local file\n\n        # Use find ... -print0 | while read ... for robust filename handling\n        while IFS= read -r -d $\'\\0\' file; do\n            # Construct the full command with multiple -e arguments for this file\n            local current_sed_cmd=(\"${sed_cmd_base[@]}\") # Copy base command (e.g., sed -i \'\')\n\n            # Populate expressions with the final escaped URL\n            local expr_template\n            for expr_template in \"${sed_expressions_templates[@]}\"; do\n                 # Replace placeholder with the fully escaped URL\n                 local expr=${expr_template//SITE_URL_PLACEHOLDER/$sed_final_escaped_site_url}\n                 current_sed_cmd+=(-e \"$expr\")\n            done\n            current_sed_cmd+=(\"$file\") # Add the filename\n\n            # Execute sed command for the current file\n            if ! \"${current_sed_cmd[@]}\"; then\n                echo -e \"${RED}Error processing file: $file${NC}\" >&2\n                error_occurred=1\n            fi\n        done < <(find \"$OUTPUT_DIR\" -type f -name \"$file_pattern\" -print0)\n\n        # Check for find errors (simplified check)\n        # Use -quit to stop after first potential error/non-existence for efficiency\n        if ! find \"$OUTPUT_DIR\" -type f -name \"$file_pattern\" -print0 -quit >/dev/null 2>&1; then\n            if [ ! -d \"$OUTPUT_DIR\" ]; then\n                 echo -e \"${YELLOW}Directory \'$OUTPUT_DIR\' not found for $description processing.${NC}\"\n            # Consider adding more specific find error checks here if needed\n            fi\n            # Note: find might return non-zero for permission issues even if files exist\n        fi\n    }\n\n    # 6. Process file types\n    # Pass expression *templates* with SITE_URL_PLACEHOLDER\n    # Use # as delimiter for sed.\n    # HTML: href=\"/...\", src=\"/...\"\n    process_files_with_sed \"*.html\" \"HTML\" \\\n        \"s#href=\\\"/#href=\\\"SITE_URL_PLACEHOLDER#g\" \\\n        \"s#src=\\\"/#src=\\\"SITE_URL_PLACEHOLDER#g\"\n\n    # XML: <loc>/...</loc>, <link>/...</link>, <guid>...</guid>\n    process_files_with_sed \"*.xml\" \"XML\" \\\n        \"s#<loc>/</<loc>SITE_URL_PLACEHOLDER#g\" \\\n        \"s#<link>/</<link>SITE_URL_PLACEHOLDER#g\" \\\n        \"s#\\\\(<guid.*>\\\\)/\\\\(</guid>\\\\)#\\\\1SITE_URL_PLACEHOLDER\\\\2#g\"\n\n    # CSS: url(\'/...\'), url(\"/...\"), url(/...)\n    process_files_with_sed \"*.css\" \"CSS\" \\\n        \"s#url(\'/#url(\'SITE_URL_PLACEHOLDER#g\" \\\n        \"s#url(\\\"/#url(\\\"SITE_URL_PLACEHOLDER#g\" \\\n        \"s#url(/#url(SITE_URL_PLACEHOLDER#g\"\n

    # 7. Report final status
    if [[ "$error_occurred" -ne 0 ]]; then
        echo -e "${RED}One or more errors occurred during URL post-processing.${NC}" >&2
    else
        echo -e "${GREEN}URL post-processing complete!${NC}"
    fi
    return $error_occurred # Return status without quotes
}


# --- Permission Fixing ---

# Sets readable permissions for files and read/execute for directories.
fix_output_permissions() {
    echo "Setting proper permissions for output directory content..."

    # Check if output directory exists
    if [ ! -d "$OUTPUT_DIR" ]; then
      echo -e "${YELLOW}Output directory '$OUTPUT_DIR' not found, skipping permission fix.${NC}"
      return 0 # Not an error, just nothing to do
    fi

    local error_occurred=0

    # Make all files readable by all users (a+r)
    echo "Setting file permissions (a+r)..."
    if ! find "$OUTPUT_DIR" -type f -print0 | xargs -0 chmod a+r; then
        echo -e "${RED}Error setting file permissions.${NC}" >&2
        error_occurred=1
    fi

    # Make all directories readable and executable by all users (a+rx)
    echo "Setting directory permissions (a+rx)..."
    if ! find "$OUTPUT_DIR" -type d -print0 | xargs -0 chmod a+rx; then
        echo -e "${RED}Error setting directory permissions.${NC}" >&2
        error_occurred=1
    fi

    if [[ "$error_occurred" -eq 0 ]]; then
        echo -e "${GREEN}Permissions set successfully!${NC}"
    else
        echo -e "${RED}Errors occurred while setting permissions.${NC}" >&2
    fi
    return $error_occurred # Return status without quotes
}

# Export functions for use in other scripts
export -f post_process_urls
export -f fix_output_permissions

# --- Main Execution (Optional) ---
# If this script were meant to be run directly, add main logic here.
# Since it's likely sourced, we usually just define/export functions.

# Example of how the calling script might use these:
# if ! post_process_urls; then
#     echo "URL processing failed!" >&2
#     # exit 1 # Or handle error
# fi
# if ! fix_output_permissions; then
#     echo "Permission fixing failed!" >&2
#     # exit 1 # Or handle error
# fi 
