#!/bin/bash

# Get the root directory of the project
root_path="$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")"

# Load environment variables from .env file in the root directory
export $(grep -v '^#' "$root_path/.env" | xargs)

# Change to the directory of the script
cd "$(dirname "$0")"

source ./utils.sh
source ./job_00_login.sh
source ./job_01_check-dataset.sh
source ./job_02_extract-n-rename-chirps.sh
source ./job_03_run_cdi.sh
source ./job_04_upload_to_geonode.sh

# Exit if wget, pup, gunzip, and curl aren't available
for cmd in wget pup gunzip curl; do
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd could not be found, please install it to proceed."
        exit 1
    fi
done
echo "All required commands are available."

login_and_download_cookies

check_and_download_chirps_dataset
extract_and_rename_chirps

check_and_download_LST_dataset
check_and_download_NDVI_dataset
check_and_download_SM_dataset

run_cdi_scripts
upload_to_geonode
