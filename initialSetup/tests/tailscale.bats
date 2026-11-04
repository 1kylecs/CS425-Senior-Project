
#!/usr/bin/env bats

# Unit tests for configure-tailscale.sh.
#
# These tests simulate Tailscale and Docker behavior rather than
# connecting to a real tailnet or modifying running containers.
#
# Mock functions replace real functions from configure-tailscale.sh
# for the duration of an individual test.

setup() {
    # Load the actual functions being tested.
    # The script must not automatically run main() when sourced.
    source "$BATS_TEST_DIRNAME/../configure-tailscale.sh"

    # Create an isolated directory for test data.
    # Some mocks use files to remember how many times they were called.
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    # Remove temporary counters and other test data.
    rm -rf "$TEST_TMPDIR"
}

# ==================================================
# TAILSCALE STATUS TESTS
# ==================================================

@test "get_status requests JSON from Tailscale" {

    # Mock the ts() wrapper instead of calling Docker.
    #
    # Normally, get_status() calls:
    #   docker exec tailscale tailscale status --json
    #
    # Here, ts() prints the arguments it receives.
    # This lets us verify that get_status() requested
    # the correct command without running Tailscale.
    ts() {
        printf '%s\n' "$*"
    }

    run get_status

    [ "$status" -eq 0 ]
    [ "$output" = 'status --json' ]
}

@test "is_connected succeeds when backend is Running" {

    # Simulate the JSON returned by:
    #   tailscale status --json
    #
    # A connected Tailscale client reports:
    #   "BackendState": "Running"
    #
    # Replacing get_status() allows us to test how
    # is_connected() interprets that response.
    get_status() {
        echo '{"BackendState":"Running"}'
    }

    run is_connected

    # Exit code 0 means the connection check succeeded.
    [ "$status" -eq 0 ]
}

@test "is_connected rejects NeedsLogin" {

    # Simulate a Tailscale installation that has started
    # but has not yet been authenticated by the user.
    #
    # This is the state we expect before the user opens
    # the browser authentication link and signs in.
    get_status() {
        echo '{"BackendState":"NeedsLogin"}'
    }

    run is_connected

    # A nonzero exit code means the server is not connected.
    [ "$status" -ne 0 ]
}

@test "is_connected rejects Stopped" {

    # Simulate a Tailscale daemon that is available
    # but currently disconnected or stopped.
    #
    # This verifies that the script does not confuse
    # an installed Tailscale client with an active connection.
    get_status() {
        echo '{"BackendState":"Stopped"}'
    }

    run is_connected

    [ "$status" -ne 0 ]
}

@test "is_connected rejects missing backend state" {

    # Simulate an incomplete JSON response.
    #
    # Real command output should contain BackendState,
    # but missing fields can occur if an API changes or
    # a response is otherwise unexpected.
    #
    # The connection check must not assume success.
    get_status() {
        echo '{}'
    }

    run is_connected

    [ "$status" -ne 0 ]
}

@test "is_connected rejects malformed JSON" {

    # Simulate corrupted or unexpected output from Tailscale.
    #
    # For example, a command might print an error message
    # instead of the expected JSON object.
    #
    # jq should reject this input, and is_connected()
    # should report that it cannot confirm a connection.
    get_status() {
        echo 'not json'
    }

    run is_connected

    [ "$status" -ne 0 ]
}

# ==================================================
# AUTHENTICATION TESTS
# ==================================================

@test "configure_login skips authentication when already connected" {

    # Simulate a server that has already authenticated.
    #
    # The real is_connected() examines Tailscale's JSON
    # status. Here we return success directly because
    # we only want to test configure_login()'s behavior
    # when the server is already connected.
    is_connected() {
        return 0
    }

    # This mock represents an unexpected Tailscale call.
    #
    # If configure_login() tries to authenticate again,
    # the mock prints a recognizable marker and fails.
    #
    # This helps verify that unnecessary authentication
    # commands are not executed.
    ts() {
        echo 'UNEXPECTED_TS_CALL'
        return 1
    }

    run configure_login

    [ "$status" -eq 0 ]
    [[ "$output" == *'already connected'* ]]
    [[ "$output" != *'UNEXPECTED_TS_CALL'* ]]
}

