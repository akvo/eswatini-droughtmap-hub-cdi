import os
import time
from upload_to_geonode_job import get_categories
from upload_to_geonode_job import tracking_upload_progress
from upload_to_geonode_job import upload_to_geonode

geonode_url = os.getenv("GEONODE_URL")
username = os.getenv("GEONODE_USERNAME")
password = os.getenv("GEONODE_PASSWORD")
dataset_path = "../../output_data/GeoTiffs/CDI"
dataset_type = ".tif"


def get_dataset_between(start, end):
    dataset_files = []
    # Check if the dataset path exists
    if not os.path.exists(dataset_path):
        print("Dataset path does not exist.")
        return dataset_files
    for root, dirs, files in os.walk(dataset_path):
        for file in files:
            if file.endswith(dataset_type):
                # Extract the date part from the filename
                date_part = file.split('_')[-1].replace('.tif', '')
                if start <= date_part <= end:
                    dataset_files.append(os.path.join(root, file))
    return dataset_files


def process_batch(batch, categories):
    """Process a batch of dataset files."""
    for dataset_file in batch:
        try:
            basename = os.path.basename(dataset_file)
            date_part = basename.split('_')[-1].replace('.tif', '')
            # convert date part to datetime object: 202201 -> 2022-01-01
            date_created = f"{date_part[:4]}-{date_part[4:6]}-01"

            print(f"Uploading {date_created} to GeoNode...")
            execution_id = upload_to_geonode(dataset_file)
            taxonomy = dataset_file.split('/')[-2]
            tracking_upload_progress(
                execution_id=execution_id,
                taxonomy=taxonomy.lower(),
                categories=categories,
                date_created=date_created
            )
        except Exception as e:
            print(f"Error uploading {dataset_file}: {e}")
            continue


def main():
    BATCH_SIZE = 5
    BATCH_DELAY_SECONDS = 60

    # Get all CDI files without date range restriction
    dataset_files = []
    if not os.path.exists(dataset_path):
        print("Dataset path does not exist.")
        return
    for root, _, files in os.walk(dataset_path):
        for file in files:
            if file.endswith(dataset_type):
                dataset_files.append(os.path.join(root, file))

    try:
        categories = get_categories(f"{geonode_url}api/categories/")

        total_files = len(dataset_files)
        total_batches = (total_files + BATCH_SIZE - 1) // BATCH_SIZE

        for i in range(0, total_files, BATCH_SIZE):
            batch_num = (i // BATCH_SIZE) + 1
            batch = dataset_files[i:i + BATCH_SIZE]

            print(f"\n=== Processing batch {batch_num}/{total_batches} ({len(batch)} files) ===")
            process_batch(batch, categories)

            # Add delay between batches (but not after the last batch)
            if i + BATCH_SIZE < total_files:
                print(f"\nWaiting {BATCH_DELAY_SECONDS} seconds before next batch...")
                time.sleep(BATCH_DELAY_SECONDS)

        print("\n=== All batches completed ===")

    except Exception as e:
        print(e)


if __name__ == "__main__":
    main()
