#!/usr/bin/env bash
#
# Script to generate preview sites for all available BSSG themes.
# Assumes it's run from the BSSG project root directory.
# Developed by Stefano Marinelli (stefano@dragas.it)

# Exit on error, treat unset variables as errors, propagation errors in pipelines
set -euo pipefail

# --- Configuration ---
# Ensure BSSG_MAIN_SCRIPT points to the main bssg.sh in the project root
# Ensure this script (generate_theme_previews.sh) is run from the project root.
readonly BSSG_MAIN_SCRIPT="./bssg.sh"
readonly THEMES_DIR="./themes"
CONFIG_FILE="config.sh" # For reading default SITE_URL if not overridden
LOCAL_CONFIG_FILE="config.sh.local" # For reading default SITE_URL if not overridden

# Global variable for the dynamic example root directory
EXAMPLE_ROOT_DIR_DYNAMIC="./example" # Default value, will be updated

# Terminal colors (optional, for better output)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default SITE_URL from config.sh if no other is specified by script's --site-url
SITE_URL_BASE="http://localhost"

# --- Helper Functions ---
info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$@"
}

success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$@"
}

warn() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$@"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$@" >&2
    exit 1
}

# --- Cleanup Functions ---
cleanup_directories() {
    info "Cleanup function called on exit. No specific preview-script files to clean in this version."
}

trap cleanup_directories EXIT

# --- Print Help ---
print_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate preview sites for all available BSSG themes.

Options:
  -h, --help                 Display this help message and exit
  --site-url URL             Set the base SITE_URL for theme previews
                             (overrides config files)

Configuration:
  The script will use the SITE_URL from the following sources in order of precedence:
  1. Command line argument (--site-url)
  2. Local config file ($LOCAL_CONFIG_FILE)
  3. Main config file ($CONFIG_FILE)
  4. Default value (http://localhost)

Output:
  Theme previews will be generated in the '$EXAMPLE_ROOT_DIR_DYNAMIC' directory,
  with each theme in its own subdirectory. An index.html file will be
  created to navigate between themes.
EOF
    exit 0
}

# --- Parse Command Line Arguments (for this script) ---
parse_args() {
    site_url_from_cli="" # Made global for load_config

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_help
                ;;
            --site-url)
                if [[ -n "${2:-}" ]]; then
                    site_url_from_cli="$2"
                    shift 2
                else
                    error "--site-url requires a value for the base URL of previews"
                fi
                ;;
            *)
                warn "Unknown option: $1 (ignored)"
                shift
                ;;
        esac
    done
}

# --- Load Configuration (for this script's SITE_URL_BASE) ---
load_config() {
    info "Loading base SITE_URL configuration for previews..."
    
    if [ -f "$CONFIG_FILE" ]; then
        # Portable way to extract SITE_URL="value"
        local main_conf_site_url
        main_conf_site_url=$(awk -F'"' '/^SITE_URL=/ {print $2; exit}' "$CONFIG_FILE")
        if [ -n "$main_conf_site_url" ]; then
            SITE_URL_BASE="$main_conf_site_url"
            info "Using SITE_URL_BASE='$SITE_URL_BASE' from $CONFIG_FILE as default"
        fi
    else
        warn "Main configuration file '$CONFIG_FILE' not found, using default SITE_URL_BASE='$SITE_URL_BASE'."
    fi
    
    if [ -f "$LOCAL_CONFIG_FILE" ]; then
        local local_conf_site_url
        # Check if SITE_URL is actually defined in the local config
        if grep -q "^SITE_URL=" "$LOCAL_CONFIG_FILE" 2>/dev/null; then
            local_conf_site_url=$(awk -F'"' '/^SITE_URL=/ {print $2; exit}' "$LOCAL_CONFIG_FILE")
            if [ -n "$local_conf_site_url" ]; then
                SITE_URL_BASE="$local_conf_site_url"
                info "Overridden SITE_URL_BASE='$SITE_URL_BASE' from $LOCAL_CONFIG_FILE"
            else
                warn "Found $LOCAL_CONFIG_FILE but failed to extract SITE_URL, using current SITE_URL_BASE='$SITE_URL_BASE'"
            fi
        fi
    fi
    
    if [ -n "$site_url_from_cli" ]; then
        SITE_URL_BASE="$site_url_from_cli"
        info "Using SITE_URL_BASE='$SITE_URL_BASE' from command line argument for previews"
    fi
    
    success "Configuration loaded. Using SITE_URL_BASE='$SITE_URL_BASE' for theme previews."
}

