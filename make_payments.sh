#!/bin/bash

SOURCE_DESTINATION_NODES_FILE="data/source_destination_nodes_generated.json"
CHANNEL_GRAPH_FILE="data/channel_graph.json"
PUBKEYS_FILE="data/lnd_node_pubkeys.json"
MC_SAMPLES_FILE="data/mc_samples.json"

# Define the percentages for importing sample sizes of MC data.
MC_PERCENTAGES=("5%" "10%" "20%" "30%" "40%" "50%" "60%" "70%" "80%" "90%" "100%")

# Function to fetch channel capacity using channel ID.
function get_channel_capacity() {
  local chan_id=$1
  local source_node=$2
  local channel_info=$(docker exec "$source_node" lncli --network=regtest getchaninfo "$chan_id")
  echo $(echo "$channel_info" | jq -r '.capacity')
}

# Function to create an invoice on the destination node.
function create_invoice() {
  local dest_node=$1
  local amount=$2
  local invoice=$(docker exec "$dest_node" lncli --network=regtest addinvoice --amt "$amount")
  echo $(echo "$invoice" | jq -r '.payment_request')
}

# Function to pay an invoice from the source node.
function pay_invoice() {
  local source_node=$1
  local payment_request=$2
  local outgoing_chan_id=$3
  if [ -n "$outgoing_chan_id" ]; then
    local response=$(docker exec "$source_node" lncli --network=regtest payinvoice --json --pay_req "$payment_request" --force --outgoing_chan_id "$outgoing_chan_id")
  else
    local response=$(docker exec "$source_node" lncli --network=regtest payinvoice --json --pay_req "$payment_request" --force)
  fi

  echo "$response"
}

# Function to fetch the channel ID between two nodes with the highest local balance.
function get_outbound_channel_id() {
  local node1=$1
  local node2_pubkey=$2
  local highest_local_balance=0
  local channel_id=""

  # Loop through each channel
  while read -r channel; do
    local local_balance=$(echo "$channel" | jq -r '.local_balance')
    if (( $(echo "$local_balance > $highest_local_balance" | bc -l) )); then
      highest_local_balance=$local_balance
      channel_id=$(echo "$channel" | jq -r '.chan_id')
    fi
  done <<< "$(docker exec $node1 lncli --network=regtest listchannels | jq -c ".channels[] | select(.remote_pubkey==\"$node2_pubkey\" and .initiator==true)")"

  echo "$channel_id"
}

# Function to query MC data
function query_mc_data() {
  local node=$1
  docker exec "$node" lncli --network=regtest querymc
}

# Function to reset MC data
function reset_mc_data() {
  local node=$1
  docker exec "$node" lncli --network=regtest resetmc
}

# Function to estimate routing fee.
function estimate_route_fee() {
  local source_node=$1
  local dest_pubkey=$2
  local amount=$3
  local fee_info=$(docker exec "$source_node" lncli --network=regtest estimateroutefee --dest "$dest_pubkey" --amt "$amount")
  local routing_fee_msat=$(echo "$fee_info" | jq -r '.routing_fee_msat')
  local routing_fee_sat=$(( (routing_fee_msat + 999) / 1000 )) # Taking ceiling value
  echo "$routing_fee_sat"
}

# Function to get the LND node name from the pubkey.
function get_lnd_node_name() {
  local pubkey=$1
  jq -r --arg pubkey "$pubkey" 'to_entries[] | select(.value == $pubkey) | .key' $PUBKEYS_FILE
}

# Function to import all mission control data inside LND.
function import_all_mc_data() {
  local node=$1
  docker exec "$node" lncli --network=regtest importmc
}

