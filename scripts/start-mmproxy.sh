#!/usr/bin/env bash
#
# start-mmproxy.sh: A generalized script to start an mmproxy instance.
#
# This script sources a configuration file and launches the go-mmproxy
# binary with parameters specific to the provided instance name.
#
# Usage: ./start-mmproxy.sh <instance_name>
# Example: ./start-mmproxy.sh vps01

set -euo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# --- Argument Check ---
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <instance_name>"
    exit 1
fi
INSTANCE_NAME=$1

# --- Configuration & Library ---
# Source shared library
source "${SCRIPT_DIR}/instance-parser.sh"

# --- Parameter Assignment ---
INSTANCE_DETAILS_STR=$(get_instance_details "$INSTANCE_NAME")
if [ $? -ne 0 ]; then
    echo "$INSTANCE_DETAILS_STR" # Print error message from the parser
    exit 1
fi

# Read the details into an array. Each line from the parser becomes an element.
mapfile -t INSTANCE_DETAILS <<< "$INSTANCE_DETAILS_STR"

FWMARK=${INSTANCE_DETAILS[0]}
LISTEN_ADDR=${INSTANCE_DETAILS[1]}
TARGET_IPV4=${INSTANCE_DETAILS[2]}
TARGET_PORT=${INSTANCE_DETAILS[3]}
TARGET_IPV6=${INSTANCE_DETAILS[4]}

# --- Idempotency Check ---
# Create a unique pattern to identify if this specific instance is already running.
# We use the listen address as it's guaranteed to be unique. The fwmark is a
# strong secondary identifier.
PGREP_PATTERN="go-mmproxy.*-l ${LISTEN_ADDR}.*-mark ${FWMARK}"
if pgrep -f "${PGREP_PATTERN}" > /dev/null; then
    echo "Idempotency check: mmproxy instance '${INSTANCE_NAME}' is already running."
    pgrep -af "${PGREP_PATTERN}"
    exit 0
fi


# Check if the binary exists. Note: MMPROXY_BIN is no longer in a config file.
# You may need to set it as an environment variable or hardcode it here.
MMPROXY_BIN=${MMPROXY_BIN:-"/opt/mmproxy/bin/go-mmproxy"}
ALLOW_LIST_PATH=${ALLOW_LIST_PATH:-"/opt/mmproxy/config/allow.txt"}

# --- Main Execution ---
echo "Starting mmproxy for instance: ${INSTANCE_NAME}..."
echo "  Listen address: ${LISTEN_ADDR}"
echo "  Target service: ${TARGET_IPV4}:${TARGET_PORT} (IPv4) / [${TARGET_IPV6}]:${TARGET_PORT} (IPv6)"
echo "  Firewall mark:  ${FWMARK}"
echo "  Allowed list:   ${ALLOW_LIST_PATH}"

if ! command -v "$MMPROXY_BIN" &> /dev/null; then
    echo "mmproxy binary not found at ${MMPROXY_BIN}"
    echo "You can set the MMPROXY_BIN environment variable."
    exit 1
fi

# Run mmproxy
exec "$MMPROXY_BIN" \
    -allowed-subnets "$ALLOW_LIST_PATH" \
    -mark "${FWMARK}" \
    -l "${LISTEN_ADDR}" \
    -4 "${TARGET_IPV4}:${TARGET_PORT}" \
    -6 "[${TARGET_IPV6}]:${TARGET_PORT}" \
    -v 1
