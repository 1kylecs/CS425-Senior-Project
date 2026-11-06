#!/usr/bin/env bats

# Unit tests for configure-nextcloud.sh.
#
# These tests exercise the real Bash functions while replacing
# Docker, network-interface discovery, and sleep commands.
#
# No actual Docker containers or Nextcloud settings are modified.
#
# The Docker mock stores trusted domains in a temporary JSON file.
# This approximates how Nextcloud persists configuration changes:
#
#   1. The script reads the current trusted domains.
#   2. The script adds a new domain using occ.
#   3. A later read includes the newly added domain.
#
# This is more realistic than simply printing Docker commands.


setup() {
    # Load the actual functions being tested.
    # The script must not run main() when sourced.
    source "$BATS_TEST_DIRNAME/../configure-nextcloud.sh"

    # Each test gets its own isolated configuration.
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR

    CONFIG_FILE="$TEST_TMPDIR/nextcloud.json"
    COMMAND_LOG="$TEST_TMPDIR/docker-commands.log"
    export CONFIG_FILE COMMAND_LOG

    # Simulate a fresh Nextcloud installation.
    # Index 0 is normally localhost.
    echo '{"system":{"trusted_domains":["localhost"]}}' > "$CONFIG_FILE"
    touch "$COMMAND_LOG"

    # Keep initialization tests fast.
    NEXTCLOUD_TIMEOUT=15
    NEXTCLOUD_POLL_INTERVAL=5
}

teardown() {
    # Remove simulated configuration and command logs.
    rm -rf "$TEST_TMPDIR"
}


# ==================================================
# SHARED MOCKS
# ==================================================

# Simulate Docker commands used by configure-nextcloud.sh.
#
# In production, docker exec communicates with the running
# Nextcloud or Tailscale container.
#
# Here, we recognize the requested command and return
# a simulated response.
#
# Configuration writes update CONFIG_FILE, allowing later
# reads to observe the changes just as they would in Nextcloud.
docker() {
    printf '%s\n' "$*" >> "$COMMAND_LOG"

    case "$*" in

        *"occ status --output=json"*)
            # Simulate Nextcloud reporting successful installation.
            echo '{"installed":true}'
            ;;

        *"occ config:list system --output=json"*)
            # Return the current simulated Nextcloud configuration.
            cat "$CONFIG_FILE"
            ;;

        *"occ config:system:set trusted_domains"*)
            # Extract the index and value from the occ command.
            #
            # Example real command:
            #   docker exec -u www-data nextcloud php occ \
            #       config:system:set trusted_domains 1 \
            #       --value=192.168.56.103

            local index=""
            local value=""
            local previous=""

            for arg in "$@"; do
                if [[ "$previous" == "trusted_domains" ]]; then
                    index="$arg"
                fi

                if [[ "$arg" == --value=* ]]; then
                    value="${arg#--value=}"
                fi

                previous="$arg"
            done

            # Update the JSON file to simulate a persistent write.
            jq --argjson index "$index" --arg value "$value" '
                .system.trusted_domains[$index] = $value
            ' "$CONFIG_FILE" > "$TEST_TMPDIR/updated.json"

            mv "$TEST_TMPDIR/updated.json" "$CONFIG_FILE"
            ;;

        *"tailscale status --json"*)
            # Simulate a connected Tailscale client returning
            # its fully qualified MagicDNS hostname.
            echo '{"Self":{"DNSName":"mycloud.example.ts.net."}}'
            ;;

        *)
            # Unexpected commands should fail the test rather
            # than silently returning success.
            echo "Unexpected Docker command: $*" >&2
            return 1
            ;;
    esac
}

# Simulate the output of:
#   ip -o -4 addr show scope global
#
# By default, the server has one ordinary LAN interface.
# Individual tests can override this function to simulate
# multiple interfaces, Docker bridges, or command failures.
ip() {
    echo '2: enp0s3 inet 192.168.56.103/24 scope global enp0s3'
}

