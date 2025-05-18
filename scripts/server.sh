#!/usr/bin/env bash

# --- Configuration ---
DEFAULT_PORT="8000"
DEFAULT_WWW_ROOT="./output"

# Terminal colors for messages (used by both parent and child via export)
RED_LOG=$(tput setaf 1 2>/dev/null || echo "")
GREEN_LOG=$(tput setaf 2 2>/dev/null || echo "")
YELLOW_LOG=$(tput setaf 3 2>/dev/null || echo "")
NC_LOG=$(tput sgr0 2>/dev/null || echo "")

# --- Helper: Log messages to stderr ---
log_msg() {
    echo "[BSSG-Server|$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}
log_debug() {
    # VERBOSE DEBUGGING
    log_msg "DEBUG: $1"
    :
}

# --- HTTP Response function ---
send_response() {
    printf "HTTP/1.1 %s\\r\\n" "$1"
    printf "Content-Type: %s\\r\\n" "$2"
    printf "Content-Length: %s\\r\\n" "$3"
    printf "Server: BSSG-BashServer/0.8\\r\\n"
    printf "Connection: close\\r\\n\\r\\n"
}

# --- Request Handler Function ---
# Relies on ABS_WWW_ROOT, REALPATH_CMD_ACTUAL, STAT_CMD, FILE_CMD, STAT_CMD_IS_WC
# being correctly set in its execution environment (script scope for netcat, inherited env for socat child).
handle_request() {
    local REQUEST_LINE REQUEST_LINE_CLEANED HEADER_LINE METHOD RPATH RPATH_DECODED TARGET_PATH_RELATIVE
    local CANDIDATE_FS_PATH FINAL_PATH_TO_SERVE NORMALIZED_CANDIDATE BODY
    local MIME_TYPE FILE_EXTENSION FILE_EXTENSION_LOWER DETECTED_BY_FILE CONTENT_LENGTH

    IFS= read -r REQUEST_LINE || { log_debug "Handler: Read fail/disconnect or empty request. PID: $$"; return 1; }
    REQUEST_LINE_CLEANED=$(echo "$REQUEST_LINE" | tr -d '\r')
    log_msg "Request: [${REQUEST_LINE_CLEANED}] (PID: $$)"

    while IFS= read -r HEADER_LINE && [[ -n "$HEADER_LINE" && "$HEADER_LINE" != $'\r' ]]; do
        log_debug "Header: [$(echo "$HEADER_LINE"|tr -d '\r')] (PID: $$)"
    done

    METHOD=$(echo "$REQUEST_LINE_CLEANED" | awk '{print $1}')
    RPATH=$(echo "$REQUEST_LINE_CLEANED" | awk '{print $2}')

    if [[ "$METHOD" != "GET" ]]; then
        log_msg "Method not implemented: $METHOD (PID: $$)"
        BODY="501 Not Implemented"; send_response "501 Not Implemented" "text/plain" "${#BODY}"; echo "$BODY"; return 0
    fi

    RPATH_DECODED=$(printf '%b' "${RPATH//%/\\\\x}")
    TARGET_PATH_RELATIVE="${RPATH_DECODED#/}"
    if [[ "$RPATH_DECODED" == "/" || -z "$TARGET_PATH_RELATIVE" ]]; then TARGET_PATH_RELATIVE="index.html"; fi

    log_debug "Child (PID: $$) using ABS_WWW_ROOT: [${ABS_WWW_ROOT}], REALPATH_CMD_ACTUAL: [${REALPATH_CMD_ACTUAL}]"
    CANDIDATE_FS_PATH="$ABS_WWW_ROOT/$TARGET_PATH_RELATIVE"
    log_debug "Child (PID: $$) CANDIDATE_FS_PATH: [${CANDIDATE_FS_PATH}]"
    
    NORMALIZED_CANDIDATE=$($REALPATH_CMD_ACTUAL "$CANDIDATE_FS_PATH" 2>/dev/null)
    local realpath_status=$?
    log_debug "Child (PID: $$) NORMALIZED_CANDIDATE: [${NORMALIZED_CANDIDATE}], realpath status: ${realpath_status}"

    if [[ -z "$NORMALIZED_CANDIDATE" || $realpath_status -ne 0 ]]; then # Check status too
        log_msg "Path resolution failed or path does not exist: '$CANDIDATE_FS_PATH' (decoded: '$RPATH_DECODED'). PID: $$"
        BODY="<html><body><h1>404 Not Found</h1><p>Resource not found or path invalid.</p></body></html>"
        send_response "404 Not Found" "text/html" "${#BODY}"; echo "$BODY"; return 0
    fi

    if [[ "$NORMALIZED_CANDIDATE" != "$ABS_WWW_ROOT" && "${NORMALIZED_CANDIDATE#"$ABS_WWW_ROOT/"}" == "$NORMALIZED_CANDIDATE" ]]; then
        log_msg "Security: Attempt to access path '$NORMALIZED_CANDIDATE' (from '$TARGET_PATH_RELATIVE') outside document root '$ABS_WWW_ROOT'. PID: $$"
        BODY="<html><body><h1>403 Forbidden</h1><p>Access denied.</p></body></html>"
        send_response "403 Forbidden" "text/html" "${#BODY}"; echo "$BODY"; return 0
    fi

    if [[ -d "$NORMALIZED_CANDIDATE" ]]; then
        if [[ -f "$NORMALIZED_CANDIDATE/index.html" && -r "$NORMALIZED_CANDIDATE/index.html" ]]; then FINAL_PATH_TO_SERVE="$NORMALIZED_CANDIDATE/index.html"; 
        else 
            log_msg "Directory listing forbidden for: $NORMALIZED_CANDIDATE (PID: $$)"; BODY="<html><body><h1>403 Forbidden</h1></body></html>"; send_response "403 Forbidden" "text/html" "${#BODY}"; echo "$BODY"; return 0; 
        fi
    elif [[ -f "$NORMALIZED_CANDIDATE" && -r "$NORMALIZED_CANDIDATE" ]]; then FINAL_PATH_TO_SERVE="$NORMALIZED_CANDIDATE"; 
    else 
        log_msg "Not Found or Not Readable: '$NORMALIZED_CANDIDATE' (requested: '$TARGET_PATH_RELATIVE'). PID: $$"; BODY="<html><body><h1>404 Not Found</h1></body></html>"; send_response "404 Not Found" "text/html" "${#BODY}"; echo "$BODY"; return 0; 
    fi
    
    MIME_TYPE="application/octet-stream"
    FILE_EXTENSION="${FINAL_PATH_TO_SERVE##*.}"; FILE_EXTENSION_LOWER=$(echo "$FILE_EXTENSION" | tr '[:upper:]' '[:lower:]')
    case "$FILE_EXTENSION_LOWER" in
        html|htm) MIME_TYPE="text/html; charset=utf-8" ;; css) MIME_TYPE="text/css; charset=utf-8" ;; 
        js) MIME_TYPE="application/javascript; charset=utf-8" ;; json) MIME_TYPE="application/json; charset=utf-8" ;; 
        xml) MIME_TYPE="application/xml; charset=utf-8" ;; txt) MIME_TYPE="text/plain; charset=utf-8" ;; 
        jpg|jpeg) MIME_TYPE="image/jpeg" ;; png) MIME_TYPE="image/png" ;; gif) MIME_TYPE="image/gif" ;; 
        svg) MIME_TYPE="image/svg+xml" ;; ico) MIME_TYPE="image/x-icon" ;; webp) MIME_TYPE="image/webp" ;; 
        woff) MIME_TYPE="font/woff" ;; woff2) MIME_TYPE="font/woff2" ;; 
        *)  if [[ -n "$FILE_CMD" ]]; then DETECTED_BY_FILE=$($FILE_CMD "$FINAL_PATH_TO_SERVE" 2>/dev/null); if [[ -n "$DETECTED_BY_FILE" ]]; then MIME_TYPE="$DETECTED_BY_FILE"; fi; fi ;;
    esac
    
    if $STAT_CMD_IS_WC; then CONTENT_LENGTH=$($STAT_CMD < "$FINAL_PATH_TO_SERVE" | awk '{print $1}'); else CONTENT_LENGTH=$($STAT_CMD "$FINAL_PATH_TO_SERVE" | awk '{print $1}'); fi
    if [[ -z "$CONTENT_LENGTH" ]]; then
        log_msg "Error: Could not determine content length for $FINAL_PATH_TO_SERVE (PID: $$)"; BODY="<html><body><h1>500 Internal Server Error</h1></body></html>"; send_response "500 Internal Server Error" "text/html" "${#BODY}"; echo "$BODY"; return 0
    fi
    log_msg "Serving: '$FINAL_PATH_TO_SERVE' as '$MIME_TYPE' ($CONTENT_LENGTH bytes) (PID: $$)"
    send_response "200 OK" "$MIME_TYPE" "$CONTENT_LENGTH"; cat "$FINAL_PATH_TO_SERVE"; return 0
}

