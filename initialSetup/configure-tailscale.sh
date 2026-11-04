#!/bin/bash

set -euo pipefail

# Configuration
CONTAINER="tailscale"
TAILSCALE_HOSTNAME="mycloud"
LOGIN_TIMEOUT=300
POLL_INTERVAL=3
SERVE_RETRIES=3

# Require root permissions for Docker commands.
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run this script with sudo."
    exit 1
fi

# Verify required commands are installed.
for cmd in docker jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required."
        exit 1
    fi
done

# Ensure the Tailscale container is running.
if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]]; then
    echo "Error: Tailscale container is not running."
    exit 1
fi

# Run Tailscale commands inside the Docker container.
ts() {
    docker exec "$CONTAINER" tailscale "$@"
}

# Retrieve Tailscale's status as JSON.
get_status() {
    ts status --json
}

# Determine whether Tailscale has successfully connected.
is_connected() {
    [[ "$(get_status | jq -r '.BackendState')" == "Running" ]]
}

# Start browser authentication and wait for the user to sign in.
configure_login() {
    if is_connected; then
        echo "Tailscale is already connected."
        return 0
    fi

    echo "Starting Tailscale authentication..."

    local login_log login_pid
    login_log=$(mktemp)

    # Run authentication in the background so we can display
    # the login URL and monitor the connection independently.

    ts up \
       --hostname="$TAILSCALE_HOSTNAME"\
       --accept-dns=false \
       --timeout=5m \
       >"$login_log" 2>&1 &


    login_pid=$!

    local elapsed=0
    local auth_url=""
    local previous_url=""
    local status

    # Poll Tailscale until authentication succeeds or times out.
    while (( elapsed < LOGIN_TIMEOUT )); do
        if status=$(get_status 2>/dev/null); then

            # Continue setup once Tailscale is connected.
            if [[ "$(jq -r '.BackendState' <<< "$status")" == "Running" ]]; then
                echo "Tailscale connected successfully!"
                wait "$login_pid" || true
                rm -f "$login_log"
                return 0
            fi

            # Retrieve the browser authentication URL.
            auth_url=$(jq -r '.AuthURL // empty' <<< "$status")

            # Only display the URL when it changes.
            if [[ -n "$auth_url" && "$auth_url" != "$previous_url" ]]; then
                echo
                echo "Open this URL to connect your server:"
                echo "$auth_url"
                echo
                previous_url="$auth_url"
            fi
        fi

        # Stop waiting if the authentication command fails.
        if ! kill -0 "$login_pid" 2>/dev/null; then
            if ! wait "$login_pid"; then
                echo "Error: Tailscale authentication failed."
                cat "$login_log"
                rm -f "$login_log"
                return 1
            fi
        fi

        sleep "$POLL_INTERVAL"
        ((elapsed+=POLL_INTERVAL))
    done

    # Stop the background command if authentication times out.
    echo "Error: Authentication timed out."
    kill "$login_pid" 2>/dev/null || true
    wait "$login_pid" 2>/dev/null || true

    cat "$login_log"
    rm -f "$login_log"
    return 1
}

# Configure Tailscale Serve to forward HTTPS traffic to Nextcloud.
configure_serve() {
    local attempt output

    echo
    echo "Configuring secure Nextcloud access..."

    # Retry if the user must enable HTTPS certificates or Serve.
    for ((attempt=1; attempt<=SERVE_RETRIES; attempt++)); do

        # Nextcloud listens on port 80 inside the shared network namespace.
        if output=$(ts serve --bg http://127.0.0.1:80 2>&1); then
            echo "Tailscale Serve configured successfully!"
            return 0
        fi

        echo "$output"
        echo
        echo "Tailscale may require HTTPS approval."
        echo "Open the approval URL shown above."
        echo

        # Allow the user to complete approval before retrying.
        if (( attempt == SERVE_RETRIES )); then
            break
        fi

        read -r -p "Press Enter to retry (Ctrl+C to cancel)..."
    done

    echo "Error: Could not configure Tailscale Serve."
    return 1
}

# Run the complete Tailscale setup process.
main() {
    echo "================================"
    echo "     Tailscale Configuration"
    echo "================================"

    # Authenticate the server, then configure HTTPS access.
    configure_login
    configure_serve

    # Display the active Serve configuration.
    echo
    echo "Checking Tailscale Serve..."
    ts serve status

    # Retrieve the MagicDNS hostname for the server's HTTPS URL.
    local hostname
    hostname=$(get_status | jq -r '.Self.DNSName // empty')
    hostname="${hostname%.}"

    if [[ -z "$hostname" ]]; then
        echo "Error: Could not determine Tailscale hostname."
        exit 1
    fi

    # Use configure-nextcloud.sh to add hostname to nextcloud
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ ! -f "$SCRIPT_DIR/configure-nextcloud.sh" ]]; then
        echo "Error: configure-nextcloud.sh not found"
        exit 1
    fi

    source "$SCRIPT_DIR/configure-nextcloud.sh"
    configure_tailscale_domain


    # Display the address users will use to access Nextcloud.
    echo
    echo "================================"
    echo "      Setup Complete!"
    echo "================================"
    echo
    echo "Your Nextcloud HTTPS address:"
    echo "https://$hostname"
    echo
    echo "Devices must be connected to your Tailscale network."
}

# Run setup only when this script is executed directly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
