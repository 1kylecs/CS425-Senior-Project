#!/bin/bash

# Retrieve Nextcloud's existing trusted-domain configuration.
# The JSON includes domain values and their array indexes.
get_trusted_domains() {
    docker exec -u www-data nextcloud php occ \
        config:list system --output=json
}

# Add a domain only if it is not already trusted.
# This helper is shared by LAN and Tailscale configuration.
add_trusted_domain() {
    local domain="$1"
    local config index

    # Reject empty values before modifying Nextcloud.
    if [[ -z "$domain" ]]; then
        echo "Error: Cannot add an empty trusted domain."
        return 1
    fi

    # Stop if Nextcloud cannot provide its configuration.
    if ! config=$(get_trusted_domains); then
        echo "Error: Could not retrieve Nextcloud configuration."
        return 1
    fi

    # Check for an exact match, avoiding duplicate entries.
    if jq -e --arg domain "$domain" '
        (.system.trusted_domains // [])
        | if type == "array" or type == "object"
          then any(.[]; . == $domain)
          else false
          end
    ' >/dev/null <<< "$config"; then
        echo "Already trusted: $domain"
        return 0
    fi

    # Find the next unused index.
    # For arrays, use their length. For indexed objects,
    # use the highest numeric key plus one.
    if ! index=$(jq -er '
        (.system.trusted_domains // [])
        | if type == "array" then
            length
          elif type == "object" then
            ([keys[] | tonumber] | max // -1) + 1
          else
            error("Unexpected trusted_domains format")
          end
    ' <<< "$config"); then
        echo "Error: Could not determine next trusted-domain index."
        return 1
    fi

    # Explicitly handle write failures instead of relying on set -e.
    if ! docker exec -u www-data nextcloud php occ \
        config:system:set trusted_domains "$index" \
        --value="$domain"; then
        echo "Error: Failed to add trusted domain: $domain"
        return 1
    fi

    echo "Added trusted domain: $domain"
}

# Wait for Nextcloud to finish installing.
# Return an error after five minutes instead of waiting indefinitely.
wait_for_nextcloud() {
    local timeout="${NEXTCLOUD_TIMEOUT:-300}"
    local interval="${NEXTCLOUD_POLL_INTERVAL:-5}"
    local elapsed=0
    local result

    echo "Waiting for Nextcloud..."

    while (( elapsed < timeout )); do
        if result=$(docker exec -u www-data nextcloud \
            php occ status --output=json 2>/dev/null); then

            if jq -e '.installed == true' >/dev/null 2>&1 <<< "$result"; then
                echo "Nextcloud is ready."
                return 0
            fi
        fi

        sleep "$interval"
        ((elapsed+=interval))
    done

    echo "Error: Nextcloud initialization timed out."
    return 1
}

# Discover and register the server's LAN IPv4 addresses.
configure_LAN_domain() {
    local ip
    local -a server_ips

    wait_for_nextcloud || return 1

    echo "Configuring LAN trusted domains..."

    # Filter Docker interfaces by name, not IP range.
    # This preserves legitimate LAN addresses in 172.16.0.0/12.
    local ip_output
    if ! ip_output=$(ip -o -4 addr show scope global); then
        echo "Error: Could not retrieve network interfaces."
        return 1
    fi

    mapfile -t server_ips < <(
        printf '%s\n' "$ip_output" |
        awk '$2 !~ /^(docker|br-|veth)/ {
            split($4, address, "/")
            print address[1]
        }' |
        sort -u
    )

    # Register each address without overwriting existing entries.
    for ip in "${server_ips[@]}"; do
        add_trusted_domain "$ip" || return 1
    done

    echo "Nextcloud LAN trusted domains configured."
}

# Retrieve and register the server's Tailscale MagicDNS hostname.
configure_tailscale_domain() {
    local status hostname

    # Read the hostname from Tailscale's JSON status.
    if ! status=$(docker exec tailscale tailscale status --json); then
        echo "Error: Could not retrieve Tailscale status."
        return 1
    fi

    if ! hostname=$(jq -er '.Self.DNSName // empty' <<< "$status"); then
        echo "Error: Could not retrieve Tailscale hostname."
        return 1
    fi

    # Tailscale returns fully qualified names with a trailing dot.
    hostname="${hostname%.}"

    if [[ -z "$hostname" ]]; then
        echo "Error: Tailscale hostname is empty."
        return 1
    fi

    add_trusted_domain "$hostname"
}