# --- Main Execution Logic ---
if [ "$1" = "__bssg_socat_child__" ]; then
    # Socat child execution path. Inherits necessary variables from parent's environment.
    # Functions are available as it's the same script being executed.
    log_debug "Socat child (PID: $$) started. Using inherited env for config."
    # Essential check: Ensure critical env vars are present, otherwise something is wrong with parent export or child env
    if [ -z "$ABS_WWW_ROOT" ] || [ -z "$REALPATH_CMD_ACTUAL" ] || [ -z "$STAT_CMD" ] || [ -z "$PORT" ]; then
        log_msg "${RED_LOG}Critical Error in Socat child (PID: $$): Essential environment variables not set. Exiting.${NC_LOG}"
        exit 1 # Fatal error for this child
    fi
    handle_request
    exit $?
else
    # Main server instance execution path (parent)

    # --- Portability Determinations & Variable Initializations (Parent Only) ---
    NC_CMD="nc"
    NC_LISTEN_ARGS=""
    NC_CLOSE_OPT=""
    STAT_CMD=""
    STAT_CMD_IS_WC=false
    REALPATH_CMD_ACTUAL=""
    FILE_CMD=""

    NC_HELP_OUTPUT=$(nc -h 2>&1)
    if echo "$NC_HELP_OUTPUT" | grep -q -- '-q[[:space:]]\\+[a-zA-Z_]\\+'; then
        NC_LISTEN_ARGS="-l -p"; NC_CLOSE_OPT="-q 0"; log_debug "Detected GNU-style nc."
    elif echo "$NC_HELP_OUTPUT" | grep -q -- '--apple-'; then
        NC_LISTEN_ARGS="-l"; NC_CLOSE_OPT=""; log_debug "Detected Apple-style nc."
    elif echo "$NC_HELP_OUTPUT" | grep -E '(^|[[:space:]])\\-N([[:space:]]|$)' && \\
        ! echo "$NC_HELP_OUTPUT" | grep -Eq -- '-N[[:space:]]+(<[^>]+>|[a-zA-Z_]+)'; then
        NC_LISTEN_ARGS="-l"; NC_CLOSE_OPT="-N"; log_debug "Detected OpenBSD-style nc."
    else
        NC_LISTEN_ARGS="-l"; NC_CLOSE_OPT=""; log_msg "${YELLOW_LOG}Warning: Basic nc detection.${NC_LOG}"
    fi

    if command -v stat >/dev/null; then
        if stat -c %s . >/dev/null 2>&1; then STAT_CMD="stat -c %s"; log_debug "Using GNU stat.";
        elif stat -f %z . >/dev/null 2>&1; then STAT_CMD="stat -f %z"; log_debug "Using BSD stat.";
        fi
    fi
    if [[ -z "$STAT_CMD" ]]; then
        if command -v wc >/dev/null; then log_msg "${YELLOW_LOG}Warning: 'stat' not ideal. Using 'wc -c'.${NC_LOG}"; STAT_CMD="wc -c"; STAT_CMD_IS_WC=true;
        else log_msg "${RED_LOG}Error: Neither 'stat' nor 'wc' found. Exiting.${NC_LOG}"; exit 1; fi
    fi
    if command -v realpath >/dev/null; then
        if realpath -m . >/dev/null 2>&1; then REALPATH_CMD_ACTUAL="realpath -m"; log_debug "Using 'realpath -m'.";
        elif realpath . >/dev/null 2>&1; then REALPATH_CMD_ACTUAL="realpath"; log_debug "Using 'realpath' (no -m).";
        else log_msg "${RED_LOG}Error: 'realpath' found but unusable. Exiting.${NC_LOG}"; exit 1; fi
    else log_msg "${RED_LOG}Error: 'realpath' not found. Exiting.${NC_LOG}"; exit 1; fi

    if command -v file >/dev/null && file --mime-type --brief . >/dev/null 2>&1; then
        FILE_CMD="file --mime-type --brief"; log_debug "Using 'file' for MIME types.";
    else log_msg "${YELLOW_LOG}Warning: 'file --mime-type --brief' not available.${NC_LOG}"; fi
    # --- End Portability Determinations ---

    # --- Main Server Instance Setup (Parent) ---
    # Note: $1 and $2 are actual arguments passed to server.sh, not the socat child marker.
    CURRENT_PORT="${1:-$DEFAULT_PORT}" # Use a different name to avoid conflict with exported PORT if $1 is empty
    WWW_ROOT_ARG="${2:-$DEFAULT_WWW_ROOT}"

    ABS_WWW_ROOT_CANDIDATE=$($REALPATH_CMD_ACTUAL "$WWW_ROOT_ARG" 2>/dev/null)
    if [[ -z "$ABS_WWW_ROOT_CANDIDATE" ]] || ! $REALPATH_CMD_ACTUAL "$WWW_ROOT_ARG" > /dev/null 2>&1 ; then
        log_msg "${RED_LOG}Error: Document root '$WWW_ROOT_ARG' invalid or could not be resolved. Exiting.${NC_LOG}"; exit 1
    fi
    if [[ ! -d "$ABS_WWW_ROOT_CANDIDATE" ]]; then
        log_msg "${RED_LOG}Error: Document root '$ABS_WWW_ROOT_CANDIDATE' (from '$WWW_ROOT_ARG') is not an existing directory. Exiting.${NC_LOG}"; exit 1
    fi
    ABS_WWW_ROOT="$ABS_WWW_ROOT_CANDIDATE"
    log_msg "Serving files from document root: $ABS_WWW_ROOT"

    SCRIPT_ABS_PATH=""
    _script_dir_temp="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    _script_basename_temp="$(basename "${BASH_SOURCE[0]}")"
    if [ -f "$_script_dir_temp/$_script_basename_temp" ]; then SCRIPT_ABS_PATH="$($REALPATH_CMD_ACTUAL "$_script_dir_temp/$_script_basename_temp")"; else
        if command -v readlink >/dev/null && readlink -f "$0" >/dev/null 2>&1; then SCRIPT_ABS_PATH="$(readlink -f "$0")"; 
        else SCRIPT_ABS_PATH="$($REALPATH_CMD_ACTUAL "$0")"; fi
    fi
    if [[ -z "$SCRIPT_ABS_PATH" || ! -f "$SCRIPT_ABS_PATH" ]]; then
        log_msg "${RED_LOG}Error: Could not determine script absolute path. Exiting.${NC_LOG}"; exit 1
    fi
    log_debug "Server script absolute path resolved to: $SCRIPT_ABS_PATH"

    # Export variables needed by socat children. Use CURRENT_PORT for export as PORT.
    export PORT="$CURRENT_PORT" 
    export ABS_WWW_ROOT 
    export REALPATH_CMD_ACTUAL STAT_CMD STAT_CMD_IS_WC FILE_CMD 
    export NC_LOG RED_LOG YELLOW_LOG GREEN_LOG

    if command -v socat >/dev/null; then
        log_msg "${GREEN_LOG}Info: Found socat. Using socat for multi-threaded server.${NC_LOG}"
        log_msg "Starting server with socat on port ${PORT}. Access at: http://localhost:${PORT} (or configured host)"
        trap '{ log_msg "Shutting down socat server (PID: $$)..."; exit 0; }' EXIT INT TERM
        socat "TCP-LISTEN:${PORT},fork,reuseaddr" "EXEC:${SCRIPT_ABS_PATH} __bssg_socat_child__"
    else
        # Netcat fallback uses CURRENT_PORT directly as it's in the same script scope
        PORT="$CURRENT_PORT" # Ensure PORT var is set for netcat loop if not using exported one
        log_msg "${YELLOW_LOG}Warning: socat not found. Falling back to netcat (single-threaded).${NC_LOG}"
        log_msg "${YELLOW_LOG}This may cause issues with loading multiple resources (like images) simultaneously.${NC_LOG}"
        log_msg "${YELLOW_LOG}For a better experience, please install socat (e.g., 'sudo apt install socat' or 'brew install socat').${NC_LOG}"
        TMP_DIR=$(mktemp -d -t bssg_server_fifo_XXXXXX)
        PIPE="$TMP_DIR/request_pipe"
        mkfifo "$PIPE" || { log_msg "${RED_LOG}Error: mkfifo failed for '$PIPE'. Exiting.${NC_LOG}"; rm -rf "$TMP_DIR"; exit 1; }
        trap '{ log_msg "Shutting down netcat server (PID: $$)..."; rm -rf "$TMP_DIR"; exit 0; }' EXIT INT TERM
        log_msg "Bash HTTP Server (netcat) preparing to listen on port $PORT. Access at: http://localhost:$PORT"
        while true; do
            CURRENT_NC_CMD_BASE=""
            if [[ "$NC_LISTEN_ARGS" == "-l -p" ]]; then CURRENT_NC_CMD_BASE="$NC_CMD $NC_LISTEN_ARGS $PORT $NC_CLOSE_OPT"; 
            elif [[ "$NC_LISTEN_ARGS" == "-l" && "$NC_CLOSE_OPT" == "-N" ]]; then CURRENT_NC_CMD_BASE="$NC_CMD $NC_LISTEN_ARGS $PORT $NC_CLOSE_OPT"; 
            elif [[ "$NC_LISTEN_ARGS" == "-l" && -z "$NC_CLOSE_OPT" ]]; then CURRENT_NC_CMD_BASE="$NC_CMD $NC_LISTEN_ARGS $PORT"; 
            else CURRENT_NC_CMD_BASE="$NC_CMD $NC_LISTEN_ARGS $PORT $NC_CLOSE_OPT"; fi
            CURRENT_NC_CMD_BASE=$(echo "$CURRENT_NC_CMD_BASE" | tr -s ' ')
            log_debug "Netcat command for listening: $CURRENT_NC_CMD_BASE"
            cat "$PIPE" | $CURRENT_NC_CMD_BASE | (handle_request; exit $?) > "$PIPE"
            pipeline_status=$?
            if [[ $pipeline_status -ne 0 && $pipeline_status -ne 1 && $pipeline_status -ne 130 ]]; then
                log_msg "${YELLOW_LOG}Warning: Netcat handler/pipe problem (status: $pipeline_status). Restarting listen.${NC_LOG}"; sleep 1
            elif [[ $pipeline_status -eq 130 ]]; then log_msg "Ctrl+C detected in netcat handler. Exiting server."; exit 130; fi
        done
    fi
fi