# Prevent initialization tests from waiting five real seconds.
#
# When testing timeout behavior, the loop still increments
# elapsed time, but this mock makes the test finish immediately.
sleep() {
    return 0
}


# ==================================================
# TRUSTED-DOMAIN HELPER TESTS
# ==================================================

@test "add_trusted_domain adds a new domain" {

    # The simulated Nextcloud configuration initially contains:
    #   0: localhost
    #
    # Adding a new address should create index 1.
    #
    # The mock updates CONFIG_FILE when the script executes
    # the equivalent of occ config:system:set.

    run add_trusted_domain "192.168.56.103"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Added trusted domain: 192.168.56.103"* ]]

    # Verify the domain was actually stored in the mock.
    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "192.168.56.103" ]
}


@test "add_trusted_domain skips an existing domain" {

    # Simulate rerunning the installer after localhost
    # has already been registered.
    #
    # The function should detect the exact match and
    # avoid executing another configuration write.

    run add_trusted_domain "localhost"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already trusted: localhost"* ]]

    # No trusted-domain write should have occurred.
    ! grep -q "config:system:set trusted_domains" "$COMMAND_LOG"
}


@test "add_trusted_domain rejects an empty domain" {

    # Simulate a caller accidentally passing an empty string.
    #
    # Without validation, this could register an invalid
    # trusted-domain entry in Nextcloud.

    run add_trusted_domain ""

    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot add an empty trusted domain"* ]]

    # The configuration must remain unchanged.
    [ "$(jq '.system.trusted_domains | length' "$CONFIG_FILE")" -eq 1 ]
}


@test "add_trusted_domain preserves existing domains" {

    # Simulate an installation that already has:
    #   localhost
    #   a LAN address
    #   a Tailscale hostname
    #
    # Adding another address must preserve all three.

    echo '{
        "system": {
            "trusted_domains": [
                "localhost",
                "192.168.56.103",
                "mycloud.example.ts.net"
            ]
        }
    }' > "$CONFIG_FILE"

    run add_trusted_domain "10.0.2.15"

    [ "$status" -eq 0 ]

    # Check that the new address was appended at index 3.
    [ "$(jq -r '.system.trusted_domains[3]' "$CONFIG_FILE")" = \
      "10.0.2.15" ]

    # Check that the existing Tailscale hostname survived.
    [ "$(jq -r '.system.trusted_domains[2]' "$CONFIG_FILE")" = \
      "mycloud.example.ts.net" ]
}


@test "add_trusted_domain handles noncontiguous indexes" {

    # Simulate trusted domains stored as an indexed object
    # with a gap between indexes 0 and 3.
    #
    # The function should select index 4 instead of
    # assuming the next index equals the number of entries.
    #
    # For this test, replace Docker with a simpler mock
    # that records the requested write index.

    echo '{
        "system": {
            "trusted_domains": {
                "0": "localhost",
                "3": "mycloud.example.ts.net"
            }
        }
    }' > "$CONFIG_FILE"

    docker() {
        if [[ "$*" == *"config:list system --output=json"* ]]; then
            cat "$CONFIG_FILE"
        elif [[ "$*" == *"config:system:set trusted_domains"* ]]; then
            echo "$*"
        else
            return 1
        fi
    }

    run add_trusted_domain "192.168.56.103"

    [ "$status" -eq 0 ]
    [[ "$output" == *"trusted_domains 4 --value=192.168.56.103"* ]]
}


@test "add_trusted_domain fails when Nextcloud cannot read configuration" {

    # Simulate Nextcloud being unavailable when the script
    # requests its system configuration.
    #
    # In production, Docker might return a nonzero exit
    # status because the container stopped or occ failed.

    get_trusted_domains() {
        return 1
    }

    run add_trusted_domain "192.168.56.103"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not retrieve Nextcloud configuration"* ]]
}


