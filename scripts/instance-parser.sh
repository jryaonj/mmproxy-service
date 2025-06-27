#!/usr/bin/env bash
#
# instance-parser.sh: Shared library for parsing the instances.tsv file.
#
# Must be sourced by a script in the scripts/ directory.

# get_instance_details reads the instances.tsv file and returns all
# details for a given instance name, one per line.
# Output order: fwmark, listen_addr, target_ipv4, target_port, target_ipv6
get_instance_details() {
    local instance_name=$1
    # This assumes the calling script is in the scripts/ directory.
    local instances_file="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/../config/instances.tsv"

    if [ -z "$instance_name" ]; then
        echo "Error: Instance name cannot be empty." >&2
        return 1
    fi

    if [ ! -f "$instances_file" ]; then
        echo "Error: Instances file not found at ${instances_file}" >&2
        return 1
    fi

    # Find the line for the instance, then print columns 2 through 6
    # We use awk's OFS (Output Field Separator) to ensure output is newline-separated
    local details=$(awk -F'\t' -v inst="$instance_name" '$1 == inst {print $2, $3, $4, $5, $6}' OFS='\n' "$instances_file")

    if [ -z "$details" ]; then
        echo "Error: Instance '${instance_name}' not found in ${instances_file}" >&2
        return 1
    fi

    echo "$details"
} 