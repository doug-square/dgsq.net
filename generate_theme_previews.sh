#!/usr/bin/env bash
#
# Script to generate preview sites for all available BSSG themes.
# Assumes it's run from the BSSG project root directory.
# Developed by Stefano Marinelli (stefano@dragas.it)

# Exit on error, treat unset variables as errors, propagation errors in pipelines
set -euo pipefail

# --- Configuration ---
readonly BSSG_BUILD_SCRIPT="scripts/build/main.sh"
readonly THEMES_DIR="./themes"
readonly BSSG_DEFAULT_OUTPUT_DIR="./output" # Default output dir used by build.sh
readonly EXAMPLE_ROOT_DIR="./example"
readonly CONFIG_FILE="config.sh"
readonly LOCAL_CONFIG_FILE="config.sh.local"

# Terminal colors (optional, for better output)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default SITE_URL from config.sh if no other is specified
SITE_URL="http://localhost"

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
    local dirs=("$BSSG_DEFAULT_OUTPUT_DIR" ".bssg_cache")
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            info "Cleaning directory: '$dir'"
            # Remove contents including hidden files, suppress errors for non-existent hidden files
            rm -rf "$dir"/* "$dir"/.??* 2>/dev/null || true
            success "Directory '$dir' cleaned successfully."
        else
            warn "Directory '$dir' does not exist, skipping cleanup."
        fi
    done
}

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
  Theme previews will be generated in the '$EXAMPLE_ROOT_DIR' directory,
  with each theme in its own subdirectory. An index.html file will be
  created to navigate between themes.
EOF
    exit 0
}

# --- Parse Command Line Arguments ---
parse_args() {
    # Initialize variable
    site_url_from_cli=""

    # Parse command line arguments
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
                    error "--site-url requires a value"
                fi
                ;;
            *)
                warn "Unknown option: $1 (ignored)"
                shift
                ;;
        esac
    done
}

# --- Load Configuration ---
load_config() {
    info "Loading configuration..."
    
    # Load main config if it exists
    if [ -f "$CONFIG_FILE" ]; then
        # Source with subshell to avoid polluting global namespace 
        # but extract SITE_URL
        SITE_URL=$(grep -m 1 "^SITE_URL=" "$CONFIG_FILE" | cut -d'"' -f2 || echo "")
        info "Loaded SITE_URL='$SITE_URL' from $CONFIG_FILE"
    else
        warn "Main configuration file '$CONFIG_FILE' not found, using default SITE_URL."
    fi
    
    # Load local config if it exists (overrides main config)
    if [ -f "$LOCAL_CONFIG_FILE" ]; then
        echo "Debug: Processing local config file: $LOCAL_CONFIG_FILE"
        # Use a more resilient approach for FreeBSD
        # First check if the file contains SITE_URL
        if grep -q "^SITE_URL=" "$LOCAL_CONFIG_FILE" 2>/dev/null; then
            # Now try to extract the value, protecting against pipeline failures
            local_site_url=$(grep -m 1 "^SITE_URL=" "$LOCAL_CONFIG_FILE" | cut -d'"' -f2 || echo "")
            echo "Debug: Found local_site_url='$local_site_url'"
            if [ -n "$local_site_url" ]; then
                SITE_URL="$local_site_url"
                info "Loaded SITE_URL='$SITE_URL' from $LOCAL_CONFIG_FILE"
            else
                warn "Failed to extract SITE_URL from $LOCAL_CONFIG_FILE (empty result)"
            fi
        else
            echo "Debug: No SITE_URL found in $LOCAL_CONFIG_FILE"
        fi
    fi
    
    # Command line argument overrides all config files
    if [ -n "$site_url_from_cli" ]; then
        SITE_URL="$site_url_from_cli"
        info "Using SITE_URL='$SITE_URL' from command line argument"
    fi
    
    success "Configuration loaded. Using SITE_URL='$SITE_URL'"
}

# --- Sanity Checks ---
check_dependencies() {
    info "Checking requirements..."
    if [ ! -f "$BSSG_BUILD_SCRIPT" ]; then
        error "BSSG build script not found at '$BSSG_BUILD_SCRIPT'. Run this script from the BSSG project root."
    fi
    if [ ! -x "$BSSG_BUILD_SCRIPT" ]; then
        error "BSSG build script '$BSSG_BUILD_SCRIPT' is not executable. Please run 'chmod +x $BSSG_BUILD_SCRIPT'."
    fi
    if [ ! -d "$THEMES_DIR" ]; then
        error "Themes directory not found at '$THEMES_DIR'."
    fi
    if [ ! -d "$BSSG_DEFAULT_OUTPUT_DIR" ]; then
        warn "Default output directory '$BSSG_DEFAULT_OUTPUT_DIR' does not exist. Will be created by build script."
    fi
    # Check for essential commands
    for cmd in find basename mkdir mv cat date rm ls grep cut; do # Added grep and cut for config parsing
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command '$cmd' not found in PATH."
        fi
    done
    success "Requirements met."
}

# --- Main Logic ---

# 1. Find all themes (directories inside the themes directory)
find_themes() {
    info "Searching for themes in '$THEMES_DIR'..."
    
    # Check if directory exists first
    if [ ! -d "$THEMES_DIR" ]; then
        error "Themes directory '$THEMES_DIR' does not exist!"
    fi
    
    # Debug the find command output
    echo "Debug: listing themes directory content with ls"
    ls -la "$THEMES_DIR"
    
    echo "Debug: attempting BSD/FreeBSD compatible find"
    
    # Use a more compatible approach for FreeBSD and other systems
    themes=()
    for d in "$THEMES_DIR"/*; do
        if [ -d "$d" ]; then
            # Extract just the basename 
            theme_name=$(basename "$d")
            themes+=("$theme_name")
        fi
    done
    
    if [ ${#themes[@]} -eq 0 ]; then
         error "No valid theme directories found in '$THEMES_DIR'."
    fi
    
    # Sort the themes array (not needed with find command previously)
    # Simple bubble sort
    for ((i=0; i<${#themes[@]}; i++)); do
        for ((j=0; j<${#themes[@]}-i-1; j++)); do
            if [[ "${themes[j]}" > "${themes[j+1]}" ]]; then
                # swap
                temp="${themes[j]}"
                themes[j]="${themes[j+1]}"
                themes[j+1]="$temp"
            fi
        done
    done
    
    info "Found ${#themes[@]} themes: ${themes[*]}"
}

# 2. Build preview for each theme
build_previews() {
    info "Clearing existing example directory: '$EXAMPLE_ROOT_DIR'"
    # Remove contents including hidden files, suppress errors for non-existent hidden files
    rm -rf "$EXAMPLE_ROOT_DIR"/* "$EXAMPLE_ROOT_DIR"/.??* 2>/dev/null || true
    # Ensure the directory exists after clearing
    mkdir -p "$EXAMPLE_ROOT_DIR"
    success "Example directory cleared and ready."

    info "Starting theme preview builds..."
    for theme in "${themes[@]}"; do
        info "Building preview for theme: '$theme'"

        # Set theme-specific SITE_URL
        local theme_site_url="${SITE_URL}/${theme}"
        info "Using theme-specific SITE_URL: $theme_site_url"

        # Run the main build script for this theme.
        # Output goes to the default ./output directory.
        if ! "$BSSG_BUILD_SCRIPT" --theme "$theme" --site-url "$theme_site_url" --output "$BSSG_DEFAULT_OUTPUT_DIR"; then
            error "Build failed for theme '$theme'. Check output above."
        fi
        success "Build completed for theme '$theme'."

        # Define destination directory for this theme's preview
        local theme_dest_dir="$EXAMPLE_ROOT_DIR/$theme"

        info "Moving built site from '$BSSG_DEFAULT_OUTPUT_DIR' to '$theme_dest_dir'"
        # Ensure destination directory itself exists
        mkdir -p "$theme_dest_dir"

        # --- Simplified Move Operation ---
        # Check if there's anything to move first
        if [ -n "$(ls -A "$BSSG_DEFAULT_OUTPUT_DIR")" ]; then # ls -A lists all except . and ..
            # Move the visible contents of the output directory.
            # Using /* ensures we move the contents, not the directory itself.
            # Added '|| true' to handle potential errors if mv fails unexpectedly (e.g. perms)
            # Added '2>/dev/null' to suppress errors if '*' matches nothing (less likely with ls -A check)
            mv "$BSSG_DEFAULT_OUTPUT_DIR"/* "$theme_dest_dir/" 2>/dev/null || true

            # Explicitly move hidden files if any (less common for build output, but safer)
            # Using a loop to handle potential `mv` argument list too long errors and hidden files better
            find "$BSSG_DEFAULT_OUTPUT_DIR" -maxdepth 1 -name '.*' -not -name '.' -not -name '..' -exec mv {} "$theme_dest_dir/" \; 2>/dev/null || true

            # Check if destination directory is still empty after move attempt
            if [ -z "$(ls -A "$theme_dest_dir")" ]; then
                 warn "Destination directory '$theme_dest_dir' is empty after move attempt for theme '$theme'. Check '$BSSG_DEFAULT_OUTPUT_DIR' content and permissions."
            else
                 success "Preview for theme '$theme' moved to '$theme_dest_dir'."
            fi

            # Clean the source output dir after successful move
            info "Cleaning source output directory '$BSSG_DEFAULT_OUTPUT_DIR'..."
            rm -rf "$BSSG_DEFAULT_OUTPUT_DIR"/* "$BSSG_DEFAULT_OUTPUT_DIR"/.??* 2>/dev/null || true

        else
            warn "Default output directory '$BSSG_DEFAULT_OUTPUT_DIR' is empty after build for theme '$theme'. Nothing to move."
        fi
        # --- End Simplified Move ---

        printf -- "----------------------------------------\n"
    done
}

# 3. Generate the index.html in the example directory (No changes here)
generate_index() {
    local index_file="$EXAMPLE_ROOT_DIR/index.html"
    info "Generating index file at '$index_file'..."

    # Get current date for the footer
    local current_date
    current_date=$(date) # Use default date format
    
    # Theme count for display
    local theme_count=${#themes[@]}

    # Use cat heredoc to create the HTML file
    cat << EOF > "$index_file"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BSSG Theme Previews</title>
    <style>
        :root {
            /* Modern color scheme inspired by default BSSG theme */
            --bg-color: #fcfcfc;
            --text-color: #333333;
            --link-color: #3b82f6;
            --link-hover-color: #1d4ed8;
            --header-color: #1e293b;
            --border-color: #e5e7eb;
            --accent-color: #f0f9ff;
            --accent-secondary: #93c5fd;
            --tag-bg: #dbeafe;
            --card-bg: #ffffff;
            --card-shadow: 0 4px 6px rgba(0, 0, 0, 0.03), 0 1px 3px rgba(0, 0, 0, 0.05);
            --radius: 10px;
            --transition: 0.2s ease;
        }
        
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #0f172a;
                --text-color: #e2e8f0;
                --link-color: #60a5fa;
                --link-hover-color: #93c5fd;
                --header-color: #f8fafc;
                --border-color: #334155;
                --accent-color: #1e3a8a;
                --accent-secondary: #3b82f6;
                --tag-bg: #1e3a8a;
                --card-bg: #1e293b;
                --card-shadow: 0 4px 6px rgba(0, 0, 0, 0.1), 0 1px 3px rgba(0, 0, 0, 0.15);
            }
        }
        
        /* Base styles */
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            color: var(--text-color);
            background-color: var(--bg-color);
        }
        
        .container {
            max-width: 900px;
            margin: 0 auto;
            padding: 2rem 1.5rem;
        }
        
        /* Header styles */
        header {
            text-align: center;
            margin-bottom: 2.5rem;
            position: relative;
            padding-bottom: 1.5rem;
            border-bottom: 1px solid var(--border-color);
        }
        
        header::after {
            content: "";
            position: absolute;
            bottom: -1px;
            left: 50%;
            transform: translateX(-50%);
            width: 120px;
            height: 3px;
            background: linear-gradient(90deg, var(--link-color), var(--accent-secondary));
            border-radius: var(--radius);
        }
        
        h1 {
            color: var(--header-color);
            font-size: 2.5rem;
            margin: 0;
            padding: 0;
            background: linear-gradient(120deg, var(--header-color) 0%, var(--link-color) 100%);
            background-clip: text;
            -webkit-background-clip: text;
            color: transparent;
            text-shadow: 0 1px 1px rgba(0,0,0,0.05);
        }
        
        .theme-count {
            display: inline-block;
            background-color: var(--accent-secondary);
            color: white;
            font-weight: bold;
            padding: 0.4rem 1rem;
            border-radius: 2rem;
            margin: 1rem 0;
            font-size: 1.1rem;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .description {
            font-size: 1.1rem;
            max-width: 600px;
            margin: 1rem auto;
            opacity: 0.9;
        }
        
        /* Grid layout */
        .theme-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .theme-card {
            background-color: var(--card-bg);
            border-radius: var(--radius);
            overflow: hidden;
            box-shadow: var(--card-shadow);
            transition: transform var(--transition), box-shadow var(--transition);
            position: relative;
            border: 1px solid var(--border-color);
        }
        
        .theme-card:hover, .theme-card:focus-within {
            transform: translateY(-5px);
            box-shadow: 0 10px 15px rgba(0, 0, 0, 0.1);
        }
        
        .theme-card a {
            display: block;
            padding: 1.5rem;
            text-decoration: none;
            color: var(--link-color);
            font-weight: 500;
            font-size: 1.1rem;
            position: relative;
            z-index: 1;
        }
        
        .theme-card a::after {
            content: "";
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            z-index: -1;
        }
        
        .theme-name {
            font-weight: 600;
            margin-bottom: 0.5rem;
            color: var(--header-color);
            transition: color var(--transition);
        }
        
        .theme-card:hover .theme-name {
            color: var(--link-color);
        }
        
        /* Hover indicator */
        .theme-card::before {
            content: "→";
            position: absolute;
            right: 1.5rem;
            top: 50%;
            transform: translateY(-50%);
            font-size: 1.25rem;
            opacity: 0;
            color: var(--link-color);
            transition: opacity var(--transition), transform var(--transition);
        }
        
        .theme-card:hover::before {
            opacity: 1;
            transform: translate(5px, -50%);
        }
        
        /* Footer styles */
        footer {
            text-align: center;
            margin-top: 3rem;
            padding-top: 1.5rem;
            color: var(--text-color);
            opacity: 0.8;
            font-size: 0.9rem;
            border-top: 1px solid var(--border-color);
            position: relative;
        }
        
        footer::before {
            content: "";
            position: absolute;
            top: -1px;
            left: 50%;
            transform: translateX(-50%);
            width: 100px;
            height: 3px;
            background: linear-gradient(90deg, var(--accent-secondary), var(--link-color));
            border-radius: var(--radius);
        }
        
        /* Responsive adjustments */
        @media (max-width: 768px) {
            .theme-grid {
                grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            }
        }
        
        @media (max-width: 480px) {
            .theme-grid {
                grid-template-columns: 1fr;
            }
            
            h1 {
                font-size: 2rem;
            }
            
            .container {
                padding: 1.5rem 1rem;
            }
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

    # Add grid items for each theme
    for theme in "${themes[@]}"; do
        local safe_theme_name="${theme//&/&amp;}"
        safe_theme_name="${safe_theme_name//</&lt;}"
        safe_theme_name="${safe_theme_name//>/&gt;}"

        cat << EOF >> "$index_file"
            <div class="theme-card">
                <a href="./${theme}/">
                    <div class="theme-name">${safe_theme_name}</div>
                </a>
            </div>
EOF
    done

    # Close the HTML structure
    cat << EOF >> "$index_file"
        </div>

        <footer>
            <p>Generated on ${current_date}</p>
            <p>Base SITE_URL: ${SITE_URL}</p>
        </footer>
    </div>
</body>
</html>
EOF

    success "Index file generated successfully with ${theme_count} themes."
}

# --- Script Execution ---
main() {
    parse_args "$@"  # Pass all script arguments to parser
    check_dependencies
    load_config
    find_themes
    
    # Clean output and cache directories before starting
    info "Cleaning output and cache directories before starting..."
    cleanup_directories
    
    build_previews
    generate_index
    
    # Clean output and cache directories after finishing
    info "Cleaning output and cache directories after finishing..."
    cleanup_directories
    
    info "All ${#themes[@]} theme previews have been generated in '$EXAMPLE_ROOT_DIR'."
    success "Theme preview generation is complete. You can view them by opening '$EXAMPLE_ROOT_DIR/index.html' in your browser."
}

# Run the main function with all script arguments
main "$@"