@test "configure_login succeeds after authentication changes to Running" {

    # Simulate a user completing browser authentication.
    #
    # In a real installation:
    # 1. Tailscale initially reports NeedsLogin.
    # 2. The user opens the authentication URL.
    # 3. Tailscale eventually reports Running.
    #
    # Our mock reproduces that sequence without requiring
    # an actual browser or Tailscale account.

    is_connected() {
        return 1
    }

    # Store the number of status checks in a file.
    #
    # We use a file because Bash command substitutions and
    # Bats' run helper execute commands in subshells.
    # A normal shell variable would not reliably preserve
    # changes between those separate executions.
    local counter="$TEST_TMPDIR/status-count"
    echo 0 > "$counter"

    get_status() {
        local n
        n=$(cat "$counter")
        n=$((n + 1))
        echo "$n" > "$counter"

        if (( n >= 2 )); then
            # On the second status check, simulate the user
            # having completed authentication successfully.
            echo '{"BackendState":"Running"}'
        else
            # On the first check, simulate Tailscale waiting
            # for the user to open its browser login link.
            echo '{"BackendState":"NeedsLogin","AuthURL":"https://login.tailscale.com/a/test"}'
        fi
    }

    # Simulate successful execution of the Tailscale CLI.
    # No Docker container or authentication is started.
    ts() {
        return 0
    }

    # Avoid a real delay between simulated status checks.
    POLL_INTERVAL=0

    run configure_login

    [ "$status" -eq 0 ]
    [[ "$output" == *'connected successfully'* ]]
}

@test "configure_login times out if connection never starts" {

    # Simulate an authentication attempt that cannot finish.
    #
    # In a real installation, this could happen because
    # the user never opens the login link or cannot sign in.
    #
    # Setting LOGIN_TIMEOUT to zero forces the timeout path
    # immediately, keeping the unit test fast.
    is_connected() {
        return 1
    }

    LOGIN_TIMEOUT=0

    # Prevent any real Tailscale command from running.
    ts() {
        return 0
    }

    run configure_login

    [ "$status" -ne 0 ]
    [[ "$output" == *'timed out'* ]]
}

# ==================================================
# TAILSCALE SERVE TESTS
# ==================================================

