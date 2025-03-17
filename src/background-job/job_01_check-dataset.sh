#!/bin/bash

check_and_download_chirps_dataset() {
    printf "\n===Check and download CHIRPS dataset===\n\n"
    remove_tmp_files "../../input_data/CHIRPS"

    # Check if all-CHIRPS.log exists
    if [ ! -f "../../logs/all-CHIRPS.log" ]; then
        touch "../../logs/all-CHIRPS.log"
    fi

    LOG_IS_EMPTY=$(cat "../../logs/all-CHIRPS.log" | wc -l)

    # If the log file is empty or the last line is 2 previous months
    # based on this pattern chirps-v2.0.{year}.{month}.tif.gz
    # then update the log file
    echo "Downloading list of available CHIRPS data and saving to log"
    if [ "$LOG_IS_EMPTY" -eq 0 ] || [ "$(tail -n 1 "../../logs/all-CHIRPS.log" | cut -d '.' -f 3)" -lt "$(date -d "2 months ago" "+%Y")" ]; then
        curl -s "${DOWNLOAD_CHIRPS_BASE_URL}" \
            | grep "${DOWNLOAD_CHIRPS_PATTERN}" \
            | pup \
            | grep -v "href" \
            | grep "${DOWNLOAD_CHIRPS_PATTERN}" \
            | sed "s/\ //g" > "../../logs/all-CHIRPS.log"
    fi

    if ls ../../input_data/CHIRPS/*.tif* 1> /dev/null 2>&1; then
        num_files_in_dir=$(get_num_files_in_dir "../../input_data/CHIRPS")
        num_files_in_log=$(get_num_files_in_log "../../logs/all-CHIRPS.log")

        echo "Comparing existing downloading data in CHIRPS directory to list saved to log"
        echo "Number of files in CHIRPS directory: ${num_files_in_dir}"
        echo "Number of files in all-CHIRPS.log log file: ${num_files_in_log}"

        if [ "$num_files_in_dir" -lt "$num_files_in_log" ]; then
            download_missing_files "../../input_data/CHIRPS" "../../logs/all-CHIRPS.log" "${DOWNLOAD_CHIRPS_BASE_URL}" ".tif*"
        else
            echo "CHIRPS log data matches the download directory."
        fi
    else
        echo "Download all CHIRPS dataset"
        ./download.sh "${DOWNLOAD_CHIRPS_BASE_URL}" "${DOWNLOAD_CHIRPS_PATTERN}" "../../logs/all-CHIRPS.log" "../../input_data/CHIRPS" > /dev/null 2>&1
    fi
}

check_and_download_LST_dataset() {
    printf "\n===Check and download LST dataset===\n\n"
    check_and_create_download_log  "${DOWNLOAD_LST_BASE_URL}" "${DOWNLOAD_LST_PATTERN}" "LST"
}

check_and_download_NDVI_dataset() {
    printf "\n===Check and download NDVI dataset===\n\n"
    check_and_create_download_log  "${DOWNLOAD_NDVI_BASE_URL}" "${DOWNLOAD_NDVI_PATTERN}" "NDVI"
}

check_and_download_SM_dataset() {
    printf "\n===Check and download SM dataset===\n\n"
    check_and_create_download_log  "${DOWNLOAD_SM_BASE_URL}" "${DOWNLOAD_SM_PATTERN}" "SM"
}