@test "add_trusted_domain fails when Nextcloud rejects the write" {

    # Simulate a successful configuration read followed
    # by a failed occ config:system:set command.
    #
    # This approximates a permission or container error.
    #
    # The function must report failure rather than
    # printing a misleading success message.

    docker() {
        if [[ "$*" == *"config:list system --output=json"* ]]; then
            cat "$CONFIG_FILE"
        elif [[ "$*" == *"config:system:set trusted_domains"* ]]; then
            return 1
        else
            return 1
        fi
    }

    run add_trusted_domain "192.168.56.103"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to add trusted domain"* ]]
}


# ==================================================
# NEXTCLOUD INITIALIZATION TESTS
# ==================================================

@test "wait_for_nextcloud succeeds when Nextcloud is installed" {

    # The shared Docker mock returns:
    #   {"installed":true}
    #
    # This approximates a Nextcloud container that has
    # completed its initial installation.
    #
    # The function should return immediately.

    run wait_for_nextcloud

    [ "$status" -eq 0 ]
    [[ "$output" == *"Nextcloud is ready"* ]]
}


@test "wait_for_nextcloud retries until installation completes" {

    # Simulate Nextcloud starting up.
    #
    # Real installation sequence:
    #   First status check:  installed=false
    #   Second status check: installed=false
    #   Third status check:  installed=true
    #
    # We use a file-backed counter because the status
    # command runs inside a command substitution.
    # Changes to ordinary shell variables might not
    # survive those subshell boundaries.

    local counter="$TEST_TMPDIR/status-count"
    echo 0 > "$counter"

    docker() {
        local n
        n=$(cat "$counter")
        n=$((n + 1))
        echo "$n" > "$counter"

        if (( n < 3 )); then
            echo '{"installed":false}'
        else
            echo '{"installed":true}'
        fi
    }

    run wait_for_nextcloud

    [ "$status" -eq 0 ]
    [ "$(cat "$counter")" -eq 3 ]
    [[ "$output" == *"Nextcloud is ready"* ]]
}


@test "wait_for_nextcloud times out if installation never completes" {

    # Simulate Nextcloud remaining uninstalled.
    #
    # In a real deployment, this could happen because
    # initialization failed or the database is unavailable.
    #
    # The mock always reports installed=false.
    # The mocked sleep prevents real waiting.

    docker() {
        echo '{"installed":false}'
    }

    NEXTCLOUD_TIMEOUT=15
    NEXTCLOUD_POLL_INTERVAL=5

    run wait_for_nextcloud

    [ "$status" -ne 0 ]
    [[ "$output" == *"Nextcloud initialization timed out"* ]]
}


# ==================================================
# LAN DOMAIN TESTS
# ==================================================

@test "configure_LAN_domain adds a valid LAN address" {

    # The shared ip mock represents a server interface:
    #   enp0s3 -> 192.168.56.103
    #
    # Nextcloud is already installed, so configuration
    # should begin immediately.
    #
    # The Docker mock persists the new trusted domain.

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "192.168.56.103" ]

    [[ "$output" == *"Nextcloud LAN trusted domains configured"* ]]
}


@test "configure_LAN_domain adds multiple LAN addresses" {

    # Simulate two network interfaces on your Ubuntu VM.
    #
    # One represents the NAT interface.
    # The other represents the host-only interface.
    #
    # Both should become trusted domains.
    #
    # The mock configuration is updated after each write,
    # so the second address receives the next index.

    ip() {
        echo '2: enp0s3 inet 10.0.2.15/24 scope global enp0s3'
        echo '3: enp0s8 inet 192.168.56.103/24 scope global enp0s8'
    }

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    # Addresses are sorted before being registered.
    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "10.0.2.15" ]

    [ "$(jq -r '.system.trusted_domains[2]' "$CONFIG_FILE")" = \
      "192.168.56.103" ]
}