@test "configure_serve succeeds on first attempt" {

    # Replace the Tailscale CLI wrapper with a mock
    # that validates the exact command being requested.
    #
    # In the real setup, this command configures Serve
    # to forward HTTPS requests to Nextcloud's HTTP port:
    #
    #   tailscale serve --bg http://127.0.0.1:80
    #
    # The mock succeeds only if the expected arguments
    # are supplied in the correct order.
    ts() {
        [ "$1" = serve ] &&
        [ "$2" = --bg ] &&
        [ "$3" = http://127.0.0.1:80 ]
    }

    run configure_serve

    [ "$status" -eq 0 ]
    [[ "$output" == *'configured successfully'* ]]
}

@test "configure_serve retries after approval and then succeeds" {

    # Simulate a new tailnet where HTTPS certificates
    # or Tailscale Serve have not yet been approved.
    #
    # Real behavior:
    # 1. The first Serve command fails and shows a URL.
    # 2. The user opens the URL and approves the request.
    # 3. The installer retries the Serve command.
    # 4. Serve succeeds.
    #
    # We reproduce this by making the first call fail
    # and the second call return success.

    local counter="$TEST_TMPDIR/serve-count"
    echo 0 > "$counter"

    ts() {
        local n
        n=$(cat "$counter")
        n=$((n + 1))
        echo "$n" > "$counter"

        if (( n == 1 )); then
            # Simulate Tailscale displaying an approval URL.
            # This is dummy output, not a real approval request.
            echo 'Approval required: https://login.tailscale.com/admin/dns'
            return 1
        fi

        # Simulate Serve succeeding after approval.
        return 0
    }

    # Replace Bash's read command so the test does not
    # pause waiting for someone to press Enter.
    #
    # Returning success approximates the user confirming
    # that they have completed the approval step.
    read() {
        return 0
    }

    run configure_serve

    [ "$status" -eq 0 ]
    [[ "$output" == *'Approval required'* ]]
    [[ "$output" == *'configured successfully'* ]]

    # Confirm Serve was attempted twice.
    [ "$(cat "$counter")" -eq 2 ]
}

@test "configure_serve stops after maximum retries" {

    # Simulate a permanent Serve configuration failure.
    #
    # Unlike the previous test, every attempt fails.
    # This could represent a persistent permission problem,
    # unavailable service, or an approval that never happens.
    #
    # The installer must eventually stop rather than
    # retrying indefinitely.

    local counter="$TEST_TMPDIR/serve-count"
    echo 0 > "$counter"

    ts() {
        local n
        n=$(cat "$counter")
        echo "$((n + 1))" > "$counter"

        echo 'Serve unavailable'
        return 1
    }

    # Simulate the user pressing Enter for each retry.
    read() {
        return 0
    }

    SERVE_RETRIES=3

    run configure_serve

    [ "$status" -ne 0 ]
    [[ "$output" == *'Could not configure Tailscale Serve'* ]]

    # Verify the script respected the configured retry limit.
    [ "$(cat "$counter")" -eq 3 ]
}

# ==================================================
# MAIN SETUP TESTS
# ==================================================

@test "main prints the hostname without a trailing dot" {

    # Simulate successful prerequisite checks,
    # authentication, and Serve configuration.
    #
    # These steps are mocked because this test focuses
    # specifically on the final HTTPS URL displayed
    # to the user.
    check_requirements() {
        return 0
    }

    configure_login() {
        return 0
    }

    configure_serve() {
        return 0
    }

    # Simulate successful Serve status output.
    ts() {
        echo 'https://mycloud.example.ts.net'
    }

    # Tailscale's DNSName normally ends with a dot,
    # representing a fully qualified DNS name.
    #
    # The installer should remove that trailing dot
    # when displaying a user-friendly HTTPS URL.
    get_status() {
        echo '{"Self":{"DNSName":"mycloud.example.ts.net."}}'
    }

    run main

    [ "$status" -eq 0 ]
    [[ "$output" == *'https://mycloud.example.ts.net'* ]]
    [[ "$output" != *'https://mycloud.example.ts.net.'* ]]
}

@test "main fails when Tailscale has no DNS hostname" {

    # Simulate a successful login and Serve setup,
    # but an incomplete status response where Tailscale
    # does not provide the device's DNS hostname.
    #
    # The installer should report an error instead
    # of displaying an invalid URL such as https://.
    check_requirements() {
        return 0
    }

    configure_login() {
        return 0
    }

    configure_serve() {
        return 0
    }

    ts() {
        return 0
    }

    get_status() {
        echo '{"Self":{}}'
    }

    run main

    [ "$status" -ne 0 ]
    [[ "$output" == *'Could not determine Tailscale hostname'* ]]
}

@test "main stops if authentication fails" {

    # Simulate an installation where prerequisites pass
    # but the Tailscale login process fails.
    #
    # A failed login must stop the setup immediately.
    # Attempting to configure Serve without authentication
    # would produce confusing follow-up errors.
    check_requirements() {
        return 0
    }

    configure_login() {
        return 1
    }

    # If this function runs, it prints a marker.
    # The test checks that the marker never appears.
    configure_serve() {
        echo 'SHOULD_NOT_RUN'
    }

    run main

    [ "$status" -ne 0 ]
    [[ "$output" != *'SHOULD_NOT_RUN'* ]]
}

@test "main stops if Serve configuration fails" {

    # Simulate a successful authentication followed by
    # a failure while configuring HTTPS access.
    #
    # The installer should not continue to report that
    # the cloud is ready if Serve could not be enabled.
    check_requirements() {
        return 0
    }

    configure_login() {
        return 0
    }

    configure_serve() {
        return 1
    }

    # This marker represents a later Tailscale command
    # that should never execute after Serve fails.
    ts() {
        echo 'SHOULD_NOT_RUN'
    }

    run main

    [ "$status" -ne 0 ]
    [[ "$output" != *'SHOULD_NOT_RUN'* ]]
}
