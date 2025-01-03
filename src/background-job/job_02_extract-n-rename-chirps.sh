#!/bin/bash

extract_and_rename_chirps() {
    # Directory where .gz files are located (default is current directory)
    local DIR=../../input_data/CHIRPS
    local CURR_DATE=$(date +%Y%m%d)
    local CURR_TIME=$(date +%H%M%S)

    # Check the number of .tif files and .gz files
    local num_tif_files=$(find "$DIR" -type f -name "*.tif" | wc -l)
    local num_gz_files=$(find "$DIR" -type f -name "*.gz" | wc -l)

    # If the number of .tif files is equal to the number of .gz files, skip the loop
    if [ "$num_tif_files" -eq "$num_gz_files" ]; then
        echo "[CHIRPS] The number of .tif files is equal to the number of .gz files. Skipping extraction and renaming."
        return
    fi

    # Loop through all .gz files in the directory
    for gz_file in "$DIR"/*.gz; do
        # Extract the file (removing .gz extension)
        gunzip -k "$gz_file"  # Use -k to keep the .gz file intact
        # Remove the .gz file
        # rm "$gz_file"

        # Get the extracted file name (removes the .gz part)
        local extracted_file="${gz_file%.gz}"

        # Extract the date parts from the file name
        # File format: chirps-v2.0.YYYY.MM.tif
        # Extract the year and month from the filename
        local year=$(echo "$extracted_file" | grep -oP '\d{4}')  # Extract the 4-digit year
        local month=$(echo "$extracted_file" | grep -oP '\.\d{2}\.' | tr -d '.')  # Extract the month, removing dots

        # Create the new filename: cYYYYMM.tif
        local new_file_name="${DIR}/c${year}${month}.tif"

        # Rename the extracted file
        mv "$extracted_file" "$new_file_name"
    done
}
