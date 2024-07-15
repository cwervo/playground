#!/bin/sh

# Remote details
REMOTE_USER="folk"
REMOTE_HOST="folk0.local"
REMOTE_DIR="~/folk-printed-programs"
REMOTE_FILE="next-id.txt"

# Fetch next ID from remote and decrement to get last ID
next_id=$(ssh ${REMOTE_USER}@${REMOTE_HOST} "cat ${REMOTE_DIR}/${REMOTE_FILE}")
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch the next ID!"
    exit 1
fi

last_id=$((next_id - 1))

# Use scp to download the file using lastID
scp "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${last_id}.pdf" .

# Check the status of scp
if [ $? -ne 0 ]; then
    echo "Error: Failed to download the file!"
    exit 2
fi

echo "Successfully downloaded ${last_id}.pdf"
