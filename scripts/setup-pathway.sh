#!/usr/bin/env bash
#
# setup-pathway.sh: Manages network routing pathways.
#
# This script is the controller for adding or removing the network rules
# required for a specific fwmark-defined pathway.
#
# It can be called with a raw fwmark number or a service instance name.
#
# Usage:
#   ./setup-pathway.sh add <fwmark | instance_name>
#   ./setup-pathway.sh del <fwmark | instance_name>
#   ./setup-pathway.sh add-all
#   ./setup-pathway.sh del-all

set -euo pipefail
shopt -s nocasematch
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the parser library to allow looking up fwmarks by instance name
source "${SCRIPT_DIR}/instance-parser.sh"

manage_pathway() {
    local action=$1
    local fwmark=$2
    local table=$fwmark # Use the same number for the table for simplicity

    echo "--- ${action^}ing pathway for fwmark ${fwmark} (table: ${table}) ---"

    for component in ip-rule ip-route iptables-connmark; do
        "${SCRIPT_DIR}/network-rules/${component}.sh" "${action}" "${fwmark}" "${table}"
    done

    echo "--- Pathway for fwmark ${fwmark} successfully managed ---"
    echo
}

# --- Main Execution ---

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

ACTION=${1:-}
TARGET=${2:-}

get_fwmark_from_target() {
    local target_name=$1
    local fwmark=""
    # Check if target is a number (fwmark) or a string (instance name)
    if [[ "$target_name" =~ ^[0-9]+$ ]]; then
        fwmark=$target_name
    else
        # It's an instance name, look up the fwmark
        # We need to get the full instance details and extract the first field (fwmark)
        local details
        details=$(get_instance_details "$target_name")
        if [ $? -ne 0 ]; then
            echo "$details" # Print error from parser
            return 1
        fi
        fwmark=$(echo "$details" | head -n 1)
        echo "Looked up instance '${target_name}', found fwmark '${fwmark}'." >&2
    fi
    echo "$fwmark"
}

case "$ACTION" in
    add)
        [ -z "$TARGET" ] && { echo "Error: fwmark or instance name required for 'add' action."; exit 1; }
        FWMARK=$(get_fwmark_from_target "$TARGET")
        if [ $? -ne 0 ]; then exit 1; fi
        manage_pathway "add" "$FWMARK"
        ;;
    del)
        [ -z "$TARGET" ] && { echo "Error: fwmark or instance name required for 'del' action."; exit 1; }
        FWMARK=$(get_fwmark_from_target "$TARGET")
        if [ $? -ne 0 ]; then exit 1; fi
        manage_pathway "del" "$FWMARK"
        ;;
    add-all|del-all)
        PATHWAYS_FILE="${SCRIPT_DIR}/../config/pathways.conf"
        if [ ! -f "$PATHWAYS_FILE" ]; then
            echo "Pathways config file not found: ${PATHWAYS_FILE}"
            exit 1
        fi

        rule_action=${ACTION%-all} # "add" or "del"
        
        while read -r fwmark_from_file || [ -n "$fwmark_from_file" ]; do
            # Skip comments and empty lines
            [[ "$fwmark_from_file" =~ ^# ]] || [ -z "$fwmark_from_file" ] && continue
            manage_pathway "$rule_action" "$fwmark_from_file"
        done < "$PATHWAYS_FILE"
        ;;
    *)
        echo "Usage: $0 {add|del <fwmark | instance_name> | add-all | del-all}"
        exit 1
        ;;
esac

echo "Operation completed successfully." 