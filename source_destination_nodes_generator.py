import json
import sys
import heapq

def generate_source_destination_data(n_nodes):
    file_name = 'data/source_destination_nodes_generated.json'

    # Read the pubkeys from the JSON file
    with open("data/lnd_node_pubkeys.json", 'r') as f:
        pubkeys = json.load(f)

    if len(list(pubkeys.values())) < n_nodes:
        raise ValueError("Not enough pubkeys to make the payments")

    data = []
    for i in range(1, n_nodes):
        entry = {"source": "lnd", "destination": f"lnd{i}"}
        entry["source_pubkey"] = pubkeys[entry["source"]]
        entry["destination_pubkey"] = pubkeys[entry["destination"]]
        data.append(entry)

    with open(file_name, 'w') as json_file:
        json.dump(data, json_file, indent=4)

    return data

def save_results(output_file, results):
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python script.py <number_of_nodes>")
        sys.exit(1)

    n = int(sys.argv[1])

    source_destination_data = generate_source_destination_data(n)

    output_file = 'data/source_destination_nodes_generated.json'
    save_results(output_file, source_destination_data)
    
    print(f"Source and Destination mappings computed computed and saved to {output_file}")
