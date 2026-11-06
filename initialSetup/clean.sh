#!/bin/bash
set -euo pipefail

# Require root permissions.
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run this script with sudo."
    exit 1
fi

echo "WARNING: This will delete ALL Docker containers,"
echo "images, volumes, and unused networks on this machine."
echo "All Nextcloud data and Tailscale login state will be lost."
echo

read -r -p "Type DELETE to continue: " CONFIRM

if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Stopping and removing Docker containers..."

# Remove all containers, including stopped ones.
CONTAINERS=$(docker ps -aq)
if [[ -n "$CONTAINERS" ]]; then
    docker rm -f $CONTAINERS
fi

echo "Removing Docker images..."

# Remove all images.
IMAGES=$(docker images -aq)
if [[ -n "$IMAGES" ]]; then
    docker rmi -f $IMAGES
fi

echo "Removing Docker volumes..."

# Remove all volumes, including Nextcloud and Tailscale data.
VOLUMES=$(docker volume ls -q)
if [[ -n "$VOLUMES" ]]; then
    docker volume rm -f $VOLUMES
fi

echo "Removing unused Docker networks..."

# Remove unused custom networks and other unused resources.
docker network prune -f
docker system prune -af --volumes

echo
echo "Docker cleanup complete!"
echo "Docker Engine and Docker Compose are still installed."
