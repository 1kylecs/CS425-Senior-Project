#!/bin/bash

# script to create a new Nextcloud user account

USERNAME="$1"

# check that a username was provided
if [ -z "$USERNAME" ]; then
    echo "Error: Please provide a username."
    exit 1
fi

if sudo docker exec -it -u www-data nextcloud php occ user:add "$USERNAME"; then
    echo "User creation completed"
else
    echo "Error: User creation failed"
    exit 1
fi
