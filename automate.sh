#!/bin/bash

docker rm -f $(docker ps -aq) && docker volume rm $(docker volume ls -q)

n=15
capacity=60600
min_base_fees=2
max_base_fees=50

cd docker && bash generate-compose.sh docker-compose-template.yml docker-compose.yml $n

bash start-containers.sh $n

cd .. && bash extract_node_pubkeys.sh $n

bash fund_lnd_nodes.sh $n

python channel_graph_generator.py $n $capacity $min_base_fees $max_base_fees

python source_destination_nodes_generator.py $n

bash open_channels.sh $n

bash compute_complete_route_in_shortest_path.sh

bash make_payments.sh
