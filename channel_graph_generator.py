import random
import networkx as nx
import json
import sys

def generate_bipartite_graph(n, channel_capacity, base_fees_range):
    # Subtract one node from total nodes to make place for the target LND node.
    n = n - 1
    
    # Split the nodes into two sets for bipartite graph.
    nodes_set_1 = [f"lnd{i+1}" for i in range(n//2)]
    nodes_set_2 = [f"lnd{i+1+n//2}" for i in range(n - n//2)]
    
    # Create a bipartite graph.
    B = nx.Graph()
    B.add_nodes_from(nodes_set_1, bipartite=0)
    B.add_nodes_from(nodes_set_2, bipartite=1)
    
    # Create connections between the two sets randomly.
    for u in nodes_set_1:
        # Randomly choose a subset of nodes from nodes_set_2 to connect to.
        subset_size = random.randint(1, len(nodes_set_2))
        nodes_to_connect = random.sample(nodes_set_2, subset_size)
        for v in nodes_to_connect:
            B.add_edge(u, v)
    
    # Create a list of edges in the desired JSON format
    edges_list = [
        {
            "from": "lnd",
            "to": nodes_set_1[0],
            "from_pubkey": "",
            "to_pubkey": "",
            "capacity": channel_capacity,
            "base_fees": 0
        },
        {
            "from": "lnd",
            "to": nodes_set_2[0],
            "from_pubkey": "",
            "to_pubkey": "",
            "capacity": channel_capacity,
            "base_fees": 0
        }
    ]
    
    for u, v in B.edges():
        edge = {
            "from": u,
            "to": v,
            "from_pubkey": "",
            "to_pubkey": "",
            "capacity": channel_capacity,
            "base_fees": random.randint(*base_fees_range)
        }
        edges_list.append(edge)
    
    return edges_list

def update_graph_with_node_pubkeys(pubkeys_file, edges_list, n):
    # Read the pubkeys from the JSON file
    with open(pubkeys_file, 'r') as f:
        pubkeys = json.load(f)

    if len(list(pubkeys.values())) < n:
        raise ValueError("Not enough pubkeys to generate the graph")

    for edge in edges_list:
        edge['from_pubkey'] = pubkeys[edge['from']]
        edge['to_pubkey'] = pubkeys[edge['to']]

def store_channel_graph(edges_list):
    # Convert the list to JSON format
    edges_json = json.dumps(edges_list, indent=4)

    # Optionally, write to a file
    with open("data/channel_graph.json", "w") as f:
        f.write(edges_json)

if __name__ == "__main__":
    if len(sys.argv) < 2 or len(sys.argv) == 4 or len(sys.argv) > 5:
        print("Usage: python script.py <number_of_nodes> [channel_capacity] [base_fees_range_min base_fees_range_max]")
        sys.exit(1)

    n = int(sys.argv[1])

    if len(sys.argv) >= 3:
        channel_capacity = int(sys.argv[2])
    else:
        channel_capacity = 60000

    if len(sys.argv) == 5:
        base_fees_range = (int(sys.argv[3]), int(sys.argv[4]))
    else:
        base_fees_range = (2, 500)

    edges_list = generate_bipartite_graph(n, channel_capacity, base_fees_range)

    update_graph_with_node_pubkeys("data/lnd_node_pubkeys.json", edges_list, n)

    store_channel_graph(edges_list)
