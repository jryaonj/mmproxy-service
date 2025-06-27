#!/usr/bin/env bash
#
# ip-route.sh: Manages 'ip route' entries for mmproxy.
# Usage: ./ip-route.sh {add|del} <fwmark> <table_id>
# Note: fwmark ($2) is ignored, but present for calling consistency.

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "Usage: $0 {add|del} <fwmark> <table_id>" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." >&2
   exit 1
fi

ACTION=$1
TABLE=$3

manage_one_route() {
    local ip_cmd=$1
    local route_to_manage=$2
    local check_pattern=$3

    local route_exists=$($ip_cmd route list table "${TABLE}" | grep -qF "${check_pattern}" && echo "yes" || echo "no")

    if [ "$ACTION" == "add" ]; then
        if [ "$route_exists" == "no" ]; then
            echo "--> Adding ${ip_cmd} route for table ${TABLE}"
            $ip_cmd route add ${route_to_manage}
        else
            echo "--> ${ip_cmd} route for table ${TABLE} already exists, skipping."
        fi
    elif [ "$ACTION" == "del" ]; then
        if [ "$route_exists" == "yes" ]; then
            echo "--> Deleting ${ip_cmd} route for table ${TABLE}"
            $ip_cmd route del ${route_to_manage}
        else
            echo "--> ${ip_cmd} route for table ${TABLE} does not exist, skipping."
        fi
    fi
}

# --- IPv4 Route ---
# The kernel normalizes '0.0.0.0/0' to 'default' in the route table listing.
ROUTE_V4_TO_MANAGE="local 0.0.0.0/0 dev lo table ${TABLE}"
CHECK_PATTERN_V4="local default dev lo"
manage_one_route "ip" "${ROUTE_V4_TO_MANAGE}" "${CHECK_PATTERN_V4}"

# --- IPv6 Route ---
if command -v ip6tables >/dev/null 2>&1; then
    # The kernel also normalizes '::/0' to 'default' in the IPv6 route table.
    ROUTE_V6_TO_MANAGE="local ::/0 dev lo table ${TABLE}"
    CHECK_PATTERN_V6="local default dev lo"
    manage_one_route "ip -6" "${ROUTE_V6_TO_MANAGE}" "${CHECK_PATTERN_V6}"
fi 