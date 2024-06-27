import json
import random
import math


SOURCE_DESTINATION_NODES_FILE = "data/source_destination_nodes_generated.json"
MC_SAMPLES_FILE = 'data/mc_samples.json'

# Define the percentages for importing sample sizes of MC data
MC_PERCENTAGES = [0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00]

# Load the JSON data from a file
with open(SOURCE_DESTINATION_NODES_FILE, 'r') as file:
    source_destination_nodes = json.load(file)

# Extract mc_data pairs into FULL_MC_DATA if they exist
FULL_MC_DATA = []
for node in source_destination_nodes:
    mc_data = node.get('mc_data')
    if mc_data:
        FULL_MC_DATA.append(mc_data['pairs'])
    else:
        print("Skipping: 'mc_data' field not found")

# Calculate and store samples based on percentages
MC_SAMPLES = {}
total_elements = len(FULL_MC_DATA)
for perc in MC_PERCENTAGES:
    sample_size = math.ceil(total_elements * perc)  # Calculate sample size
    samples = random.sample(FULL_MC_DATA, sample_size)  # Get random samples
    flat_samples = [element for sublist in samples for element in sublist]
    formatted_percentage = f"{int(perc * 100)}%"
    MC_SAMPLES[formatted_percentage] = flat_samples

# Save the samples to a JSON file
with open(MC_SAMPLES_FILE, 'w') as outfile:
    json.dump(MC_SAMPLES, outfile, indent=4)
