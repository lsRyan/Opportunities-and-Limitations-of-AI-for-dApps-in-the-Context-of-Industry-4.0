import glob
import os
import json
import pandas as pd
import matplotlib.pyplot as plt

def analyze_csv(dir, threshold):
    """
    Analyzes a CSV file by filtering rows where 'startLine' > threshold,
    counts unique entries in the 'name' column, and saves results to a new CSV.

    Parameters:
    - input_file (str): Path to the input CSV file.
    - output_file (str): Path to save the output CSV file.
    - threshold (int): Threshold value for filtering 'startLine'.
    """
    # Read the input CSV file
    df = pd.read_csv(f'{dir}/consolidated_report.csv')

    # Filter rows where 'startLine' >= threshold
    filtered_df = df[df['startLine'] >= threshold]
    
    # Sort rows by 'startLine'
    sorted_and_filtered_df = filtered_df.sort_values(by=['startLine'], ascending=True)

    # Save sorted and filtered data to a new CSV file
    sorted_and_filtered_df.to_csv(f'{dir}/sorted_and_filtered_report.csv', index=False)

    # Count unique entries in the 'name' column
    name_counts = filtered_df['name'].value_counts().reset_index()

    # Create rows
    name_counts.columns = ['name', 'count']

    # Save count to a new CSV file
    name_counts.to_csv(f'{dir}/analysis.csv', index=False)


def process_files(csv_path, json_path):
    # Read CSV file
    df = pd.read_csv(csv_path)

    # Read JSON file
    with open(json_path) as f:
        vulnerability_groups = json.load(f)

    # Flatten the JSON structure to get all possible names
    all_names_in_json = []
    for group in vulnerability_groups.values():
        all_names_in_json.extend(group)

    # Find duplicates (names that appear in both CSV and JSON)
    csv_names = df['name'].tolist()
    duplicates = set(csv_names) & set(all_names_in_json)

    # Create a mapping of grouped names to their base group
    name_to_group = {}
    for group_name, names in vulnerability_groups.items():
        for name in names:
            name_to_group[name] = group_name

    # Process the CSV data
    processed_data = []
    seen_groups = set()

    for _, row in df.iterrows():
        name = row['name']
        count = row['count']

        if name in duplicates:
            # This is a duplicate, find its group and add to that group's total
            group_name = name_to_group[name]
            if group_name not in seen_groups:
                seen_groups.add(group_name)
                processed_data.append((group_name, count))
            else:
                # Find the existing entry for this group and add the count
                for i, (existing_name, existing_count) in enumerate(processed_data):
                    if existing_name == group_name:
                        processed_data[i] = (group_name, existing_count + count)
        else:
            # This is a unique name not in any group
            processed_data.append((name, count))

    # Separate truly unique names from grouped ones
    unique_names = []
    grouped_counts = []

    for name, count in processed_data:
        if name in vulnerability_groups.keys():
            grouped_counts.append(count)
        else:
            unique_names.append(name)

    # Prepare data for plotting
    x_labels = unique_names + [f"Grouped: {group}" for group in seen_groups]
    y_values = [count for _, count in processed_data]

    # Create the plot
    plt.figure(figsize=(12, 6))
    bars = plt.bar(x_labels, y_values)

    # Add value labels on top of each bar
    for bar in bars:
        height = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2., height,
                 f'{int(height)}',
                 ha='center', va='bottom')

    plt.xlabel('Unique Names / Groups')
    plt.ylabel('Count')
    plt.title('Distribution of Vulnerability Names and Groups')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.show()

    # Return some statistics
    total_unique = len(unique_names) + len(seen_groups)
    return {
        "total_unique_entries": total_unique,
        "unique_names": unique_names,
        "grouped_counts": grouped_counts,
        "processed_data": processed_data
    }

if __name__ == "__main__":
    startLine_threshold = {
    "Cartorio_F.sol": 4652,
    "Consorcio_F.sol": 1,
    "SupplyChain_F.sol": 3940,
    "VotacaoCondominio_F.sol": 5436,
    "Wallet_F.sol": 1
    }
    
    directories = glob.glob(f'{os.getcwd()}/*/*')

    for directory in directories:
        contract = os.path.basename(directory)
        threshold = startLine_threshold[contract]

        analyze_csv(directory, threshold)

    # results = process_files('analysis.csv', 'Vulnerability_groups.json')