# --- Sanity Checks ---
check_dependencies() {
    info "Checking requirements..."
    if [ ! -f "$BSSG_MAIN_SCRIPT" ]; then
        error "BSSG main script not found at '$BSSG_MAIN_SCRIPT'. Run this script from the BSSG project root."
    fi
    if [ ! -x "$BSSG_MAIN_SCRIPT" ]; then
        error "BSSG main script '$BSSG_MAIN_SCRIPT' is not executable. Please run 'chmod +x $BSSG_MAIN_SCRIPT'."
    fi
    if [ ! -d "$THEMES_DIR" ]; then
        error "Themes directory not found at '$THEMES_DIR'. This script must be run from the BSSG project root."
    fi
    for cmd in find basename mkdir mv cat date rm ls grep awk sed dirname sort printf bash; do # Added awk, sed, printf, bash
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command '$cmd' not found in PATH."
        fi
    done
    # Check for pwd -P behavior (standard in POSIX sh, but good to be aware)
    if ! (pwd -P >/dev/null 2>&1); then
        warn "pwd -P might not be supported or behave as expected on this system. Path resolution might be affected."
    fi
    success "Requirements met."
}

# --- Path Normalization Helper (replaces realpath -m) ---
_normalize_path_string() {
    local path_to_normalize="$1"
    local current_dir
    current_dir=$(pwd -P) # Get current physical working directory

    local temp_path
    # Make path absolute if it's relative, using the script's CWD as base
    if [[ "$path_to_normalize" != /* ]]; then
        temp_path="$current_dir/$path_to_normalize"
    else
        temp_path="$path_to_normalize"
    fi

    # Add a sentinel component to handle leading '..' correctly by making the path e.g., /sentinel/actual/path
    # This simplifies logic for popping '..' at the "root"
    temp_path="/sentinel${temp_path}"

    local OIFS="$IFS"
    IFS='/'
    # shellcheck disable=SC2206 # Word splitting is desired here for path components
    local components=($temp_path)
    IFS="$OIFS"

    local result_components=()
    for comp in "${components[@]}"; do
        if [[ -z "$comp" || "$comp" == "." ]]; then
            continue # Skip empty or current dir components
        fi
        if [[ "$comp" == ".." ]]; then
            # Only pop if result_components is not empty and last component is not 'sentinel'
            if [[ ${#result_components[@]} -gt 0 && "${result_components[${#result_components[@]}-1]}" != "sentinel" ]]; then
                unset 'result_components[${#result_components[@]}-1]'
            fi
        else
            result_components+=("$comp")
        fi
    done

    # Reconstruct the path
    local final_path
    # Remove 'sentinel' if it's the first component
    if [[ ${#result_components[@]} -gt 0 && "${result_components[0]}" == "sentinel" ]]; then
        # Handle case where only sentinel remains (e.g. /sentinel/../..) -> /
        if [[ ${#result_components[@]} -eq 1 ]]; then
            final_path="/"
        else
            # Join remaining components. ${array[*]:1} gives elements from index 1.
            final_path="/$(IFS=/; echo "${result_components[*]:1}")"
        fi
    else 
        # This case implies original path was something like /../../.. that resolved above sentinel
        # or the sentinel was incorrectly processed. Should resolve to root.
        final_path="/"
    fi
    
    # Post-process: remove multiple slashes, trailing slash (unless it's just "/")
    final_path=$(echo "$final_path" | sed 's#//*#/#g')
    if [[ "$final_path" != "/" && "${final_path: -1}" == "/" ]]; then
         final_path="${final_path%/}"
    fi
    # If final_path is empty after all this (e.g. input was just "/"), ensure it's "/"
    if [[ -z "$final_path" ]]; then
        echo "/"
    else
        echo "$final_path"
    fi
}


# --- Main Logic ---

find_themes() {
    info "Searching for themes in '$THEMES_DIR'..."
    
    if [ ! -d "$THEMES_DIR" ]; then
        error "Themes directory '$THEMES_DIR' does not exist!"
    fi
    
    echo "Debug: listing themes directory content with ls"
    ls -la "$THEMES_DIR" # Keep for debugging if needed
    
    local theme_names=()
    for d in "$THEMES_DIR"/*; do
        if [ -d "$d" ]; then
            theme_names+=("$(basename "$d")")
        fi
    done
    
    if [ ${#theme_names[@]} -eq 0 ]; then
         error "No valid theme directories found in '$THEMES_DIR'."
    fi
    
    # Sort themes using standard sort command
    # Store sorted names back into the global 'themes' array
    local sorted_theme_names_nl
    sorted_theme_names_nl=$(printf "%s\n" "${theme_names[@]}" | sort)
    
    themes=() # Clear global themes array before repopulating
    while IFS= read -r line; do
        if [ -n "$line" ]; then # Ensure no empty lines become theme names
             themes+=("$line")
        fi
    done <<< "$sorted_theme_names_nl"
    
    info "Found ${#themes[@]} themes: ${themes[*]}"
}

build_previews() {
    info "Clearing existing example directory: '$EXAMPLE_ROOT_DIR_DYNAMIC'"
    mkdir -p "$EXAMPLE_ROOT_DIR_DYNAMIC"
    # More robustly clear contents. Using find is safer for unusual filenames.
    # However, rm -rf with :? guard is common.
    # Ensure EXAMPLE_ROOT_DIR_DYNAMIC is not empty and not root, for safety.
    if [ -z "$EXAMPLE_ROOT_DIR_DYNAMIC" ] || [ "$EXAMPLE_ROOT_DIR_DYNAMIC" = "/" ] || [ "$EXAMPLE_ROOT_DIR_DYNAMIC" = "." ] || [ "$EXAMPLE_ROOT_DIR_DYNAMIC" = ".." ]; then
        error "Safety check failed: EXAMPLE_ROOT_DIR_DYNAMIC is '$EXAMPLE_ROOT_DIR_DYNAMIC'. Aborting clear."
    fi
    rm -rf "${EXAMPLE_ROOT_DIR_DYNAMIC:?}"/* "${EXAMPLE_ROOT_DIR_DYNAMIC:?}"/.* 2>/dev/null || true 
    # Note: .??* misses files like .a but covers most common dotfiles. /.* is more thorough but needs care.
    # A safer alternative if `find` is available:
    # find "$EXAMPLE_ROOT_DIR_DYNAMIC" -mindepth 1 -delete
    success "Example directory cleared and ready."

    info "Starting theme preview builds..."
    info "Previews will use content from the BSSG site configured by your standard config.sh/config.sh.local files."

    for theme in "${themes[@]}"; do
        info "Building preview for theme: '$theme'"

        local theme_site_url="${SITE_URL_BASE%/}/${theme}" 
        local theme_output_path="${EXAMPLE_ROOT_DIR_DYNAMIC}/${theme}"

        info "Theme Site URL: $theme_site_url"
        info "Theme Output Path: $theme_output_path"

        mkdir -p "$theme_output_path"

        info "Executing: $BSSG_MAIN_SCRIPT build -f --theme \"$theme\" --site-url \"$theme_site_url\" --output \"$theme_output_path\""
        
        if ! "$BSSG_MAIN_SCRIPT" build -f --theme "$theme" --site-url "$theme_site_url" --output "$theme_output_path"; then
            error "Build failed for theme '$theme'. Check output above."
        fi
        success "Preview for theme '$theme' built successfully in '$theme_output_path'"
    done

    success "All theme previews built."
}

create_index_page() {
    local index_file="$EXAMPLE_ROOT_DIR_DYNAMIC/index.html"
    info "Generating index file at '$index_file'..."

    local current_date
    current_date=$(date) 
    local theme_count=${#themes[@]}

    # HTML content remains the same, heredoc is portable
    cat << EOF > "$index_file"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BSSG Theme Previews</title>
    <style>
        :root {
            --bg-color: #fcfcfc; --text-color: #333333; --link-color: #3b82f6;
            --link-hover-color: #1d4ed8; --header-color: #1e293b; --border-color: #e5e7eb;
            --accent-color: #f0f9ff; --accent-secondary: #93c5fd; --tag-bg: #dbeafe;
            --card-bg: #ffffff; --card-shadow: 0 4px 6px rgba(0, 0, 0, 0.03), 0 1px 3px rgba(0, 0, 0, 0.05);
            --radius: 10px; --transition: 0.2s ease;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #0f172a; --text-color: #e2e8f0; --link-color: #60a5fa;
                --link-hover-color: #93c5fd; --header-color: #f8fafc; --border-color: #334155;
                --accent-color: #1e3a8a; --accent-secondary: #3b82f6; --tag-bg: #1e3a8a;
                --card-bg: #1e293b; --card-shadow: 0 4px 6px rgba(0, 0, 0, 0.1), 0 1px 3px rgba(0, 0, 0, 0.15);
            }
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6; margin: 0; padding: 0; color: var(--text-color); background-color: var(--bg-color);
        }
        .container { max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem; }
        header {
            text-align: center; margin-bottom: 2.5rem; position: relative;
            padding-bottom: 1.5rem; border-bottom: 1px solid var(--border-color);
        }
        header::after {
            content: ""; position: absolute; bottom: -1px; left: 50%; transform: translateX(-50%);
            width: 120px; height: 3px; background: linear-gradient(90deg, var(--link-color), var(--accent-secondary));
            border-radius: var(--radius);
        }
        h1 {
            color: var(--header-color); font-size: 2.5rem; margin: 0; padding: 0;
            background: linear-gradient(120deg, var(--header-color) 0%, var(--link-color) 100%);
            background-clip: text; -webkit-background-clip: text; color: transparent;
            text-shadow: 0 1px 1px rgba(0,0,0,0.05);
        }
        .theme-count {
            display: inline-block; background-color: var(--accent-secondary); color: white;
            font-weight: bold; padding: 0.4rem 1rem; border-radius: 2rem; margin: 1rem 0;
            font-size: 1.1rem; box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .description { font-size: 1.1rem; max-width: 600px; margin: 1rem auto; opacity: 0.9; }
        .theme-grid {
            display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 1.5rem; margin-bottom: 2rem;
        }
        .theme-card {
            background-color: var(--card-bg); border-radius: var(--radius); overflow: hidden;
            box-shadow: var(--card-shadow); transition: transform var(--transition), box-shadow var(--transition);
            position: relative; border: 1px solid var(--border-color);
        }
        .theme-card:hover, .theme-card:focus-within { transform: translateY(-5px); box-shadow: 0 10px 15px rgba(0, 0, 0, 0.1); }
        .theme-card a {
            display: block; padding: 1.5rem; text-decoration: none; color: var(--link-color);
            font-weight: 500; font-size: 1.1rem; position: relative; z-index: 1;
        }
        .theme-card a::after { content: ""; position: absolute; top: 0; left: 0; right: 0; bottom: 0; z-index: -1; }
        .theme-name { font-weight: 600; margin-bottom: 0.5rem; color: var(--header-color); transition: color var(--transition); }
        .theme-card:hover .theme-name { color: var(--link-color); }
        .theme-card::before {
            content: "→"; position: absolute; right: 1.5rem; top: 50%; transform: translateY(-50%);
            font-size: 1.25rem; opacity: 0; color: var(--link-color);
            transition: opacity var(--transition), transform var(--transition);
        }
        .theme-card:hover::before { opacity: 1; transform: translate(5px, -50%); }
        footer {
            text-align: center; margin-top: 3rem; padding-top: 1.5rem; color: var(--text-color);
            opacity: 0.8; font-size: 0.9rem; border-top: 1px solid var(--border-color); position: relative;
        }
        footer::before {
            content: ""; position: absolute; top: -1px; left: 50%; transform: translateX(-50%);
            width: 100px; height: 3px; background: linear-gradient(90deg, var(--accent-secondary), var(--link-color));
            border-radius: var(--radius);
        }
        @media (max-width: 768px) { .theme-grid { grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); } }
        @media (max-width: 480px) {
            .theme-grid { grid-template-columns: 1fr; }
            h1 { font-size: 2rem; } .container { padding: 1.5rem 1rem; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>BSSG Theme Previews</h1>
            <div class="theme-count">${theme_count} Themes Available</div>
            <p class="description">Browse these theme previews using the current site content. Click on any theme to explore its design.</p>
        </header>
        <div class="theme-grid">
EOF

    for theme in "${themes[@]}"; do
        local safe_theme_name="${theme//&/&}"
        safe_theme_name="${safe_theme_name//</<}"
        safe_theme_name="${safe_theme_name//>/>}"

        cat << EOF >> "$index_file"
            <div class="theme-card">
                <a href="./${theme}/">
                    <div class="theme-name">${safe_theme_name}</div>
                </a>
            </div>
EOF
    done

    cat << EOF >> "$index_file"
        </div>
        <footer>
            <p>Generated on ${current_date}</p>
            <p>Base SITE_URL: ${SITE_URL_BASE}</p>
        </footer>
    </div>
</body>
</html>
EOF

    success "Index file generated successfully with ${theme_count} themes."
}

determine_example_root_dir() {
    info "Determining effective site root for EXAMPLE_ROOT_DIR_DYNAMIC..."
    local project_root_abs
    # Portable way to get absolute path of current directory
    project_root_abs=$( (cd . && pwd -P) || { error "Could not determine project root."; exit 1; } )


    local effective_output_dir
    effective_output_dir=$(export BSSG_SCRIPT_DIR="$project_root_abs"; \
                           bash -c 'source "$BSSG_SCRIPT_DIR/scripts/build/config_loader.sh" "" &>/dev/null; echo "$OUTPUT_DIR"')

    if [ -z "$effective_output_dir" ]; then
        warn "Could not determine effective OUTPUT_DIR from BSSG configuration. Defaulting EXAMPLE_ROOT_DIR_DYNAMIC to '$EXAMPLE_ROOT_DIR_DYNAMIC'."
        return
    fi
    info "Effective OUTPUT_DIR from BSSG configuration: '$effective_output_dir'"

    local effective_output_dir_abs_unnormalized
    if [[ "$effective_output_dir" == /* ]]; then 
        effective_output_dir_abs_unnormalized="$effective_output_dir"
    else 
        effective_output_dir_abs_unnormalized="$project_root_abs/$effective_output_dir"
    fi
    
    # Normalize the path using our helper (handles ., .., and non-existent paths)
    local effective_output_dir_abs
    effective_output_dir_abs=$(_normalize_path_string "$effective_output_dir_abs_unnormalized")
    info "Normalized effective_output_dir_abs: '$effective_output_dir_abs'"


    local site_root_candidate
    site_root_candidate=$(dirname "$effective_output_dir_abs")
    # dirname /foo is / ; dirname / is /
    # Ensure site_root_candidate is cleaned up if it's just "//" or similar from dirname
    if [[ "$site_root_candidate" != "/" ]]; then
        site_root_candidate=$(echo "$site_root_candidate" | sed 's#//*#/#g')
    fi


    if [[ "$site_root_candidate" != "$project_root_abs" && "$effective_output_dir" == /* ]]; then
        info "Detected external site configuration. Previews will be generated in '$site_root_candidate/example'."
        EXAMPLE_ROOT_DIR_DYNAMIC="$site_root_candidate/example"
    else
        info "Using BSSG project directory for previews. Previews will be generated in '$project_root_abs/example'."
        EXAMPLE_ROOT_DIR_DYNAMIC="$project_root_abs/example" 
    fi
    # Normalize the final EXAMPLE_ROOT_DIR_DYNAMIC as well
    EXAMPLE_ROOT_DIR_DYNAMIC=$(_normalize_path_string "$EXAMPLE_ROOT_DIR_DYNAMIC")
    success "EXAMPLE_ROOT_DIR_DYNAMIC set to '$EXAMPLE_ROOT_DIR_DYNAMIC'."
}

main() {
    # Ensure global 'themes' array is declared if not implicitly through find_themes
    declare -a themes

    parse_args "$@"
    load_config 
    check_dependencies
    determine_example_root_dir 

    find_themes # Populates global 'themes' array
    build_previews
    create_index_page

    success "Theme previews generated successfully in '$EXAMPLE_ROOT_DIR_DYNAMIC'"
    info "Open '$EXAMPLE_ROOT_DIR_DYNAMIC/index.html' in your browser to view them."
}

main "$@"