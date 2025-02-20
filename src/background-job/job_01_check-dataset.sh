#!/bin/bash

check_and_download_chirps_dataset() {
    remove_tmp_files "../../input_data/CHIRPS"

    # Check if all-CHIRPS.log exists
    if [ ! -f "../../logs/all-CHIRPS.log" ]; then
        touch "../../logs/all-CHIRPS.log"
    fi

    curl -s "${DOWNLOAD_CHIRPS_BASE_URL}" \
        | grep "${DOWNLOAD_CHIRPS_PATTERN}" \
        | pup \
        | grep -v "href" \
        | grep "${DOWNLOAD_CHIRPS_PATTERN}" \
        | sed "s/\ //g" > "../../logs/all-CHIRPS.log"

    if ls ../../input_data/CHIRPS/*.tif* 1> /dev/null 2>&1; then
        num_files_in_dir=$(get_num_files_in_dir "../../input_data/CHIRPS")
        num_files_in_log=$(get_num_files_in_log "../../logs/all-CHIRPS.log")

        if [ "$num_files_in_dir" -lt "$num_files_in_log" ]; then
            download_missing_files "../../input_data/CHIRPS" "../../logs/all-CHIRPS.log" "${DOWNLOAD_CHIRPS_BASE_URL}" ".tif*"
        else
            echo "All CHIRPS dataset files are up to date"
        fi
    else
        echo "Download all CHIRPS dataset"
        ./download.sh "${DOWNLOAD_CHIRPS_BASE_URL}" "${DOWNLOAD_CHIRPS_PATTERN}" "../../logs/all-CHIRPS.log" "../../input_data/CHIRPS" > /dev/null 2>&1
    fi
}

check_and_download_LST_dataset() {
    check_and_create_download_log  "${DOWNLOAD_LST_BASE_URL}" "${DOWNLOAD_LST_PATTERN}" "LST"
}

check_and_download_NDVI_dataset() {
    check_and_create_download_log  "${DOWNLOAD_NDVI_BASE_URL}" "${DOWNLOAD_NDVI_PATTERN}" "NDVI"
}

check_and_download_SM_dataset() {
    check_and_create_download_log  "${DOWNLOAD_SM_BASE_URL}" "${DOWNLOAD_SM_PATTERN}" "SM"
}
