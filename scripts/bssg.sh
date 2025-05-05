#!/usr/bin/env bash
#
# BSSG - Bash Static Site Generator
# Main script to manage blog posts and build the site
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# --- Argument Parsing for --config --- START ---
# We need to parse arguments early to catch --config before loading the config.
# This allows the specified config file to override defaults.
CMD_LINE_CONFIG_FILE=""
declare -a OTHER_ARGS # Array to hold arguments not related to --config

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --config)
        if [[ -z "$2" || "$2" == -* ]]; then # Check if value is missing or looks like another flag
            echo -e "${RED}Error: --config option requires a path argument.${NC}" >&2
            exit 1
        fi
        CMD_LINE_CONFIG_FILE="$2"
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option or command
        OTHER_ARGS+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
done

# Restore positional parameters from the filtered arguments
set -- "${OTHER_ARGS[@]}"
# --- Argument Parsing for --config --- END ---

# --- Configuration Override Logic --- START ---
# Priority: --config > BSSG_LCONF > Default (config.sh.local)
FINAL_CONFIG_OVERRIDE=""

if [ -n "$CMD_LINE_CONFIG_FILE" ]; then
    # --config flag was used, prioritize it
    FINAL_CONFIG_OVERRIDE="$CMD_LINE_CONFIG_FILE"
    echo "Info: Using configuration file specified via --config: $FINAL_CONFIG_OVERRIDE"
elif [ -v BSSG_LCONF ] && [ -n "${BSSG_LCONF}" ]; then
    # --config not used, check BSSG_LCONF environment variable
    FINAL_CONFIG_OVERRIDE="${BSSG_LCONF}"
    echo "Info: Using configuration file specified via BSSG_LCONF environment variable: $FINAL_CONFIG_OVERRIDE"
# else
    # Neither --config nor BSSG_LCONF is set, config_loader.sh will check for default config.sh.local
    # No message needed here, config_loader will print messages.
fi
# --- Configuration Override Logic --- END ---

# Load configuration (DEPRECATED - Moved to config_loader.sh)
# CONFIG_FILE="config.sh"
# if [ -f "$CONFIG_FILE" ]; then
#     source "$CONFIG_FILE"
# else
#     echo "Error: Configuration file '$CONFIG_FILE' not found"
#     exit 1
# fi

# Load local configuration overrides if they exist (DEPRECATED - Moved to config_loader.sh)
# LOCAL_CONFIG_FILE="config.sh.local"
# if [ -f "$LOCAL_CONFIG_FILE" ]; then
#     source "$LOCAL_CONFIG_FILE"
#     echo "Local configuration loaded from $LOCAL_CONFIG_FILE"
# fi

# --- Centralized Configuration Loading --- START ---
# Source the config loader script EARLY to set defaults, load configs, and expand paths.
# It handles config.sh, config.sh.local, and site-specific configs sourced via core local file.
# It also EXPORTS all necessary variables for subsequent scripts.
# NOW passes the command-line config path, if provided.

# Define path to config loader relative to this script
BSSG_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export BSSG_SCRIPT_DIR # Export the variable so sub-scripts inherit it
CONFIG_LOADER_SCRIPT="${BSSG_SCRIPT_DIR}/scripts/build/config_loader.sh"

if [ -f "$CONFIG_LOADER_SCRIPT" ]; then
    # Pass the determined configuration override path (or empty string) to the loader script
    # The loader script will handle sourcing it appropriately.
    # shellcheck source=scripts/build/config_loader.sh
    source "$CONFIG_LOADER_SCRIPT" "$FINAL_CONFIG_OVERRIDE"
    echo "Central configuration loaded via config_loader.sh"
    # Note: The echo message regarding the loaded local config is now handled within config_loader.sh
else
    echo -e "${RED}Error: Config loader script not found at '$CONFIG_LOADER_SCRIPT'${NC}" >&2
    exit 1
fi
# --- Centralized Configuration Loading --- END ---

