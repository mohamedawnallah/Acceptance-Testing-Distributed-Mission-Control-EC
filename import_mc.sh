#!/bin/bash

# Function to display usage information.
function usage() {
    echo "Usage: $0 <pairs> [macaroon_path] [tls_cert] [lnd_rest_host]"
    echo
    echo "Arguments:"
    echo "  pairs          A list of pairs to import (required)"
    echo
    echo "Example:"
    echo "  $0 '[{\"node_from\":\"node_from_pub_key_hex\",\"node_to\":\"node_to_pubkey\",\"history\":{}}]'"
}

# Variables.
pairs=$1
macaroon_path="/root/.lnd/data/chain/bitcoin/regtest/admin.macaroon"
tls_cert="/root/.lnd/tls.cert"
lnd_rest_host="localhost:8080"

# Check if pairs is provided.
if [ -z "$1" ]; then
    echo "Error: pairs is required."
    usage
    exit 1
fi

# Initialize an empty JSON array for modified pairs.
modified_pairs="[]"

# Loop over each pair to encode node_from and node_to.
echo "Original and encoded pairs:"
for pair in $pairs; do
    echo "pair" "$pair"
    node_from=$(echo "$pair" | jq -r ".node_from")
    echo "node_from" $node_from
    node_to=$(echo "$pair" | jq -r ".node_to")
    echo "node_to" $node_to
    history=$(echo "$pair" | jq ".history")
    echo "node_to" $node_to
    echo "history" "$history"

    # # Convert hexadecimal to binary and then to Base64.
    node_from_base64=$(echo -n $node_from | xxd -r -p | base64)
    node_to_base64=$(echo -n $node_to | xxd -r -p | base64)

    # Construct new JSON object with modified node_from and node_to.
    new_pair=$(jq -n --arg nf "$node_from_base64" --arg nt "$node_to_base64" --argjson hist "$history" \
        '{node_from: $nf, node_to: $nt, history: $hist}')

    # # Add to the array of modified pairs.
    modified_pairs=$(echo "$modified_pairs" | jq ". + [$new_pair]")
done

echo "macaroon_path" $macaroon_path

# # Convert the macaroon file to hexadecimal.
docker cp lnd:$macaroon_path /tmp/admin.macaroon
macaroon_hex=$(xxd -ps -u -c 1000 /tmp/admin.macaroon)

# Define the URL and the JSON data.
url="https://$lnd_rest_host/v2/router/x/importhistory"
data="{\"pairs\": $modified_pairs, \"force\": false}"

# Docker execution starts here for POST request.
response_code=$(docker exec lnd /bin/bash -c "
    curl -s -o /dev/null -w \"%{http_code}\" -X POST \"$url\" \
        --header \"Content-Type: application/json\" \
        --header \"Grpc-Metadata-macaroon: $macaroon_hex\" \
        --data '$data' \
        --cacert \"$tls_cert\"
")

echo "RESPONSE CODE: $response_code"

# Check if the request was successful.
if [ "$response_code" -eq 200 ]; then
    echo "Import successful"
else
    echo "Import failed with response code: $response_code"
fi
