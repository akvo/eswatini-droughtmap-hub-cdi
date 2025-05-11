#!/bin/bash

extract_and_rename_chirps() {
    local DIR=../../input_data/CHIRPS
    local num_tif=$(find "$DIR" -maxdepth 1 -type f -name "*.tif" | wc -l)
    local num_gz=$(find "$DIR" -maxdepth 1 -type f -name "*.gz" | wc -l)

    if [ "$num_tif" -eq "$num_gz" ]; then
        echo "[CHIRPS] Extraction already completed. Skipping."
        return
    fi

    # Extract all .gz files (keeping the original files)
    for gz in "$DIR"/*.gz; do
        [ -e "$gz" ] || continue
        gunzip -k "$gz"
    done

    # Rename all extracted files matching chirps-v2.0.*.tif
    for file in "$DIR"/chirps-v2.0.*.tif; do
        [ -e "$file" ] || continue
        local year=$(echo "$file" | grep -oP '\d{4}')
        local month=$(echo "$file" | grep -oP '\.\d{2}\.' | tr -d '.')
        mv "$file" "${DIR}/c${year}${month}.tif"
    done
}
