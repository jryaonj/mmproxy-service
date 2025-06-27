#!/usr/bin/env bash
#
# iptables-connmark.sh: Manages iptables CONNMARK rules for mmproxy.
# Usage: ./iptables-connmark.sh {add|del} <fwmark> <table_id>
# Note: table_id ($3) is ignored, but present for calling consistency.

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
FWMARK=$2

manage_iptables_rule() {
    local iptables_cmd=$1
    local chain=$2
    local rule_params=$3
    local rule_exists=$($iptables_cmd -t mangle -C "$chain" $rule_params --wait 0 2>/dev/null && echo "yes" || echo "no")

    if [ "$ACTION" == "add" ]; then
        if [ "$rule_exists" == "no" ]; then
            echo "--> Adding ${iptables_cmd} rule to ${chain} for fwmark ${FWMARK}"
            $iptables_cmd -t mangle -A "$chain" $rule_params
        else
            echo "--> ${iptables_cmd} rule in ${chain} for fwmark ${FWMARK} already exists, skipping."
        fi
    elif [ "$ACTION" == "del" ]; then
        if [ "$rule_exists" == "yes" ]; then
            echo "--> Deleting ${iptables_cmd} rule from ${chain} for fwmark ${FWMARK}"
            $iptables_cmd -t mangle -D "$chain" $rule_params
        else
            echo "--> ${iptables_cmd} rule in ${chain} for fwmark ${FWMARK} does not exist, skipping."
        fi
    fi
}

# --- IPv4 Rules ---
PREROUTING_RULE_V4="-i+ -m mark --mark ${FWMARK} -j CONNMARK --save-mark"
OUTPUT_RULE_V4="-o+ -m connmark --mark ${FWMARK} -j CONNMARK --restore-mark"
manage_iptables_rule "iptables" "PREROUTING" "${PREROUTING_RULE_V4}"
manage_iptables_rule "iptables" "OUTPUT" "${OUTPUT_RULE_V4}"

# --- IPv6 Rules ---
if command -v ip6tables >/dev/null 2>&1; then
    PREROUTING_RULE_V6="-i+ -m mark --mark ${FWMARK} -j CONNMARK --save-mark"
    OUTPUT_RULE_V6="-o+ -m connmark --mark ${FWMARK} -j CONNMARK --restore-mark"
    manage_iptables_rule "ip6tables" "PREROUTING" "${PREROUTING_RULE_V6}"
    manage_iptables_rule "ip6tables" "OUTPUT" "${OUTPUT_RULE_V6}"
fi 