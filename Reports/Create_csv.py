import glob
import os
import json
import csv

def process_sarif_files(directory_path, output_csv_path):
    """
    Process SARIF files in the specified directory and compile results into a CSV file.

    Args:
        directory_path (str): Path to the directory containing SARIF files.
        output_csv_path (str): Path to the output CSV file.
    """
    # Initialize the CSV file with headers
    fieldnames = [
        'uri', 'startLine', 'endLine', 'id', 'name', 'text'
    ]
    with open(output_csv_path, mode='w', newline='', encoding='utf-8') as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()

        # Process each SARIF file in the directory
        for filename in glob.glob(f'{directory_path}/*/*.sarif'):
            filepath = os.path.join(directory_path, filename)

            with open(filepath, 'r', encoding='utf-8') as sarif_file:
                data = json.load(sarif_file)

                # Extract rules for mapping IDs to names
                rules = {}
                if 'runs' in data and len(data['runs']) > 0:
                    tool = data['runs'][0].get('tool', {})
                    driver = tool.get('driver', {})
                    rule_list = driver.get('rules', [])
                    for rule in rule_list:
                        rules[rule['id']] = rule.get('name', '')

                # Process each result entry
                if 'runs' in data and len(data['runs']) > 0:
                    results = data['runs'][0].get('results', [])
                    for result in results:
                        locations = result.get('locations', [])
                        if not locations:
                            continue

                        physical_location = locations[0].get('physicalLocation', {})
                        artifact_location = physical_location.get('artifactLocation', {})
                        region = physical_location.get('region', {})

                        uri = artifact_location.get('uri', '')
                        startLine = region.get('startLine', 0)
                        endLine = region.get('endLine', startLine)  # Default to startLine if missing

                        rule_id = result.get('ruleId', '')
                        name = rules.get(rule_id, '')
                        text = result.get('message', {}).get('text', '')

                        writer.writerow({
                            'uri': uri,
                            'startLine': startLine,
                            'endLine': endLine,
                            'id': rule_id,
                            'name': name,
                            'text': text
                        })

if __name__ == '__main__':
    # Get all directories
    for directory_path in glob.glob(f'{os.getcwd()}/*/*'):
        if os.path.isdir(directory_path):
            # Define consolidated csv path
            output_csv_path = f'{directory_path}/consolidated_report.csv'

            # Consolidate non-empty reports
            process_sarif_files(directory_path, output_csv_path)