@test "configure_LAN_domain removes duplicate IP addresses" {

    # Simulate the same address appearing on two interfaces.
    #
    # The script uses sort -u to remove duplicates
    # before sending them to Nextcloud.
    #
    # Only one configuration write should occur.

    ip() {
        echo '2: enp0s3 inet 192.168.56.103/24 scope global enp0s3'
        echo '3: enp0s8 inet 192.168.56.103/24 scope global enp0s8'
    }

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    # The final configuration should contain two entries:
    # localhost and the unique LAN address.
    [ "$(jq '.system.trusted_domains | length' "$CONFIG_FILE")" -eq 2 ]

    # Verify that only one write was attempted.
    [ "$(grep -c 'config:system:set trusted_domains' "$COMMAND_LOG")" -eq 1 ]
}


@test "configure_LAN_domain excludes Docker interfaces" {

    # Simulate a real LAN interface and two Docker interfaces.
    #
    # Docker commonly creates:
    #   docker0
    #   br-<network-id>
    #
    # Their addresses should not be registered because
    # they are internal to Docker networking.

    ip() {
        echo '2: enp0s3 inet 192.168.56.103/24 scope global enp0s3'
        echo '4: docker0 inet 172.17.0.1/16 scope global docker0'
        echo '5: br-123abc inet 172.18.0.1/16 scope global br-123abc'
    }

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    # Only the real LAN address should be added.
    [ "$(jq '.system.trusted_domains | length' "$CONFIG_FILE")" -eq 2 ]

    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "192.168.56.103" ]
}


@test "configure_LAN_domain accepts legitimate 172.x LAN addresses" {

    # Simulate a physical LAN interface using 172.20.1.50.
    #
    # The previous implementation excluded the entire
    # 172.16.0.0/12 range, which also contains valid
    # private LAN addresses.
    #
    # The updated function filters by interface name,
    # so this address should now be accepted.

    ip() {
        echo '2: enp0s3 inet 172.20.1.50/24 scope global enp0s3'
    }

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "172.20.1.50" ]
}


@test "configure_LAN_domain preserves an existing Tailscale hostname" {

    # Simulate rerunning the installer after Tailscale
    # has already registered its hostname.
    #
    # Existing configuration:
    #   0: localhost
    #   1: mycloud.example.ts.net
    #
    # LAN configuration must append its IP address
    # without overwriting the Tailscale hostname.

    echo '{
        "system": {
            "trusted_domains": [
                "localhost",
                "mycloud.example.ts.net"
            ]
        }
    }' > "$CONFIG_FILE"

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "mycloud.example.ts.net" ]

    [ "$(jq -r '.system.trusted_domains[2]' "$CONFIG_FILE")" = \
      "192.168.56.103" ]
}


@test "configure_LAN_domain does not duplicate domains on rerun" {

    # Simulate running LAN configuration twice.
    #
    # This matters because users may rerun install.sh
    # after a failed setup or system update.
    #
    # The first call adds the address.
    # The second call should recognize it as trusted.

    configure_LAN_domain >/dev/null

    run configure_LAN_domain

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already trusted: 192.168.56.103"* ]]

    # The trusted-domain list should not grow.
    [ "$(jq '.system.trusted_domains | length' "$CONFIG_FILE")" -eq 2 ]
}


@test "configure_LAN_domain handles no eligible LAN addresses" {

    # Simulate a server where all discovered addresses
    # belong to Docker interfaces.
    #
    # After filtering, no addresses remain.
    #
    # The function should finish successfully without
    # writing an empty trusted-domain entry.

    ip() {
        echo '4: docker0 inet 172.17.0.1/16 scope global docker0'
        echo '5: br-123abc inet 172.18.0.1/16 scope global br-123abc'
    }

    run configure_LAN_domain

    [ "$status" -eq 0 ]

    # Only the original localhost entry should remain.
    [ "$(jq '.system.trusted_domains | length' "$CONFIG_FILE")" -eq 1 ]

    ! grep -q 'config:system:set trusted_domains' "$COMMAND_LOG"
}


