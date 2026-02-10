#!/usr/bin/env bash
#
# BSSG - RAM Build Helpers
# Preloads input content in memory and provides lookup helpers.
#

# Guard against duplicate sourcing
if [[ -n "${BSSG_RAM_MODE_SCRIPT_LOADED:-}" ]]; then
    return 0
fi
export BSSG_RAM_MODE_SCRIPT_LOADED=1

# In-memory stores
declare -gA BSSG_RAM_FILE_CONTENT=()
declare -gA BSSG_RAM_FILE_MTIME=()
declare -gA BSSG_RAM_DATASET=()
declare -gA BSSG_RAM_BASENAME_KEY=()
declare -ga BSSG_RAM_SRC_FILES=()
declare -ga BSSG_RAM_PAGE_FILES=()
declare -ga BSSG_RAM_TEMPLATE_FILES=()

ram_mode_enabled() {
    [[ "${BSSG_RAM_MODE:-false}" == "true" ]]
}

_ram_mode_disk_mtime() {
    local file="$1"
    local kernel_name
    kernel_name=$(uname -s)
    if [[ "$kernel_name" == "Darwin" ]] || [[ "$kernel_name" == *"BSD" ]]; then
        stat -f "%m" "$file" 2>/dev/null || echo "0"
    else
        stat -c "%Y" "$file" 2>/dev/null || echo "0"
    fi
}

ram_mode_resolve_key() {
    local file="$1"
    if [[ -n "${BSSG_RAM_FILE_CONTENT[$file]+_}" || -n "${BSSG_RAM_FILE_MTIME[$file]+_}" ]]; then
        echo "$file"
        return 0
    fi

    if [[ "$file" == /* && -n "${BSSG_PROJECT_ROOT:-}" ]]; then
        local prefix="${BSSG_PROJECT_ROOT%/}/"
        if [[ "$file" == "$prefix"* ]]; then
            local rel="${file#"$prefix"}"
            if [[ -n "${BSSG_RAM_FILE_CONTENT[$rel]+_}" || -n "${BSSG_RAM_FILE_MTIME[$rel]+_}" ]]; then
                echo "$rel"
                return 0
            fi
        fi
    fi

    if [[ "$file" != */* && -n "${BSSG_RAM_BASENAME_KEY[$file]+_}" ]]; then
        local mapped="${BSSG_RAM_BASENAME_KEY[$file]}"
        if [[ "$mapped" != "__AMBIGUOUS__" ]]; then
            echo "$mapped"
            return 0
        fi
    fi

    echo "$file"
    return 0
}

ram_mode_has_file() {
    local key
    key=$(ram_mode_resolve_key "$1")
    [[ -n "${BSSG_RAM_FILE_CONTENT[$key]+_}" || -n "${BSSG_RAM_FILE_MTIME[$key]+_}" ]]
}

ram_mode_get_content() {
    local key
    key=$(ram_mode_resolve_key "$1")
    if [[ -n "${BSSG_RAM_FILE_CONTENT[$key]+_}" ]]; then
        printf '%s' "${BSSG_RAM_FILE_CONTENT[$key]}"
    fi
}

ram_mode_get_mtime() {
    local key
    key=$(ram_mode_resolve_key "$1")
    if [[ -n "${BSSG_RAM_FILE_MTIME[$key]+_}" ]]; then
        printf '%s\n' "${BSSG_RAM_FILE_MTIME[$key]}"
    else
        printf '0\n'
    fi
}

ram_mode_list_src_files() {
    printf '%s\n' "${BSSG_RAM_SRC_FILES[@]}"
}

ram_mode_list_page_files() {
    printf '%s\n' "${BSSG_RAM_PAGE_FILES[@]}"
}

ram_mode_set_dataset() {
    local key="$1"
    local value="$2"
    BSSG_RAM_DATASET["$key"]="$value"
}

ram_mode_get_dataset() {
    local key="$1"
    if [[ -n "${BSSG_RAM_DATASET[$key]+_}" ]]; then
        printf '%s' "${BSSG_RAM_DATASET[$key]}"
    fi
}

ram_mode_clear_dataset() {
    local key="$1"
    unset 'BSSG_RAM_DATASET[$key]'
}

ram_mode_dataset_line_count() {
    local key="$1"
    local data
    data=$(ram_mode_get_dataset "$key")
    if [[ -z "$data" ]]; then
        echo "0"
        return 0
    fi
    printf '%s\n' "$data" | awk 'NF { c++ } END { print c+0 }'
}

_ram_mode_store_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local file_content
    file_content=$(cat "$file")
    BSSG_RAM_FILE_CONTENT["$file"]="$file_content"
    BSSG_RAM_FILE_MTIME["$file"]="$(_ram_mode_disk_mtime "$file")"

    local base
    base=$(basename "$file")
    if [[ -z "${BSSG_RAM_BASENAME_KEY[$base]+_}" ]]; then
        BSSG_RAM_BASENAME_KEY["$base"]="$file"
    elif [[ "${BSSG_RAM_BASENAME_KEY[$base]}" != "$file" ]]; then
        BSSG_RAM_BASENAME_KEY["$base"]="__AMBIGUOUS__"
    fi
}

_ram_mode_collect_content_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    find "$dir" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" | sort
}

_ram_mode_collect_template_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    find "$dir" -type f -name "*.html" -not -path "*/.*" | sort
}

ram_mode_preload_inputs() {
    if ! ram_mode_enabled; then
        return 0
    fi

    BSSG_RAM_FILE_CONTENT=()
    BSSG_RAM_FILE_MTIME=()
    BSSG_RAM_DATASET=()
    BSSG_RAM_BASENAME_KEY=()
    BSSG_RAM_SRC_FILES=()
    BSSG_RAM_PAGE_FILES=()
    BSSG_RAM_TEMPLATE_FILES=()

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        BSSG_RAM_SRC_FILES+=("$file")
        _ram_mode_store_file "$file"
    done < <(_ram_mode_collect_content_files "${SRC_DIR:-src}")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        BSSG_RAM_PAGE_FILES+=("$file")
        _ram_mode_store_file "$file"
    done < <(_ram_mode_collect_content_files "${PAGES_DIR:-pages}")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        BSSG_RAM_TEMPLATE_FILES+=("$file")
        _ram_mode_store_file "$file"
    done < <(_ram_mode_collect_template_files "${TEMPLATES_DIR:-templates}")

    # Preload active locale (and fallback locale) so date/menu rendering avoids disk reads.
    if [[ -f "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh" ]]; then
        _ram_mode_store_file "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh"
    fi
    if [[ -f "${LOCALE_DIR:-locales}/en.sh" ]]; then
        _ram_mode_store_file "${LOCALE_DIR:-locales}/en.sh"
    fi

    print_info "RAM mode preloaded ${#BSSG_RAM_FILE_CONTENT[@]} text files (${#BSSG_RAM_SRC_FILES[@]} posts, ${#BSSG_RAM_PAGE_FILES[@]} pages)."
}

export -f ram_mode_enabled ram_mode_resolve_key ram_mode_has_file ram_mode_get_content ram_mode_get_mtime
export -f ram_mode_list_src_files ram_mode_list_page_files ram_mode_preload_inputs
export -f ram_mode_set_dataset ram_mode_get_dataset ram_mode_clear_dataset
export -f ram_mode_dataset_line_count
