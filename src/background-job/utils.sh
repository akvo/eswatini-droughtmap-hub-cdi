#!/bin/bash

download_file() {
    local TARGET_DIR=$1
    local BASE_URL=$2
    local GES_FILE=$3

    wget --load-cookies ./.urs_cookies \
        --keep-session-cookies --user="${EARTHDATA_USERNAME}" \
        --content-disposition --content-disposition -r -c -nH -nd -np -A ".nc4" \
        -P "${TARGET_DIR}" "${BASE_URL}/${GES_FILE}" -O "${TARGET_DIR}/${GES_FILE}.tmp" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "Download failed: ${BASE_URL}/${GES_FILE}. Exiting."
        exit 1
    fi

    mv "${TARGET_DIR}/${GES_FILE}.tmp" "${TARGET_DIR}/${GES_FILE}"
}

remove_tmp_files() {
    local dir=$1
    for file in "${dir}"/*.tmp; do
        if [ -f "$file" ]; then
            rm "$file"
        fi
    done
}

get_num_files_in_dir() {
    local dir=$1
    find "${dir}" \( -name "FLDAS*.nc" -o -name "*.hdf" \) | wc -l
}

get_num_files_in_log() {
    local log_file=$1
    wc -l <"${log_file}"
}

# Function to validate if a string is a valid URL
is_valid_url() {
    [[ $1 =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]
}

download_missing_files() {
    local dir=$1
    local log_file=$2
    local base_url=$3
    local pattern=$4

    missing_files=()
    # Collect missing files
    while IFS= read -r f; do
        file_name=$(basename "$f")
        if [ ! -f "${dir}/${file_name}" ]; then
            missing_files+=("$f")
        fi
    done <"${log_file}"

    # Process files in batches of 10 with 30 seconds delay between batches
    for ((i = 0; i < ${#missing_files[@]}; i += 10)); do
        echo "START: Batch $((i / 10 + 1))"
        for ((j = i; j < i + 10 && j < ${#missing_files[@]}; j++)); do
            (
                file_name=$(basename "${missing_files[j]}")
                prefix_url=$(dirname "${missing_files[j]}")

                # Use base_url if prefix_url is not a valid URL
                if ! is_valid_url "${prefix_url}"; then
                    prefix_url="${base_url}"
                fi
                echo "Downloading: ${file_name} from ${prefix_url}"
                download_file "${dir}" "${prefix_url}" "${file_name}"
            ) &
        done
        wait # Wait for all background jobs in the current batch to finish
        echo "Batch $((i / 10 + 1)) complete. Waiting for 30 seconds..."
        sleep 30
    done
}

log_new_urls() {
    local BASE_URL=$1
    local GES_URL=$2
    local GES_PATTERN=$3
    local LOG_FILE=$4
    local seen_urls_file=$5

    if ! grep -q "${BASE_URL}${GES_URL}" "${seen_urls_file}"; then
        curl -s "${BASE_URL}${GES_URL}" |
            grep "${GES_PATTERN}" |
            pup |
            grep -v "href" |
            grep "${GES_PATTERN}" |
            grep -v "\.xml" |
            sed "s/\ //g" |
            sed "s|^|${BASE_URL}${GES_URL}|" \
                >>"${LOG_FILE}"

        echo "${BASE_URL}${GES_URL}" >>"${seen_urls_file}"
    fi
}

check_and_create_download_log() {
    local BASE_URL=$1
    local GES_PATTERN=$2
    local NAME=$3
    LOG_NAME="all-${NAME}_URLS.log"

    remove_tmp_files "../../input_data/${NAME}"

    URL_DIRS=$(curl -s "${BASE_URL}" |
        grep "\[DIR\]" |
        grep -v "doc" |
        grep -oP '(?<=href=")[^"]*')

    seen_urls_file="/tmp/seen_${NAME}.txt"
    if [ ! -f "${seen_urls_file}" ]; then
        touch "${seen_urls_file}"
    fi

    if [ ! -f "../../logs/${LOG_NAME}" ]; then
        # Clear the file at the beginning of the script
        >"${seen_urls_file}"

        for URLS in ${URL_DIRS}; do
            GES_URL="${URL}${URLS}"
            log_new_urls "${BASE_URL}" "${GES_URL}" "${GES_PATTERN}" "../../logs/${LOG_NAME}.tmp" "${seen_urls_file}"
        done
        mv "../../logs/${LOG_NAME}.tmp" "../../logs/${LOG_NAME}"
        sed -i '/xml/d' "../../logs/${LOG_NAME}"
    fi

    if [ -f "../../logs/${LOG_NAME}" ]; then
        LAST_URL_DIR=$(echo "$URL_DIRS" | tail -n 1)
        log_new_urls "${BASE_URL}" "${LAST_URL_DIR}" "${GES_PATTERN}" "../../logs/${LOG_NAME}" "${seen_urls_file}"

        num_files_in_log=$(get_num_files_in_log "../../logs/${LOG_NAME}")
        num_files_in_dir=$(get_num_files_in_dir "../../input_data/${NAME}")

        if [ "$num_files_in_dir" -lt "$num_files_in_log" ]; then
            download_missing_files "../../input_data/${NAME}" "../../logs/${LOG_NAME}" "${BASE_URL}" "${GES_PATTERN}"
        else
            echo "All ${NAME} files are up to date"
        fi
    fi
}
