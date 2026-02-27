import glob
import os
import json

def check_sarif_results(directory):
    """
    Iterates through all SARIF files in the specified directory and checks if the 'results' list is empty.
    Prints the file path for each SARIF file with an empty 'results' list.

    Args:
        directory (str): The path to the directory containing SARIF files.
    """
    # Iterate over all files in the directory
    for filename in os.listdir(directory):
        if filename.endswith('.sarif'):
            filepath = os.path.join(directory, filename)

            try:
                with open(filepath, 'r') as file:
                    data = json.load(file)

                    # Check if 'results' list is empty
                    if not data.get('runs', [{}])[0].get('results', []):
                        print(f"Moving empty results in: {filepath}")
                        
                        # Get report directory and tool name
                        current_report_path = os.path.dirname(filepath)
                        report_tool = os.path.basename(current_report_path)

                        # Cefining new directory
                        EMPTY_dir = f'{os.path.dirname(current_report_path)}/EMPTY'

                        # Create directory for empty reports
                        if not os.path.exists(EMPTY_dir):
                            os.makedirs(EMPTY_dir)

                        # Moving empty reports
                        os.rename(current_report_path, f'{EMPTY_dir}/{report_tool}')

            except (json.JSONDecodeError, IndexError) as e:
                print(f"Error processing file {filepath}: {e}")

# Example usage
if __name__ == "__main__":
    directories = glob.glob(f'{os.getcwd()}/*/*')  # Replace with your directory path
    for directory in directories:
        print(f'\nIn directoy: {directory}')
        reports = glob.glob(f'{directory}/*')
        for report in reports:
                check_sarif_results(report)
