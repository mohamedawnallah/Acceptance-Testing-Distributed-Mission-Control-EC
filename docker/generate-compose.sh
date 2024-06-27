#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <template_file> <output_file> <num_nodes>"
  exit 1
fi

# Assign the arguments to variables
TEMPLATE_FILE=$1
OUTPUT_FILE=$2
NUM_NODES=$3

# Copy the template to the actual compose file
cp "$TEMPLATE_FILE" "$OUTPUT_FILE"

# Add the LND services
for i in $(seq 0 $((NUM_NODES - 1))); do
  if [ "$i" -eq 0 ]; then
    NAME="lnd"
  else
    NAME="lnd$i"
  fi
  echo "    $NAME:" >> "$OUTPUT_FILE"
  echo "        image: lnd" >> "$OUTPUT_FILE"
  echo "        container_name: $NAME" >> "$OUTPUT_FILE"
  echo "        build:" >> "$OUTPUT_FILE"
  echo "            context: ./" >> "$OUTPUT_FILE"
  echo "            dockerfile: dev.Dockerfile" >> "$OUTPUT_FILE"
  echo "        environment:" >> "$OUTPUT_FILE"
  echo "            - RPCUSER=devuser" >> "$OUTPUT_FILE"
  echo "            - RPCPASS=devpass" >> "$OUTPUT_FILE"
  echo "            - NETWORK=regtest" >> "$OUTPUT_FILE"
  echo "            - CHAIN=bitcoin" >> "$OUTPUT_FILE"
  echo "            - LND_DEBUG=debug" >> "$OUTPUT_FILE"
  echo "            - BACKEND=bitcoind" >> "$OUTPUT_FILE"
  echo "            - ALIAS=$NAME" >> "$OUTPUT_FILE"
  echo "            - PS1=\u@$NAME#" >> "$OUTPUT_FILE"
  echo "        volumes:" >> "$OUTPUT_FILE"
  echo "            - $NAME:/root/.lnd" >> "$OUTPUT_FILE"
  echo "        entrypoint: [\"./start-lnd.sh\"]" >> "$OUTPUT_FILE"
  echo "        depends_on:" >> "$OUTPUT_FILE"
  echo "            - \"bitcoind\"" >> "$OUTPUT_FILE"
  echo "        links:" >> "$OUTPUT_FILE"
  echo "            - \"bitcoind:blockchain\"" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

# Add the volumes
echo "volumes:" >> "$OUTPUT_FILE"
echo "    bitcoin:" >> "$OUTPUT_FILE"
echo "        driver: local" >> "$OUTPUT_FILE"

for i in $(seq 0 $((NUM_NODES - 1))); do
  if [ "$i" -eq 0 ]; then
    NAME="lnd"
  else
    NAME="lnd$i"
  fi
  echo "    $NAME:" >> "$OUTPUT_FILE"
  echo "        driver: local" >> "$OUTPUT_FILE"
done

echo "Docker Compose file with $NUM_NODES LND nodes has been created as $OUTPUT_FILE."
