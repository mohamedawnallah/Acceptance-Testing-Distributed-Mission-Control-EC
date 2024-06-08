#!/bin/bash

# Check if the number of LND containers is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_lnd_containers>"
  exit 1
fi

NUM_CONTAINERS=$1

# Function to fund a single LND container.
function fund_container() {
  local NAME=$1
  
  # Generate a new address for the LND container
  ADDR=$(docker exec $NAME lncli --network=regtest newaddress p2wkh | jq -r '.address')
  echo "Generated address for $NAME: $ADDR"

  # Send coins to the generated address.
  docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 1 $ADDR
  echo "Sent coins to $NAME at address $ADDR"
}

# Fund each LND container.
for i in $(seq 0 $((NUM_CONTAINERS - 1))); do
  if [ "$i" -eq 0 ]; then
    NAME="lnd"
  else
    NAME="lnd$i"
  fi

  fund_container $NAME
  sleep 2
done

echo "Wait for LND nodes funds to be reflected in the network..."
sleep 10

ADDR="2N1NQzFjCy1NnpAH3cT4h4GoByrAAkiH7zu"
docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 100 $ADDR

echo "All LND nodes have been funded."
