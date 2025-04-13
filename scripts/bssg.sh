#!/usr/bin/env bash
#
# BSSG - Bash Static Site Generator
# Main script to manage blog posts and build the site
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
    echo "Local configuration loaded from $LOCAL_CONFIG_FILE"
fi

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Make sure all scripts are executable
chmod +x scripts/*.sh 2>/dev/null || true

# Function to display help information
show_help() {
    echo "BSSG - Bash Static Site Generator (v0.10)"
    echo "=================================="
    echo ""
    echo "Usage: $0 command [options]"
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
    echo "  backup                       Create a backup of all posts, pages, and config"
    echo "  restore [backup_file|ID]     Restore from a backup (all content by default)"
    echo "                               Options: --no-posts, --no-drafts, --no-pages, --no-config"
    echo "  backups                      List all available backups"
    echo "  build                        Build the site"
    echo "  init <target_directory>       Initialize a new site in the specified directory"
    echo "  help                         Show this help message"
    echo ""
    echo "For more information, refer to the README.md file."
}

# Main function
main() {
    local command=""
    
    # No arguments provided
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    command="$1"
    shift
    
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
            # Pass along any additional arguments (e.g., --force-rebuild)
            echo "Invoking new build process..."
            scripts/build/main.sh "$@"
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
main "$@" 
