#!/usr/bin/env bash
#
# ip-rule.sh: Manages 'ip rule' entries for mmproxy.
# Usage: ./ip-rule.sh {add|del} <fwmark> <table_id>

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
FWMARK_DEC=$2
TABLE=$3

# Convert decimal fwmark to hex for matching, as 'ip rule list' may show hex.
FWMARK_HEX=$(printf "0x%x" "$FWMARK_DEC")

manage_one_rule() {
    local ip_cmd=$1
    local source_addr
    if [[ "$ip_cmd" == "ip -6" ]]; then
        source_addr="::1"
    else
        source_addr="127.0.0.1/8"
    fi

    # This regex matches 'fwmark' followed by the decimal OR hex value, then the table.
    local check_regex="from ${source_addr} fwmark (${FWMARK_DEC}|${FWMARK_HEX}) lookup ${TABLE}"
    local rule_exists=$($ip_cmd rule list | grep -qE "${check_regex}" && echo "yes" || echo "no")
    
    # The rule to add/del always uses the decimal value, as 'ip rule add' handles it correctly.
    local rule_to_manage="from ${source_addr} fwmark ${FWMARK_DEC} iif lo lookup ${TABLE}"

    if [ "$ACTION" == "add" ]; then
        if [ "$rule_exists" == "no" ]; then
            echo "--> Adding ${ip_cmd} rule for fwmark ${FWMARK_DEC} with source ${source_addr}"
            $ip_cmd rule add ${rule_to_manage}
        else
            echo "--> ${ip_cmd} rule for fwmark ${FWMARK_DEC} with source ${source_addr} already exists, skipping."
        fi
    elif [ "$ACTION" == "del" ]; then
        if [ "$rule_exists" == "yes" ]; then
            echo "--> Deleting ${ip_cmd} rule for fwmark ${FWMARK_DEC} with source ${source_addr}"
            $ip_cmd rule del ${rule_to_manage}
        else
            echo "--> ${ip_cmd} rule for fwmark ${FWMARK_DEC} with source ${source_addr} does not exist, skipping."
        fi
    fi
}

# --- Manage IPv4 Rule ---
manage_one_rule "ip"

# --- Manage IPv6 Rule ---
if command -v ip6tables >/dev/null 2>&1; then
    manage_one_rule "ip -6"
fi 