@test "configure_LAN_domain fails when interface discovery fails" {

    # Simulate the ip command returning an error.
    #
    # This could happen if the command is unavailable
    # or the system cannot retrieve interface information.
    #
    # The installer should stop instead of claiming
    # that LAN configuration succeeded.

    ip() {
        return 1
    }

    run configure_LAN_domain

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not retrieve network interfaces"* ]]
}


# ==================================================
# TAILSCALE DOMAIN TESTS
# ==================================================

@test "configure_tailscale_domain adds the MagicDNS hostname" {

    # The shared Docker mock returns:
    #   mycloud.example.ts.net.
    #
    # This approximates the DNSName field returned by:
    #   tailscale status --json
    #
    # The function should remove the trailing dot
    # and register the hostname with Nextcloud.

    run configure_tailscale_domain

    [ "$status" -eq 0 ]

    [ "$(jq -r '.system.trusted_domains[1]' "$CONFIG_FILE")" = \
      "mycloud.example.ts.net" ]
}


@test "configure_tailscale_domain skips an existing hostname" {

    # Simulate a Tailscale hostname that was registered
    # during an earlier installation.
    #
    # The function should detect the duplicate
    # and avoid modifying the configuration.

    echo '{
        "system": {
            "trusted_domains": [
                "localhost",
                "mycloud.example.ts.net"
            ]
        }
    }' > "$CONFIG_FILE"

    run configure_tailscale_domain

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already trusted: mycloud.example.ts.net"* ]]

    [ "$(jq '.system.trusted_domains | length' "$CONFIG_FILE")" -eq 2 ]
}


@test "configure_tailscale_domain fails when hostname is missing" {

    # Simulate Tailscale returning a valid JSON response
    # without the Self.DNSName field.
    #
    # This could happen if Tailscale has not completed
    # authentication or its status is incomplete.
    #
    # The function must not register an empty hostname.

    docker() {
        if [[ "$*" == *"tailscale status --json"* ]]; then
            echo '{"Self":{}}'
        else
            echo "UNEXPECTED_DOMAIN_WRITE"
            return 1
        fi
    }

    run configure_tailscale_domain

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not retrieve Tailscale hostname"* ]]
    [[ "$output" != *"UNEXPECTED_DOMAIN_WRITE"* ]]
}


@test "configure_tailscale_domain fails when Tailscale status fails" {

    # Simulate the Tailscale container being unavailable.
    #
    # In production, docker exec would return a nonzero
    # exit code if the container were stopped or missing.
    #
    # The function should report the failure rather
    # than attempting to configure Nextcloud.

    docker() {
        if [[ "$*" == *"tailscale status --json"* ]]; then
            return 1
        fi

        echo "UNEXPECTED_DOMAIN_WRITE"
        return 1
    }

    run configure_tailscale_domain

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not retrieve Tailscale status"* ]]
    [[ "$output" != *"UNEXPECTED_DOMAIN_WRITE"* ]]
}


@test "configure_tailscale_domain propagates Nextcloud write failure" {

    # Simulate Tailscale returning a valid hostname,
    # followed by Nextcloud rejecting the configuration write.
    #
    # This verifies that the failure travels through
    # add_trusted_domain() to configure_tailscale_domain().
    #
    # The installer must not report success if the
    # hostname was never registered.

    docker() {
        if [[ "$*" == *"tailscale status --json"* ]]; then
            echo '{"Self":{"DNSName":"mycloud.example.ts.net."}}'

        elif [[ "$*" == *"config:list system --output=json"* ]]; then
            cat "$CONFIG_FILE"

        elif [[ "$*" == *"config:system:set trusted_domains"* ]]; then
            return 1

        else
            return 1
        fi
    }

    run configure_tailscale_domain

    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to add trusted domain"* ]]
}
