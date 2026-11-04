#!/bin/bash
set -euo pipefail

# require sudo for Docker Admin tasks
if [[ $EUID -ne 0 ]]; then
    echo "Error. run with sudo"
    exit 1
fi

# Wait until Nextcloud has finished initializing.
echo "Waiting for Nextcloud..."

until docker exec -u www-data nextcloud \
    php occ status --output=json 2>/dev/null | grep -q '"installed":true'; do
    sleep 5
done

echo "Configuring trusted domains..."

# Get all IPv4 addresses assigned to the server's network interfaces.
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
