#!/bin/bash

# Check if the number of LND containers is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_lnd_containers>"
  exit 1
fi

NUM_CONTAINERS=$1
PUBKEYS_FILE="data/lnd_node_pubkeys.json"

# Function to extract the node identity pub key
function extract_pubkey() {
  local container_name=$1

  # Get the node identity pub key
  local pubkey=$(docker exec "$container_name" lncli --network=regtest getinfo | jq -r '.identity_pubkey')

  # Check if PUBKEY is empty or not
  if [ -z "$pubkey" ]; then
    echo "Failed to get pubkey for $container_name"
    exit 1
  fi

  echo "$pubkey"
}

# Initialize an empty JSON object
echo "{" > $PUBKEYS_FILE

# Loop through each LND container and extract the node identity pub key
for i in $(seq 0 $((NUM_CONTAINERS - 1))); do
  if [ "$i" -eq 0 ]; then
    NAME="lnd"
  else
    NAME="lnd$i"
  fi

  # Extract the pub key using the function
  PUBKEY=$(extract_pubkey "$NAME")

  # Append the pub key to the JSON file
  if [ "$i" -eq $((NUM_CONTAINERS - 1)) ]; then
    echo "  \"$NAME\": \"$PUBKEY\"" >> $PUBKEYS_FILE
  else
    echo "  \"$NAME\": \"$PUBKEY\"," >> $PUBKEYS_FILE
  fi
done

# Close the JSON object.
echo "}" >> $PUBKEYS_FILE

echo "Public keys have been written to $PUBKEYS_FILE"
