#!/usr/bin/env bash

# --- Configuration ---
DEFAULT_PORT="8000"
DEFAULT_WWW_ROOT="./output"

# --- Helper: Log messages to stderr ---
log_msg() {
    echo "[BSSG-Server|$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}
log_debug() {
    # VERBOSE DEBUGGING
    log_msg "DEBUG: $1"
    :
}

# --- Portability Checks & Command Setup ---
NC_CMD="nc"
NC_LISTEN_ARGS=""
NC_CLOSE_OPT=""
STAT_CMD=""
STAT_CMD_IS_WC=false
REALPATH_CMD_ACTUAL=""
HAS_REALPATH_M=false
FILE_CMD=""

NC_HELP_OUTPUT=$(nc -h 2>&1)
if echo "$NC_HELP_OUTPUT" | grep -q -- '-q[[:space:]]\+[a-zA-Z_]\+'; then
    NC_LISTEN_ARGS="-l -p"; NC_CLOSE_OPT="-q 0"
    log_debug "Detected GNU-style nc. Listen args: '$NC_LISTEN_ARGS', Close opt: '$NC_CLOSE_OPT'"
elif echo "$NC_HELP_OUTPUT" | grep -q -- '--apple-'; then
    NC_LISTEN_ARGS="-l"; NC_CLOSE_OPT=""
    log_debug "Detected Apple-style nc. Listen args: '$NC_LISTEN_ARGS', Close opt: (none, relying on default EOF close)"
elif echo "$NC_HELP_OUTPUT" | grep -E '(^|[[:space:]])\-N([[:space:]]|$)' && \
     ! echo "$NC_HELP_OUTPUT" | grep -Eq -- '-N[[:space:]]+(<[^>]+>|[a-zA-Z_]+)'; then
    NC_LISTEN_ARGS="-l"; NC_CLOSE_OPT="-N"
    log_debug "Detected OpenBSD-style nc (with -N for EOF close). Listen args: '$NC_LISTEN_ARGS', Close opt: '$NC_CLOSE_OPT'"
else
    NC_LISTEN_ARGS="-l"; NC_CLOSE_OPT=""
    log_msg "Warning: Could not robustly determine specific nc type/options. Using basic listen ('-l <port>') and hoping for default EOF close behavior."
fi

if command -v stat >/dev/null; then
    if stat -c %s . >/dev/null 2>&1; then STAT_CMD="stat -c %s"; log_debug "Using GNU stat.";
    elif stat -f %z . >/dev/null 2>&1; then STAT_CMD="stat -f %z"; log_debug "Using BSD stat.";
    fi
fi
if [[ -z "$STAT_CMD" ]]; then
    if command -v wc >/dev/null; then log_msg "Warning: 'stat' not ideal. Using 'wc -c'."; STAT_CMD="wc -c"; STAT_CMD_IS_WC=true;
    else log_msg "Error: Neither 'stat' nor 'wc' found. Exiting."; exit 1; fi
fi
if command -v realpath >/dev/null; then
    if realpath -m . >/dev/null 2>&1; then REALPATH_CMD_ACTUAL="realpath -m"; HAS_REALPATH_M=true; log_debug "Using 'realpath -m'.";
    elif realpath . >/dev/null 2>&1; then REALPATH_CMD_ACTUAL="realpath"; HAS_REALPATH_M=false; log_debug "Using 'realpath' (no -m).";
    else log_msg "Error: 'realpath' found but unusable. Exiting."; exit 1; fi
else log_msg "Error: 'realpath' not found. Exiting."; exit 1; fi
if command -v file >/dev/null && file --mime-type --brief . >/dev/null 2>&1; then
    FILE_CMD="file --mime-type --brief"; log_debug "Using 'file' for MIME types.";
else log_msg "Warning: 'file --mime-type --brief' not available. Defaulting MIME type."; fi

PORT="${1:-$DEFAULT_PORT}"
WWW_ROOT_ARG="${2:-$DEFAULT_WWW_ROOT}"
ABS_WWW_ROOT_CANDIDATE=$($REALPATH_CMD_ACTUAL "$WWW_ROOT_ARG" 2>/dev/null)
if [[ -z "$ABS_WWW_ROOT_CANDIDATE" ]] || ! $REALPATH_CMD_ACTUAL "$WWW_ROOT_ARG" > /dev/null 2>&1 ; then
    log_msg "Error: Document root '$WWW_ROOT_ARG' invalid or could not be resolved. Exiting."; exit 1
fi
if [[ ! -d "$ABS_WWW_ROOT_CANDIDATE" ]]; then
    log_msg "Error: Document root '$ABS_WWW_ROOT_CANDIDATE' (from '$WWW_ROOT_ARG') is not an existing directory. Exiting."; exit 1
fi
ABS_WWW_ROOT="$ABS_WWW_ROOT_CANDIDATE"
log_msg "Serving files from document root: $ABS_WWW_ROOT"

TMP_DIR=$(mktemp -d -t bssg_server_fifo_XXXXXX)
PIPE="$TMP_DIR/request_pipe"
mkfifo "$PIPE" || { log_msg "Error: mkfifo failed for '$PIPE'. Exiting."; rm -rf "$TMP_DIR"; exit 1; }
trap '{ log_msg "Shutting down server..."; rm -rf "$TMP_DIR"; exit 0; }' EXIT INT TERM
log_msg "Bash HTTP Server preparing to listen on port $PORT. Access at: http://localhost:$PORT"

send_response() {
    printf "HTTP/1.1 %s\r\n" "$1"; printf "Content-Type: %s\r\n" "$2"
    printf "Content-Length: %s\r\n" "$3"; printf "Server: BSSG-BashServer/0.6\r\n"
    printf "Connection: close\r\n\r\n"
}

while true; do
    _NC_VERBOSITY_FLAG="-v"
    if [[ "$NC_LISTEN_ARGS" == "-l -p" ]]; then # GNU style, port is separate argument after -p
        CURRENT_NC_CMD="$NC_CMD $_NC_VERBOSITY_FLAG $NC_LISTEN_ARGS $PORT $NC_CLOSE_OPT"
    elif [[ "$NC_LISTEN_ARGS" == "-l" && "$NC_CLOSE_OPT" == "-N" ]]; then # OpenBSD style with -N
        CURRENT_NC_CMD="$NC_CMD $_NC_VERBOSITY_FLAG $NC_LISTEN_ARGS $PORT $NC_CLOSE_OPT"
    elif [[ "$NC_LISTEN_ARGS" == "-l" && -z "$NC_CLOSE_OPT" ]]; then # Apple or true fallback, try general verbose listen
        CURRENT_NC_CMD="$NC_CMD -v $NC_LISTEN_ARGS $PORT"
    else # A catch-all for any other combination from detection, or if detection was poor
        CURRENT_NC_CMD="$NC_CMD $_NC_VERBOSITY_FLAG $NC_LISTEN_ARGS $PORT $NC_CLOSE_OPT"
    fi
    CURRENT_NC_CMD=$(echo "$CURRENT_NC_CMD" | tr -s ' ') # Remove extra spaces
    log_msg "Attempting to listen with: $CURRENT_NC_CMD"

    cat "$PIPE" | $CURRENT_NC_CMD | (
        REQUEST_LINE=""; IFS= read -r REQUEST_LINE || { log_debug "Handler: Read fail/disconnect."; exit 1; }
        REQUEST_LINE_CLEANED=$(echo "$REQUEST_LINE" | tr -d '\r'); log_msg "Request: [${REQUEST_LINE_CLEANED}]"
        while IFS= read -r HEADER_LINE && [[ -n "$HEADER_LINE" && "$HEADER_LINE" != $'\r' ]]; do log_debug "Header: [$(echo "$HEADER_LINE"|tr -d '\r')]"; done
        METHOD=$(echo "$REQUEST_LINE_CLEANED" | awk '{print $1}'); RPATH=$(echo "$REQUEST_LINE_CLEANED" | awk '{print $2}')
        if [[ "$METHOD" != "GET" ]]; then log_msg "Method not implemented: $METHOD"; BODY="501 Not Implemented"; send_response "501 Not Implemented" "text/plain" "${#BODY}"; echo "$BODY"; exit 0; fi
        RPATH_DECODED=$(printf '%b' "${RPATH//%/\\x}"); TARGET_PATH_RELATIVE="${RPATH_DECODED#/}"
        if [[ "$RPATH_DECODED" == "/" ]]; then TARGET_PATH_RELATIVE="index.html"; fi
        CANDIDATE_FS_PATH="$ABS_WWW_ROOT/$TARGET_PATH_RELATIVE"; FINAL_PATH_TO_SERVE=""
        NORMALIZED_CANDIDATE=$($REALPATH_CMD_ACTUAL "$CANDIDATE_FS_PATH" 2>/dev/null)
        if [[ -n "$NORMALIZED_CANDIDATE" && "${NORMALIZED_CANDIDATE#"$ABS_WWW_ROOT"}" == "$NORMALIZED_CANDIDATE" && "$NORMALIZED_CANDIDATE" != "$ABS_WWW_ROOT" ]]; then
            log_msg "Security: Norm path '$NORMALIZED_CANDIDATE' outside '$ABS_WWW_ROOT'."; BODY="<html><body><h1>400 Bad Request</h1></body></html>"; send_response "400 Bad Request" "text/html" "${#BODY}"; echo "$BODY"; exit 0;
        fi
        if [[ -d "$CANDIDATE_FS_PATH" ]]; then
            if [[ -f "$CANDIDATE_FS_PATH/index.html" && -r "$CANDIDATE_FS_PATH/index.html" ]]; then FINAL_PATH_TO_SERVE="$CANDIDATE_FS_PATH/index.html";
            else log_msg "Dir listing forbidden: $CANDIDATE_FS_PATH"; BODY="<html><body><h1>403 Forbidden</h1></body></html>"; send_response "403 Forbidden" "text/html" "${#BODY}"; echo "$BODY"; exit 0; fi
        elif [[ -f "$CANDIDATE_FS_PATH" && -r "$CANDIDATE_FS_PATH" ]]; then FINAL_PATH_TO_SERVE="$CANDIDATE_FS_PATH";
        else log_msg "Not Found/Readable: '$CANDIDATE_FS_PATH' (req: '$RPATH_DECODED')"; BODY="<html><body><h1>404 Not Found</h1></body></html>"; send_response "404 Not Found" "text/html" "${#BODY}"; echo "$BODY"; exit 0; fi
        RESOLVED_ACTUAL_PATH_TO_SERVE=$($REALPATH_CMD_ACTUAL "$FINAL_PATH_TO_SERVE" 2>/dev/null)
        if [[ -z "$RESOLVED_ACTUAL_PATH_TO_SERVE" ]] || \
           [[ "${RESOLVED_ACTUAL_PATH_TO_SERVE#"$ABS_WWW_ROOT"}" == "$RESOLVED_ACTUAL_PATH_TO_SERVE" && "$RESOLVED_ACTUAL_PATH_TO_SERVE" != "$ABS_WWW_ROOT" ]]; then
            log_msg "Security: Final path '$RESOLVED_ACTUAL_PATH_TO_SERVE' outside '$ABS_WWW_ROOT'."; BODY="<html><body><h1>400 Bad Request</h1></body></html>"; send_response "400 Bad Request" "text/html" "${#BODY}"; echo "$BODY"; exit 0;
        fi

        MIME_TYPE="application/octet-stream"
        FILE_EXTENSION="${RESOLVED_ACTUAL_PATH_TO_SERVE##*.}"
        FILE_EXTENSION_LOWER=$(echo "$FILE_EXTENSION" | tr '[:upper:]' '[:lower:]')
        case "$FILE_EXTENSION_LOWER" in
            html|htm) MIME_TYPE="text/html" ;;
            css)      MIME_TYPE="text/css" ;;
            js)       MIME_TYPE="application/javascript" ;;
            json)     MIME_TYPE="application/json" ;;
            xml)      MIME_TYPE="application/xml" ;;
            txt)      MIME_TYPE="text/plain" ;;
            jpg|jpeg) MIME_TYPE="image/jpeg" ;;
            png)      MIME_TYPE="image/png" ;;
            gif)      MIME_TYPE="image/gif" ;;
            svg)      MIME_TYPE="image/svg+xml" ;;
            ico)      MIME_TYPE="image/x-icon" ;; # Common name for favicon
            webp)     MIME_TYPE="image/webp" ;;
            woff)     MIME_TYPE="font/woff" ;;
            woff2)    MIME_TYPE="font/woff2" ;;
            *)  if [[ -n "$FILE_CMD" ]]; then
                    DETECTED_BY_FILE=$($FILE_CMD "$RESOLVED_ACTUAL_PATH_TO_SERVE" 2>/dev/null)
                    if [[ -n "$DETECTED_BY_FILE" ]]; then MIME_TYPE="$DETECTED_BY_FILE"; fi
                fi ;;
        esac
        
        CONTENT_LENGTH=""; if $STAT_CMD_IS_WC; then CONTENT_LENGTH=$($STAT_CMD < "$RESOLVED_ACTUAL_PATH_TO_SERVE" | awk '{print $1}'); else CONTENT_LENGTH=$($STAT_CMD "$RESOLVED_ACTUAL_PATH_TO_SERVE" | awk '{print $1}'); fi
        if [[ -z "$CONTENT_LENGTH" ]]; then log_msg "Error: No content length for $RESOLVED_ACTUAL_PATH_TO_SERVE"; BODY="<html><body><h1>500 Internal Server Error</h1></body></html>"; send_response "500 Error" "text/html" "${#BODY}"; echo "$BODY"; exit 0; fi
        log_msg "Serving: '$RESOLVED_ACTUAL_PATH_TO_SERVE' ($MIME_TYPE, $CONTENT_LENGTH bytes)"
        send_response "200 OK" "$MIME_TYPE" "$CONTENT_LENGTH"; cat "$RESOLVED_ACTUAL_PATH_TO_SERVE"
    ) > "$PIPE"
    pipeline_status=$?
    if [[ $pipeline_status -ne 0 && $pipeline_status -ne 130 ]]; then log_msg "Warning: Handler/pipe problem (status: $pipeline_status). Restarting."; sleep 1;
    elif [[ $pipeline_status -eq 130 ]]; then log_msg "Ctrl+C in handler. Exiting."; exit 130; fi
done
