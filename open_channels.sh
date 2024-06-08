#!/bin/bash

# Check if the number of LND containers is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_lnd_containers>"
  exit 1
fi

NUM_CONTAINERS=$1
CHANNELS_FILE="data/channel_graph.json"

# Function to open a channel between two LND nodes
function open_channel() {
  local from_container=$1
  local to_container=$2
  local from_pubkey=$3
  local to_pubkey=$4
  local capacity=$5
  local base_fees=$6

  echo "Opening channel from $from_container to $to_container with capacity $capacity and base fees $base_fees msats"

  # Use the lncli command to open a channel.
  docker exec "$from_container" lncli --network=regtest openchannel --node_key="$to_pubkey" --connect "$to_container:9735" --local_amt="$capacity" --base_fee_msat="$base_fees"

  # Generate LND address for the initiator.
  ADDR=$(docker exec "$from_container" lncli --network=regtest newaddress p2wkh | jq -r '.address')

  # Mine at 3 blocks for the channel funding tx.
  docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 3 $ADDR

  echo "Opening channel from $to_container to $from_container with capacity $capacity and base fees $base_fees msats"

  # Use the lncli command to open a channel.
  docker exec "$to_container" lncli --network=regtest openchannel --node_key="$from_pubkey" --connect "$from_container:9735" --local_amt="$capacity" --base_fee_msat="$base_fees"

  # Generate LND address for the initiator.
  ADDR=$(docker exec "$to_container" lncli --network=regtest newaddress p2wkh | jq -r '.address')

  # Mine at 3 blocks for the channel funding tx.
  docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 3 $ADDR
}

# Read the channel graph data
CHANNELS=$(jq -c '.[]' $CHANNELS_FILE)

# Open channels based on the channel graph data and compute shortest paths would useful for deliberate testing later.
echo "$CHANNELS" | while IFS= read -r channel; do
  FROM=$(echo "$channel" | jq -r '.from')
  TO=$(echo "$channel" | jq -r '.to')
  FROM_PUBKEY=$(echo "$channel" | jq -r '.from_pubkey')
  TO_PUBKEY=$(echo "$channel" | jq -r '.to_pubkey')
  CAPACITY=$(echo "$channel" | jq -r '.capacity')
  BASE_FEES=$(echo "$channel" | jq -r '.base_fees')

  open_channel "$FROM" "$TO" "$FROM_PUBKEY" "$TO_PUBKEY" "$CAPACITY" "$BASE_FEES"
  sleep 10
done

echo "Wait for channel updates to propagate in the network..."
sleep 120
echo "All channels have been opened in the complete graph."
