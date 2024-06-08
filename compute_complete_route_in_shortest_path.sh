#!/bin/bash

SOURCE_DESTINATION_NODES_FILE="data/source_destination_nodes_generated.json"
PUBKEYS_FILE="data/lnd_node_pubkeys.json"

# Function to get the LND node name from the pubkey
function get_lnd_node_name() {
  local pubkey=$1
  jq -r --arg pubkey "$pubkey" 'to_entries[] | select(.value == $pubkey) | .key' $PUBKEYS_FILE
}

# Function to reset MC data
function reset_mc_data() {
  local node=$1
  docker exec "$node" lncli --network=regtest resetmc
}

# Function to compute the complete route in the shortest path
function compute_complete_route_in_shortest_path() {
  local source=$1
  local destination=$2
  local source_pubkey=$3
  local destination_pubkey=$4

  echo "Computing shortest path from $source to $destination"

  # Generate an invoice on the destination node
  INVOICE=$(docker exec "$destination" lncli --network=regtest addinvoice --amt=10)
  PAYMENT_REQUEST=$(echo "$INVOICE" | jq -r '.payment_request')

  # Pay the invoice from the source node
  PAYMENT_RESULT=$(docker exec "$source" lncli --network=regtest payinvoice --json --force "$PAYMENT_REQUEST")
  echo "$PAYMENT_RESULT" | jq .

  reset_mc_data "$source"

  # Extract the route's hops
  HOPS=$(echo "$PAYMENT_RESULT" | jq -r '.htlcs[0].route.hops')
  HOP_COUNT=$(echo "$HOPS" | jq -r 'length')

  # Initialize an array to store the route
  ROUTE=("$source")

  for (( i=0; i<$HOP_COUNT; i++ )); do
    HOP_PUBKEY=$(echo "$HOPS" | jq -r ".[$i].pub_key")
    HOP_NAME=$(get_lnd_node_name "$HOP_PUBKEY")
    ROUTE+=("$HOP_NAME")
  done

  # Join the route array into a JSON array string
  ROUTE_JSON=$(printf '%s\n' "${ROUTE[@]}" | jq -R . | jq -s .)

  echo "Complete route in the shortest path computed from $source to $destination: $ROUTE_JSON"

  # Update the source-destination nodes file with the complete route
  jq --arg source_pubkey "$source_pubkey" --arg destination_pubkey "$destination_pubkey" --argjson route "$ROUTE_JSON" '
    map(
      if .source_pubkey == $source_pubkey and .destination_pubkey == $destination_pubkey then
        . + {complete_route_in_shortest_path: $route}
      else
        .
      end
    )' "$SOURCE_DESTINATION_NODES_FILE" > temp.json && mv temp.json "$SOURCE_DESTINATION_NODES_FILE"
}

# Read the source destination nodes data
SOURCE_DESTINATION_NODES=$(jq -c '.[]' $SOURCE_DESTINATION_NODES_FILE)

echo "$SOURCE_DESTINATION_NODES" | while IFS= read -r source_destination; do
  SOURCE_NODE=$(echo "$source_destination" | jq -r '.source')
  SOURCE_NODE_PUBKEY=$(echo "$source_destination" | jq -r '.source_pubkey')
  DESTINATION_NODE=$(echo "$source_destination" | jq -r '.destination')
  DESTINATION_NODE_PUBKEY=$(echo "$source_destination" | jq -r '.destination_pubkey')

  compute_complete_route_in_shortest_path "$SOURCE_NODE" "$DESTINATION_NODE" "$SOURCE_NODE_PUBKEY" "$DESTINATION_NODE_PUBKEY"
done

echo "Complete routes in shortest paths have been computed."
