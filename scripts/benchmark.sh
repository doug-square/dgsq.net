#!/usr/bin/env bash
#
# BSSG - Performance Benchmarking Script
# Measures build times and identifies bottlenecks
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine script directory for absolute paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
CONFIG_FILE="$BASE_DIR/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error: Configuration file 'config.sh' not found at $CONFIG_FILE${NC}"
    exit 1
fi

# Function to measure execution time
measure_execution() {
    local description="$1"
    local command="$2"
    
    echo -e "${BLUE}Measuring: ${description}${NC}"
    
    # Take 3 measurements for reliability
    for i in {1..3}; do
        echo -e "  Run $i: " 
        
        # Record start time
        start_time=$(date +%s.%N)
        
        # Execute the command
        eval "$command"
        
        # Record end time
        end_time=$(date +%s.%N)
        
        # Calculate duration
        duration=$(echo "$end_time - $start_time" | bc)
        
        echo -e "    ${GREEN}Completed in: ${duration} seconds${NC}"
        
        # Add to total for average
        total_time=$(echo "$total_time + $duration" | bc)
    done
    
    # Calculate average
    avg_time=$(echo "scale=3; $total_time / 3" | bc)
    echo -e "${YELLOW}Average time for '${description}': ${avg_time} seconds${NC}"
    echo ""
}

# Create test report directory
REPORT_DIR="$BASE_DIR/.benchmark_reports"
mkdir -p "$REPORT_DIR"

# Generate timestamp for this report
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/benchmark_$TIMESTAMP.txt"

# Start benchmarking
{
    echo "BSSG Performance Benchmark Report"
    echo "================================="
    echo "Date: $(date)"
    echo "System: $(uname -a)"
    echo ""
    echo "Configuration:"
    echo "- MARKDOWN_PROCESSOR: $MARKDOWN_PROCESSOR"
    echo "- CLEAN_OUTPUT: $CLEAN_OUTPUT"
    echo "- THEME: $THEME"
    
    if command -v parallel &>/dev/null; then
        echo "- GNU Parallel: Available"
    else
        echo "- GNU Parallel: Not available"
    fi
    
    echo ""
    echo "CPU Info:"
    if command -v lscpu &>/dev/null; then
        lscpu | grep "CPU(s)" | head -1
    elif command -v sysctl &>/dev/null; then
        echo "- $(sysctl -n hw.physicalcpu) physical CPUs, $(sysctl -n hw.logicalcpu) logical CPUs"
    else
        echo "- CPU info not available"
    fi
    echo ""
    
    # Count number of files to process
    echo "Content stats:"
    echo "- Posts: $(find "$BASE_DIR/src" -type f | wc -l)"
    echo "- Pages: $(find "$BASE_DIR/pages" -type f 2>/dev/null | wc -l || echo "0")"
    echo ""
    
    echo "Performance measurements:"
    echo "------------------------"
} | tee "$REPORT_FILE"

# Run benchmark with clean output directory (full build)
{
    echo "Test 1: Full build (clean output)"
    
    # Save current directory
    pushd "$BASE_DIR" > /dev/null
    
    # Ensure output directory is empty
    rm -rf "$BASE_DIR/output"
    mkdir -p "$BASE_DIR/output"
    
    # Measure full build time
    total_time=0
    measure_execution "Full build (clean output)" "time ./bssg.sh build --clean-output"
    
    echo "Test 2: Incremental build (no changes)"
    
    # Measure incremental build time
    total_time=0
    measure_execution "Incremental build (no changes)" "time ./bssg.sh build"
    
    echo "Test 3: Partial changes rebuild"
    
    # Make a small change to a random post to trigger partial rebuild
    RANDOM_POST=$(find "$BASE_DIR/src" -type f | sort | head -1)
    if [ -n "$RANDOM_POST" ]; then
        # Add a comment to the end of the file
        echo "<!-- Modified for benchmark testing: $(date) -->" >> "$RANDOM_POST"
        
        # Measure partial rebuild time
        total_time=0
        measure_execution "Partial rebuild (one file changed)" "time ./bssg.sh build"
        
        # Restore the file
        sed -i.bak '$ d' "$RANDOM_POST"
        rm -f "${RANDOM_POST}.bak"
    else
        echo "No posts found for partial rebuild test"
    fi
    
    echo "Test 4: Force rebuild"
    
    # Measure force rebuild time
    total_time=0
    measure_execution "Force rebuild (rebuild all)" "time ./bssg.sh build --force-rebuild"
    
    # Restore original directory
    popd > /dev/null
    
    echo "Benchmark complete!"
    echo "Report saved to: $REPORT_FILE"
} | tee -a "$REPORT_FILE"

echo -e "${GREEN}Benchmark completed. Report saved to: $REPORT_FILE${NC}" 