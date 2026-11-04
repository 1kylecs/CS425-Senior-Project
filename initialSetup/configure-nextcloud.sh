#!/bin/bash
set -euo pipefail

# require sudo for Docker Admin tasks
if [[ $EUID -ne 0 ]]; then
    echo "Error. run with sudo"
    exit 1
fi

# add the LAN interface IPs to Nextcloud's Trusted Domain
configure_LAN_domain() {
    # Wait until Nextcloud has finished initializing.
    echo "Waiting for Nextcloud..."

    until docker exec -u www-data nextcloud \
        php occ status --output=json 2>/dev/null | grep -q '"installed":true'; do
        sleep 5
    done

    echo "Configuring trusted domains..."

    # Get all IPv4 addresses assigned to the server's network interfaces.
    # the grep filters out localhost and docker container IPs that are not external
    mapfile -t SERVER_IPS < <(
        ip -o -4 addr show scope global |
        awk '{split($4, address, "/"); print address[1]}' |
        grep -vE '^(127\.|172\.(1[6-9]|2[0-9]|3[01])\.)' |
        sort -u
    )

    # Add each IP address to Nextcloud's trusted domains.
    index=1

    for ip in "${SERVER_IPS[@]}"; do
        docker exec -u www-data nextcloud \
            php occ config:system:set trusted_domains "$index" \
            --value="$ip"

        echo "Added trusted domain: $ip"
        ((index+=1))
    done

    echo "Nextcloud trusted domains configured."
}


# add the tailscale hostname to nextclouds trusted domains
configure_tailscale_domain() {
    local hostname domains index

    # get servers Tailscale MagicDNS hostname
    hostname=$(docker exec tailscale tailscale status --json |
        jq -r '.Self.DNSName // empty')

    hostname="${hostname%.}"  # strip trailing '.'

    if [[ -z "$hostname" ]]; then
        echo "Error: Could not retrieve Tailscale Hostname."
        return 1
    fi

    # get existing trusted domains, avoid duplicates
    domains=$(docker exec -u www-data nextcloud php occ \
        config:system:get trusted_domains)

    if grep -Fxq "$hostname" <<< "$domains"; then
       echo "Tailscale hostname, $hostname, already trusted"
       return 0
    fi

    # append the hostname without removing existing domains
    index=$(printf '%s\n' "$domains" | wc -l)

    docker exec -u www-data nextcloud php occ \
        config:system:set trusted_domains "$index" \
        --value="$hostname"

    echo "Added trusted domain: $hostname"
}
