#!/usr/bin/env bash

set -euo pipefail

# Stop installation if the script is not running with root privileges.
# Installing packages and modifying system directories requires root access.
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run this script using sudo."
    exit 1
fi

# Ensure APT is available before attempting to install packages.
if ! command -v apt-get &> /dev/null; then
    echo "Error: APT package manager not found."
    exit 1
fi

# Ensure system is using Ubuntu, since installer uses Dockers
# official Ubuntu APT repository
source /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    echo "Error: This installer requires Ubuntu."
    exit 1
fi

echo ""
echo "-------------------------------------------------------"
echo "[1/8] Updating packages and installing dependencies..."
echo "-------------------------------------------------------"

# Update the package index and install the tools needed to
# download Docker's signing key and verify its packages.
apt-get update
apt-get install -y ca-certificates curl

echo ""
echo "-------------------------------------------------------"
echo "[2/8] Configuring Docker's package repository..."
echo "-------------------------------------------------------"

# Read the Ubuntu release codename to select correct
# Docker packages for installed Ubuntu version.
UBUNTU_RELEASE="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

# Create the directory used to store trusted APT signing keys.
install -m 0755 -d /etc/apt/keyrings

# Download Docker's official signing key so APT can verify
# the authenticity of packages downloaded from its repository.
curl -fsSL \
    "https://download.docker.com/linux/ubuntu/gpg" \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

# Register Docker's repository with APT.
# The system architecture is detected automatically, allowing
# the same script to run on x86-64 VMs and ARM64 Raspberry Pis.
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_RELEASE}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo ""
echo "-------------------------------------------------------"
echo "[3/8] Installing Docker Engine and Docker Compose..."
echo "-------------------------------------------------------"

# Refresh the package index to include Docker's repository.
# Install Docker Engine, its command-line tools, container runtime,
# and the Compose and Buildx plugins.
apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin


echo ""
echo "-------------------------------------------------------"
echo "[4/8] Starting Docker service..."
echo "-------------------------------------------------------"

# Start Docker immediately and configure it to start
# automatically whenever the server boots.
systemctl enable --now docker

echo ""
echo "-------------------------------------------------------"
echo "[5/8] Verifying Docker installation..."
echo "-------------------------------------------------------"

# Confirm that Docker Engine is installed and its daemon is responding.
# Also verify that the Docker Compose plugin is available.
docker info > /dev/null
docker compose version

echo ""
echo "-------------------------------------------------------"
echo "[6/8] Installation complete!"
echo "-------------------------------------------------------"

# Display installed versions for troubleshooting and verification.
docker --version
docker compose version

echo ""
echo "-------------------------------------------------------"
echo "[7/8] Starting Nextcloud and Tailscale..."
echo "-------------------------------------------------------"


# Get the directory containing this script.
# This ensures Docker Compose can find compose.yaml even if
# the script is executed from a different working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify that the Docker Compose configuration exists.
if [[ ! -f "$SCRIPT_DIR/compose.yaml" ]]; then
    echo "Error: compose.yaml not found in $SCRIPT_DIR"
    exit 1
fi

# Start Nextcloud AIO and Tailscale in the background.
# Docker automatically downloads any missing container images.
docker compose \
    --env-file "$SCRIPT_DIR/default-creds.env" \
     -f "$SCRIPT_DIR/compose.yaml" up -d

echo ""
echo "-------------------------------------------------------"
echo "[8/8] Installation complete!"
echo "-------------------------------------------------------"

# Display the running containers.
docker compose -f "$SCRIPT_DIR/compose.yaml" ps

echo ""
echo "Nextcloud AIO and Tailscale have been started."
echo "Nextcloud AIO setup: https://localhost:8080"
