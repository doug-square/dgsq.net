#!/usr/bin/env bash
#
# BSSG - Command Line Interface Handling
# Functions for parsing arguments and showing help.
#

# Parse command line arguments
parse_args() {
    # Initialize deploy override flag
    CMD_DEPLOY_OVERRIDE="unset"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                # Save current settings that may have come from local config
                local saved_theme="$THEME"
                local saved_site_title="$SITE_TITLE"
                local saved_site_url="$SITE_URL"
                local saved_site_description="$SITE_DESCRIPTION"
                local saved_author_name="$AUTHOR_NAME"
                local saved_author_email="$AUTHOR_EMAIL"
                local saved_clean_output="$CLEAN_OUTPUT"

                # Load the specified config file
                CONFIG_FILE="$2"
                if [ -f "$CONFIG_FILE" ]; then
                    # Reset to defaults before loading new config
                    THEME="default"
                    SITE_TITLE="My Journal"
                    SITE_DESCRIPTION="A personal journal and introspective newspaper"
                    SITE_URL="http://localhost"
                    AUTHOR_NAME="Anonymous"
                    AUTHOR_EMAIL="anonymous@example.com"
                    CLEAN_OUTPUT=false

                    # Load new config
                    source "$CONFIG_FILE"
                    echo -e "${GREEN}Configuration loaded from $CONFIG_FILE${NC}"

                    # Load local configuration if it exists
                    local local_config="${CONFIG_FILE}.local"
                    if [ -f "$local_config" ]; then
                        source "$local_config"
                        echo -e "${GREEN}Local configuration loaded from $local_config${NC}"
                    else
                        # If new local config doesn't exist, restore settings from previous local config
                        # but only if they weren't set in the new config file
                        if [ "$THEME" = "default" ] && [ "$saved_theme" != "default" ]; then
                            THEME="$saved_theme"
                        fi
                        if [ "$SITE_TITLE" = "My Journal" ] && [ "$saved_site_title" != "My Journal" ]; then
                            SITE_TITLE="$saved_site_title"
                        fi
                        if [ "$SITE_URL" = "http://localhost" ] && [ "$saved_site_url" != "http://localhost" ]; then
                            SITE_URL="$saved_site_url"
                        fi
                        if [ "$AUTHOR_NAME" = "Anonymous" ] && [ "$saved_author_name" != "Anonymous" ]; then
                            AUTHOR_NAME="$saved_author_name"
                        fi
                        if [ "$AUTHOR_EMAIL" = "anonymous@example.com" ] && [ "$saved_author_email" != "anonymous@example.com" ]; then
                            AUTHOR_EMAIL="$saved_author_email"
                        fi
                        if [ "$CLEAN_OUTPUT" = false ] && [ "$saved_clean_output" != false ]; then
                            CLEAN_OUTPUT="$saved_clean_output"
                        fi
                    fi
                else
                    echo -e "${RED}Error: Configuration file '$CONFIG_FILE' not found${NC}"
                    exit 1
                fi
                shift 2
                ;;
            --src)
                SRC_DIR="$2"
                shift 2
                ;;
            --pages)
                PAGES_DIR="$2"
                shift 2
                ;;
            --drafts)
                DRAFTS_DIR="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --templates)
                TEMPLATES_DIR="$2"
                shift 2
                ;;
            --themes-dir)
                THEMES_DIR="$2"
                shift 2
                ;;
            --theme)
                THEME="$2"
                shift 2
                ;;
            --static)
                STATIC_DIR="$2"
                shift 2
                ;;
            --clean-output)
                # Handle both flag style (--clean-output) and value style (--clean-output true/false)
                if [[ "$2" == "true" || "$2" == "false" ]]; then
                    CLEAN_OUTPUT="$2"
                    shift 2
                else
                    CLEAN_OUTPUT=true
                    shift 1
                fi
                ;;
            --force-rebuild)
                FORCE_REBUILD=true
                shift 1
                ;;
            --site-title)
                SITE_TITLE="$2"
                shift 2
                ;;
            --site-url)
                SITE_URL="$2"
                shift 2
                ;;
            --site-description)
                SITE_DESCRIPTION="$2"
                shift 2
                ;;
            --author-name)
                AUTHOR_NAME="$2"
                shift 2
                ;;
            --author-email)
                AUTHOR_EMAIL="$2"
                shift 2
                ;;
            --posts-per-page)
                POSTS_PER_PAGE="$2"
                shift 2
                ;;
            --local-config)
                # Load the local config file directly
                if [ -f "$2" ]; then
                    source "$2"
                    echo -e "${GREEN}Local configuration loaded from $2${NC}"
                else
                    echo -e "${YELLOW}Warning: Local config file $2 not found${NC}"
                fi
                shift 2
                ;;
            --deploy)
                CMD_DEPLOY_OVERRIDE="true"
                shift 1
                ;;
            --no-deploy)
                CMD_DEPLOY_OVERRIDE="false"
                shift 1
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# Display help information
show_help() {
    echo "BSSG - Bash Static Site Generator"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --config FILE           Configuration file (default: config.sh)"
    echo "  --src DIR               Source directory containing markdown files (default: src)"
    echo "  --pages DIR             Pages directory containing markdown/html files (default: pages)"
    echo "  --drafts DIR            Drafts directory (default: drafts)"
    echo "  --output DIR            Output directory for the generated site (default: output)"
    echo "  --templates DIR         Templates directory (default: templates)"
    echo "  --themes-dir DIR        Themes parent directory (default: themes)"
    echo "  --theme NAME            Theme to use (default: default)"
    echo "  --static DIR            Static directory (default: static)"
    echo "  --clean-output          Clean output directory before building (default: false)"
    echo "  --force-rebuild         Force rebuild of all files regardless of modification time"
    echo "  --site-title TITLE      Site title (default: My Journal)"
    echo "  --site-url URL          Site URL (default: http://localhost)"
    echo "  --site-description DESC Site description (default: A personal journal)"
    echo "  --author-name NAME      Author name (default: Anonymous)"
    echo "  --author-email EMAIL    Author email (default: anonymous@example.com)"
    echo "  --posts-per-page NUM    Posts per page (default: 10)"
    echo "  --local-config FILE     Load local configuration file directly"
    echo "  --deploy                Force deployment after successful build (overrides config)"
    echo "  --no-deploy             Prevent deployment after build (overrides config)"
    echo "  --help                  Display this help message and exit"
} 