# Function to make payments and handle failures.
function make_payments() {
  local source_destination=$1
  local mc_percentage=$2
  local use_historical_mc_data=false  # Default to false, indicating historical data should NOT be used.
  # Check if mc_sample and mc_percentage are NOT provided
  if [[ -n "$mc_percentage" ]]; then
    use_historical_mc_data=true  # Set to true, indicating historical data should be used.
  fi
  SOURCE_NODE=$(echo "$source_destination" | jq -r '.source')
  SOURCE_NODE_PUBKEY=$(echo "$source_destination" | jq -r '.source_pubkey')
  LAST_NODE_PUBKEY=$(echo "$source_destination" | jq -r '.destination_pubkey')
  COMPLETE_ROUTE_IN_SHORTEST_PATH=$(echo "$source_destination" | jq -r '.complete_route_in_shortest_path | @sh')
  COMPLETE_ROUTE_IN_SHORTEST_PATH=${COMPLETE_ROUTE_IN_SHORTEST_PATH//\'/}
  IFS=' ' read -r -a PATH_ARRAY <<< "$COMPLETE_ROUTE_IN_SHORTEST_PATH"

  # Check if the path has more than two nodes excluding the source node otherwise there will be no failed attempts.
  PATH_LENGTH=${#PATH_ARRAY[@]}
  if [ $PATH_LENGTH -gt 2 ]; then
    # Get the last two nodes to form the last edge
    LAST_NODE="${PATH_ARRAY[$((PATH_LENGTH - 1))]}"
    SECOND_LAST_NODE="${PATH_ARRAY[$((PATH_LENGTH - 2))]}"
    SECOND_LAST_NODE_PUBKEY=$(docker exec "$SECOND_LAST_NODE" lncli --network=regtest getinfo | jq -r '.identity_pubkey')
    echo "Last node: $LAST_NODE"
    echo "Second last node: $SECOND_LAST_NODE"

    # Fetch the channel ID between the second last node and the last node.
    CHANNEL_ID=$(get_outbound_channel_id "$SECOND_LAST_NODE" "$LAST_NODE_PUBKEY")
    echo "Channel ID: $CHANNEL_ID"
    if [ -z "$CHANNEL_ID" ]; then
      echo "Failed to fetch channel ID."
      continue
    fi

    # Calculate Channel Capacity without Reserve Sats, Commit Fee, ANCHORS fees, and fixed backup value (1000).
    CHANNEL_CAPACITY=$(get_channel_capacity "$CHANNEL_ID" "$SECOND_LAST_NODE")
    echo "Channel capacity: $CHANNEL_CAPACITY"
    if [ -z "$CHANNEL_CAPACITY" ] || [ "$CHANNEL_CAPACITY" -eq 0 ]; then
      echo "Failed to fetch channel capacity or channel capacity is zero."
      continue
    fi
    COMMIT_FEE=$(docker exec "$SOURCE_NODE" lncli --network=regtest getchaninfo "$CHANNEL_ID" | jq -r '.commit_fee')
    CHANNEL_MIN_RESERVE_SATS=$(awk "BEGIN {print int(0.01 * $CHANNEL_CAPACITY)}")
    CHANNEL_CAPACITY_PURE=$(awk "BEGIN {print int($CHANNEL_CAPACITY - $CHANNEL_MIN_RESERVE_SATS - 2 * 330 - $COMMIT_FEE - 1000)}")

    if [[ "$use_historical_mc_data" == false ]]; then
      # Make a payment to fail the last edge.
      PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE=$((CHANNEL_CAPACITY_PURE / 2))
      echo "Payment amount to fail last edge (half of channel capacity): $PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE"
      ROUTE_FEE_SAT=$(estimate_route_fee "$SECOND_LAST_NODE" "$LAST_NODE_PUBKEY" "$PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE")
      echo "ROUTE_FEE_SAT: " $ROUTE_FEE_SAT
      TOTAL_PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE=$((PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE + $ROUTE_FEE_SAT))
      echo "Total payment amount including routing fee: $TOTAL_PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE"
      PAYMENT_REQUEST=$(create_invoice "$LAST_NODE" "$TOTAL_PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE")
      echo "Payment request: $PAYMENT_REQUEST"
      payment_response_failing_last_edge=$(pay_invoice "$SECOND_LAST_NODE" "$PAYMENT_REQUEST")
      echo "Payment made from $SECOND_LAST_NODE to $LAST_NODE with amount $TOTAL_PAYMENT_AMOUNT_TO_FAIL_LAST_EDGE with response:"
      echo "$payment_response_failing_last_edge" | jq .
      failure_reason=$(echo "$payment_response_failing_last_edge" | jq -r '.failure_reason')
      if [ "$failure_reason" = "FAILURE_REASON_INSUFFICIENT_BALANCE" ]; then
        echo "Failure reason: $failure_reason"
        break
      fi
      reset_mc_data "$SOURCE_NODE"
    fi
 
    # Make a payment from source to destination after failing last edge.
    PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE=$((CHANNEL_CAPACITY_PURE * 2 / 3))
    echo "Payment amount after failing last edge (two thirds of channel capacity): $PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE"
    ROUTE_FEE_SAT=$(estimate_route_fee "$SOURCE_NODE" "$LAST_NODE_PUBKEY" "$PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE")
    echo "ROUTE_FEE_SAT: " $ROUTE_FEE_SAT
    TOTAL_PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE=$((PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE + $ROUTE_FEE_SAT))
    echo "Total payment amount including routing fee: $TOTAL_PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE"
    PAYMENT_REQUEST=$(create_invoice "$LAST_NODE" "$TOTAL_PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE")
    echo "Payment request: $PAYMENT_REQUEST"
    payment_response_after_failing_last_edge=$(pay_invoice "$SOURCE_NODE" "$PAYMENT_REQUEST")
    echo "Payment made from $SOURCE_NODE to $LAST_NODE with amount $TOTAL_PAYMENT_AMOUNT_AFTER_FAILING_LAST_EDGE with response:"
    echo "$payment_response_after_failing_last_edge" | jq .
    failure_reason=$(echo "$payment_response_after_failing_last_edge" | jq -r '.failure_reason')
    if [ "$failure_reason" = "FAILURE_REASON_INSUFFICIENT_BALANCE" ]; then
      echo "Failure reason: $failure_reason"
      break
    fi

    if [[ "$use_historical_mc_data" == false ]]; then
      new_field="payment_attempts_before_mc"
    else
      new_field="payment_attempts_after_mc_${mc_percentage}"
    fi
    
    # Inject mc_data and payment response under the dynamically named field.
    mc_data=$(query_mc_data "$SOURCE_NODE")
    source_destination=$(echo "$source_destination" | jq --argjson mc_data "$mc_data" '. + {mc_data: $mc_data}' | jq --arg new_field "$new_field" --argjson new_field_value "$payment_response_after_failing_last_edge" '. + {($new_field): $new_field_value}')
    jq --argjson source_destination "$source_destination" '.[] |= if .destination_pubkey == $source_destination.destination_pubkey then $source_destination else . end' "$SOURCE_DESTINATION_NODES_FILE" > temp.json && mv temp.json "$SOURCE_DESTINATION_NODES_FILE"

    if [[ "$use_historical_mc_data" == false ]]; then
      # Reverse the payment of failing the last edge.
      HOPS=$(echo "$payment_response_failing_last_edge" | jq -r '.htlcs[-1].route.hops')
      HOP_COUNT=$(echo "$HOPS" | jq -r 'length')
      ROUTE_ARRAY=("$SECOND_LAST_NODE")
      CHANNEL_ID_ARRAY=("")
      for (( i=0; i<$HOP_COUNT; i++ )); do
        HOP_PUBKEY=$(echo "$HOPS" | jq -r ".[$i].pub_key")
        HOP_NAME=$(get_lnd_node_name "$HOP_PUBKEY")
        CHANNEL_ID=$(echo "$HOPS" | jq -r ".[$i].chan_id")
        ROUTE_ARRAY+=("$HOP_NAME")
        CHANNEL_ID_ARRAY+=("$CHANNEL_ID")
      done
      ROUTE_LENGTH=${#ROUTE_ARRAY[@]}
      for ((i = $ROUTE_LENGTH - 1; i > 0; i--)); do
          CURRENT_NODE="${ROUTE_ARRAY[$i]}"
          PREVIOUS_NODE="${ROUTE_ARRAY[$((i - 1))]}"
      done
      for ((i = $ROUTE_LENGTH - 1; i > 0; i--)); do
        CURRENT_NODE="${ROUTE_ARRAY[$i]}"
        PREVIOUS_NODE="${ROUTE_ARRAY[$((i - 1))]}"
        FUNDING_TX_ID="${FUNDING_TX_ID_ARRAY[$i]}"
        CHANNEL_ID="${CHANNEL_ID_ARRAY[$i]}"
        CHANNEL_POINT=$(docker exec "$PREVIOUS_NODE" lncli --network=regtest listchannels | jq -r --arg CHANNEL_ID "$CHANNEL_ID" '.channels[] | select(.chan_id == $CHANNEL_ID) | .channel_point')
        FUNDING_TX_ID=$(echo "$CHANNEL_POINT" | cut -d ":" -f 1)
        CURRENT_NODE_PUBKEY=$(docker exec "$CURRENT_NODE" lncli --network=regtest getinfo | jq -r '.identity_pubkey')
        PREVIOUS_NODE_PUBKEY=$(docker exec "$PREVIOUS_NODE" lncli --network=regtest getinfo | jq -r '.identity_pubkey')
        channel_data=$(jq --arg from "$PREVIOUS_NODE_PUBKEY" --arg to "$CURRENT_NODE_PUBKEY" '.[] | select(.from_pubkey == $from and .to_pubkey == $to)' "$CHANNEL_GRAPH_FILE")
        if [ -z "$channel_data" ]; then
            # If the initial query returns nothing, swap the values and try again
            channel_data=$(jq --arg from "$CURRENT_NODE_PUBKEY" --arg to "$PREVIOUS_NODE_PUBKEY" '.[] | select(.from_pubkey == $from and .to_pubkey == $to)' "$CHANNEL_GRAPH_FILE")
        fi
        capacity=$(echo "$channel_data" | jq -r '.capacity')
        base_fees=$(echo "$channel_data" | jq -r '.base_fees')
        docker exec "$PREVIOUS_NODE" lncli --network=regtest openchannel --node_key="$CURRENT_NODE_PUBKEY" --connect "$CURRENT_NODE:9735" --local_amt="$capacity" --base_fee_msat="$base_fees"
        docker exec  "$PREVIOUS_NODE" lncli --network=regtest closechannel --force "$FUNDING_TX_ID"
        docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 6 "2N1NQzFjCy1NnpAH3cT4h4GoByrAAkiH7zu"
        reset_mc_data "$CURRENT_NODE"
        sleep 10
      done
      reset_mc_data "$SECOND_LAST_NODE"
    fi

    # Reverse the payment from source to destination.
    HOPS=$(echo "$payment_response_after_failing_last_edge" | jq -r '.htlcs[-1].route.hops')
    HOP_COUNT=$(echo "$HOPS" | jq -r 'length')
    ROUTE_ARRAY=("$SOURCE_NODE")
    CHANNEL_ID_ARRAY=("")
    for (( i=0; i<$HOP_COUNT; i++ )); do
      HOP_PUBKEY=$(echo "$HOPS" | jq -r ".[$i].pub_key")
      HOP_NAME=$(get_lnd_node_name "$HOP_PUBKEY")
      CHANNEL_ID=$(echo "$HOPS" | jq -r ".[$i].chan_id")
      ROUTE_ARRAY+=("$HOP_NAME")
      CHANNEL_ID_ARRAY+=("$CHANNEL_ID")
    done
    ROUTE_LENGTH=${#ROUTE_ARRAY[@]}
    for ((i = $ROUTE_LENGTH - 1; i > 0; i--)); do
        CURRENT_NODE="${ROUTE_ARRAY[$i]}"
        PREVIOUS_NODE="${ROUTE_ARRAY[$((i - 1))]}"
    done
    for ((i = $ROUTE_LENGTH - 1; i > 0; i--)); do
      CURRENT_NODE="${ROUTE_ARRAY[$i]}"
      PREVIOUS_NODE="${ROUTE_ARRAY[$((i - 1))]}"
      FUNDING_TX_ID="${FUNDING_TX_ID_ARRAY[$i]}"
      echo "CURRENT_NODE:" $CURRENT_NODE
      echo "PREVIOUS_NODE:" $PREVIOUS_NODE

      CHANNEL_ID="${CHANNEL_ID_ARRAY[$i]}"
      echo "CHANNEL_ID:" $CHANNEL_ID
      CHANNEL_POINT=$(docker exec "$PREVIOUS_NODE" lncli --network=regtest listchannels | jq -r --arg CHANNEL_ID "$CHANNEL_ID" '.channels[] | select(.chan_id == $CHANNEL_ID) | .channel_point')
      echo "CHANNEL_POINT:" $CHANNEL_POINT
      FUNDING_TX_ID=$(echo "$CHANNEL_POINT" | cut -d ":" -f 1)
      echo "FUNDING_TX_ID:" $FUNDING_TX_ID     

      CURRENT_NODE_PUBKEY=$(docker exec "$CURRENT_NODE" lncli --network=regtest getinfo | jq -r '.identity_pubkey')
      PREVIOUS_NODE_PUBKEY=$(docker exec "$PREVIOUS_NODE" lncli --network=regtest getinfo | jq -r '.identity_pubkey')

      # Find the channel data matching the current and previous nodes.
      channel_data=$(jq --arg from "$PREVIOUS_NODE_PUBKEY" --arg to "$CURRENT_NODE_PUBKEY" '.[] | select(.from_pubkey == $from and .to_pubkey == $to)' "$CHANNEL_GRAPH_FILE")
      if [ -z "$channel_data" ]; then
          # If the initial query returns nothing, swap the values and try again
          channel_data=$(jq --arg from "$CURRENT_NODE_PUBKEY" --arg to "$PREVIOUS_NODE_PUBKEY" '.[] | select(.from_pubkey == $from and .to_pubkey == $to)' "$CHANNEL_GRAPH_FILE")
      fi
      echo "CHANNEL DATA:" "$channel_data"

      # Extract capacity and base fees from the channel data
      capacity=$(echo "$channel_data" | jq -r '.capacity')
      base_fees=$(echo "$channel_data" | jq -r '.base_fees')

      echo "CAPACITY FOUND: " "$capacity"
      echo "BASE FEES FOUND: " "$base_fees"
  
      docker exec "$PREVIOUS_NODE" lncli --network=regtest openchannel --node_key="$CURRENT_NODE_PUBKEY" --connect "$CURRENT_NODE:9735" --local_amt="$capacity" --base_fee_msat="$base_fees"
      docker exec  "$PREVIOUS_NODE" lncli --network=regtest closechannel --force "$FUNDING_TX_ID"
      docker exec bitcoind bitcoin-cli -chain=regtest -rpcuser=devuser -rpcpassword=devpass generatetoaddress 3 "2N1NQzFjCy1NnpAH3cT4h4GoByrAAkiH7zu"
      reset_mc_data "$CURRENT_NODE"
      sleep 5
    done
    reset_mc_data "$SOURCE_NODE"
  fi 
}

# Loop through each source-destination pair and make payments.
SOURCE_DESTINATION_NODES=$(jq -c '.[]' "$SOURCE_DESTINATION_NODES_FILE")
echo "$SOURCE_DESTINATION_NODES" | while IFS= read -r source_destination; do
  echo "Processing: "
  echo "$source_destination" | jq .
  make_payments "$source_destination"
done

# Generate the mc_samples based on the percentages.
python process_mc_samples.py

# Loop through mc percentages and each source-destination pair to make payments based on historical MC data.
for percentage in "${MC_PERCENTAGES[@]}"; do
  # Import all historical mc data before making a payment.
  mc_sample=$(jq -c ".[\"$percentage\"][]" "$MC_SAMPLES_FILE")
  bash import_mc.sh $mc_sample
  sleep 1
  # Make the payments for each source-destination node.
  SOURCE_DESTINATION_NODES=$(jq -c '.[]' "$SOURCE_DESTINATION_NODES_FILE")
  echo "$SOURCE_DESTINATION_NODES" | while IFS= read -r source_destination; do
    echo "$source_destination" | jq .
    make_payments "$source_destination" "$percentage"
  done
  reset_mc_data "lnd"
done