# Terminal colors (still needed here if config_loader doesn't export them, though it should)
RED='${RED:-$(tput setaf 1)}' # Use tput for wider compatibility if not set
GREEN='${GREEN:-$(tput setaf 2)}'
YELLOW='${YELLOW:-$(tput setaf 3)}'
NC='${NC:-$(tput sgr0)}' # Reset color

# Make sure all scripts are executable
chmod +x scripts/*.sh 2>/dev/null || true

# Function to display help information
show_help() {
    echo "BSSG - Bash Static Site Generator (v0.15)"
    echo "========================================="
    echo ""
    echo "Usage: $0 [--config <path>] command [options]"
    echo ""
    echo "Global Options:"
    echo "  --config <path>            Specify a custom configuration file. Overrides BSSG_LCONF"
    echo "                             and the default config.sh.local."
    echo ""
    echo "Environment Variables:"
    echo "  BSSG_LCONF                 Path to a configuration file to use if --config is not set."
    echo ""
    echo "Commands:"
    echo "  post [-html] [draft_file]    Create a new post or continue editing a draft"
    echo "                               Use -html to edit in HTML instead of Markdown"
    echo "  page [-html] [draft_file]    Create a new page or continue editing a draft"
    echo "                               Use -html to edit in HTML instead of Markdown"
    echo "  edit [-n] <post_file>     Edit an existing post"
    echo "                               Use -n to give the post a new name if title changes"
    echo "  delete [-f] <post_file>      Delete a post"
    echo "                               Use -f to skip confirmation"
    echo "  list                         List all posts"
    echo "  tags [-n]                    List all tags"
    echo "                               Use -n to sort by number of posts"
    echo "  drafts                       List all draft posts"
    echo "  backup                       Create a backup of all posts, pages, drafts, and config"
    echo "  restore [backup_file|ID]     Restore from a backup (all content by default)"
    echo "                               Options: --no-content, --no-config"
    echo "  backups                      List all available backups"
    echo "  build                        Build the site"
    echo "  init <target_directory>       Initialize a new site in the specified directory"
    echo "  help                         Show this help message"
    echo ""
    echo "For more information, refer to the README.md file."
}

# Function to display help specific to the build command
show_build_help() {
    echo "Usage: $0 build [options]"
    echo ""
    echo "Build Options:"
    echo "  --src DIR               Override Source directory (from config: ${SRC_DIR:-src})"
    echo "  --pages DIR             Override Pages directory (from config: ${PAGES_DIR:-pages})"
    echo "  --drafts DIR            Override Drafts directory (from config: ${DRAFTS_DIR:-drafts})"
    echo "  --output DIR            Override Output directory (from config: ${OUTPUT_DIR:-output})"
    echo "  --templates DIR         Override Templates directory (from config: ${TEMPLATES_DIR:-templates})"
    echo "  --themes-dir DIR        Override Themes parent directory (from config: ${THEMES_DIR:-themes})"
    echo "  --theme NAME            Override Theme to use (from config: ${THEME:-default})"
    echo "  --static DIR            Override Static directory (from config: ${STATIC_DIR:-static})"
    echo "  --clean-output [bool]   Clean output directory before building (default from config: ${CLEAN_OUTPUT:-false})"
    echo "  --force-rebuild         Force rebuild of all files regardless of modification time"
    echo "  --site-title TITLE      Override Site title"
    echo "  --site-url URL          Override Site URL"
    echo "  --site-description DESC Override Site description"
    echo "  --author-name NAME      Override Author name"
    echo "  --author-email EMAIL    Override Author email"
    echo "  --posts-per-page NUM    Override Posts per page (from config: ${POSTS_PER_PAGE:-10})"
    echo "  --deploy                Force deployment after successful build (overrides config)"
    echo "  --no-deploy             Prevent deployment after build (overrides config)"
    echo "  --help                  Display this build-specific help message and exit"
    echo ""
    echo "Note: These options override settings from configuration files for this build run."
}

# Main function
main() {
    # Arguments are already parsed and filtered by the time main() is called.
    # Positional parameters ($1, $2, etc.) now contain only the command and its specific options.

    local command=""

    # No arguments provided (after potential --config filtering)
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    command="$1"
    shift # Consume the command itself

    case "$command" in
        post)
            scripts/post.sh "$@"
            ;;
        page)
            scripts/page.sh "$@"
            ;;
        edit)
            scripts/edit.sh "$@"
            ;;
        delete)
            scripts/delete.sh "$@"
            ;;
        list)
            scripts/list.sh posts
            ;;
        tags)
            scripts/list.sh tags "$@"
            ;;
        drafts)
            scripts/list.sh drafts
            ;;
        backup)
            scripts/backup.sh backup
            ;;
        restore)
            scripts/restore.sh "$@"
            ;;
        backups)
            scripts/backup.sh list
            ;;
        build)
            # Call the new build orchestrator script in the build/ directory
            # Parse build-specific arguments first and export them as environment variables
            echo "Parsing build-specific arguments..."
            export CMD_DEPLOY_OVERRIDE="unset" # Reset deploy override for this build command

            declare -a build_args=("$@") # Capture args passed to build
            set -- "${build_args[@]}" # Set positional params for parsing

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --src)
                        export SRC_DIR="$2"
                        shift 2
                        ;;
                    --pages)
                        export PAGES_DIR="$2"
                        shift 2
                        ;;
                    --drafts)
                        export DRAFTS_DIR="$2"
                        shift 2
                        ;;
                    --output)
                        export OUTPUT_DIR="$2"
                        shift 2
                        ;;
                    --templates)
                        export TEMPLATES_DIR="$2"
                        shift 2
                        ;;
                    --themes-dir)
                        export THEMES_DIR="$2"
                        shift 2
                        ;;
                    --theme)
                        export THEME="$2"
                        shift 2
                        ;;
                    --static)
                        export STATIC_DIR="$2"
                        shift 2
                        ;;
                    --clean-output)
                        # Handle both flag style (--clean-output) and value style (--clean-output true/false)
                        if [[ "$2" == "true" || "$2" == "false" ]]; then
                            export CLEAN_OUTPUT="$2"
                            shift 2
                        else
                            export CLEAN_OUTPUT=true
                            shift 1
                        fi
                        ;;
                    --force-rebuild)
                        export FORCE_REBUILD=true
                        shift 1
                        ;;
                    -f)
                        export FORCE_REBUILD=true
                        shift 1
                        ;;
                    --site-title)
                        export SITE_TITLE="$2"
                        shift 2
                        ;;
                    --site-url)
                        export SITE_URL="$2"
                        shift 2
                        ;;
                    --site-description)
                        export SITE_DESCRIPTION="$2"
                        shift 2
                        ;;
                    --author-name)
                        export AUTHOR_NAME="$2"
                        shift 2
                        ;;
                    --author-email)
                        export AUTHOR_EMAIL="$2"
                        shift 2
                        ;;
                    --posts-per-page)
                        export POSTS_PER_PAGE="$2"
                        shift 2
                        ;;
                    --deploy)
                        export CMD_DEPLOY_OVERRIDE="true"
                        shift 1
                        ;;
                    --no-deploy)
                        export CMD_DEPLOY_OVERRIDE="false"
                        shift 1
                        ;;
                    --help)
                        show_build_help
                        exit 0
                        ;;
                    *)
                        echo -e "${RED}Error: Unknown build option: $1${NC}"
                        show_build_help
                        exit 1
                        ;;
                esac
            done

            echo "Invoking build process (scripts/build/main.sh)..."
            # Execute the main build script. It will inherit the exported variables.
            scripts/build/main.sh
            ;;
        init)
            # Check if directory argument is provided
            if [ -z "$1" ]; then
                echo -e "${RED}Error: Target directory argument is required for the init command.${NC}"
                echo -e "Usage: $0 init <target_directory>"
                exit 1
            fi
            scripts/init.sh "$1"
            ;;
        help)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Run the main function
# Pass the filtered arguments (command and its options) to main
main "$@" 
