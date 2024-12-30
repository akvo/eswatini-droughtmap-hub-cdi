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

login_and_download_cookies

check_and_download_chirps_dataset
check_and_download_LST_dataset
check_and_download_NDVI_dataset
check_and_download_SM_dataset

extract_and_rename_chirps
