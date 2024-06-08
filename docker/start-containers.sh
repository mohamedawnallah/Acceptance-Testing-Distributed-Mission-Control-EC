#!/bin/bash

# Check if the number of LND containers is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_lnd_containers>"
  exit 1
fi

NUM_CONTAINERS=$1

# Start bitcoind first
docker-compose up -d bitcoind

# Wait for bitcoind to be fully ready (you may need to adjust the sleep time or add a more sophisticated check)
echo "Waiting for bitcoind to be ready..."
sleep 2

ADDR="2N1NQzFjCy1NnpAH3cT4h4GoByrAAkiH7zu"
docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 100 $ADDR

# Start each lnd container sequentially
for i in $(seq 0 $((NUM_CONTAINERS - 1))); do
  if [ "$i" -eq 0 ]; then
    NAME="lnd"
  else
    NAME="lnd$i"
  fi

  docker-compose up -d $NAME

  # Sleep for 10 seconds before starting the new LND node not to overwhelm the
  # docker backend, except for the last container.
  if [ "$i" -lt $((NUM_CONTAINERS - 1)) ]; then
    echo "Started $NAME, waiting before starting the next one..."
    sleep 2
  fi
done

echo "Wait for all containers to start..."
sleep 120
echo "All containers have been started."
