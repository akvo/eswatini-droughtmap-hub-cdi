#!/bin/bash

download_file() {
    local TARGET_DIR=$1
    local BASE_URL=$2
    local GES_FILE=$3

    wget --load-cookies ./.urs_cookies \
        --keep-session-cookies --user="${EARTHDATA_USERNAME}" \
        --content-disposition --content-disposition -r -c -nH -nd -np -A ".nc4" \
        -P "${TARGET_DIR}" "${BASE_URL}/${GES_FILE}" -O "${TARGET_DIR}/${GES_FILE}.tmp"

    if [ $? -ne 0 ]; then
        echo "Download failed. Exiting."
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
    local pattern=$2
    find "${dir}" -name "*${pattern}*" | wc -l
}

get_num_files_in_log() {
    local log_file=$1
    wc -l < "${log_file}"
}

download_missing_files() {
    local dir=$1
    local log_file=$2
    local base_url=$3
    local pattern=$4

    missing_files=()
    for f in $(cat "${log_file}"); do
        file_name=$(basename "$f")
        if [ ! -f "${dir}/${file_name}" ]; then
            missing_files+=("$f")
        fi
    done

    for ((i=0; i<${#missing_files[@]}; i+=10)); do
    {
        for ((j=i; j<i+10 && j<${#missing_files[@]}; j++)); do
            file_name=$(basename "${missing_files[j]}")
            prefix_url=$(dirname "${missing_files[j]}")
            if [ -z "${prefix_url}" ] || [ "${prefix_url}" = "." ]; then
                prefix_url="${base_url}"
            fi
            download_file "${dir}" "${prefix_url}" "${file_name}"
        done
        wait
        sleep 300
    } &
    done
    wait
}

check_and_create_download_log() {
    local BASE_URL=$1
    local GES_PATTERN=$2
    local NAME=$3
    LOG_NAME="all-${NAME}_URLS.log"

    remove_tmp_files "../../input_data/${NAME}"

    if [ ! -f "../../logs/${LOG_NAME}" ]; then
        URL_DIRS=$(curl -S "${BASE_URL}" \
            | grep "\[DIR\]" \
            | grep -v "doc" \
            | grep -oP '(?<=href=")[^"]*')

        for URLS in ${URL_DIRS}; do
            GES_URL="${URL}${URLS}"
            curl -s "${BASE_URL}${GES_URL}" \
                | grep "${GES_PATTERN}" \
                | pup \
                | grep -v "href" \
                | grep "${GES_PATTERN}" \
                | grep -v "\.xml" \
                | sed "s/\ //g" \
                | sed "s|^|${BASE_URL}${GES_URL}|"
        done > "../../logs/${LOG_NAME}.tmp"
        mv "../../logs/${LOG_NAME}.tmp" "../../logs/${LOG_NAME}"
        sed -i '/xml/d' "../../logs/${LOG_NAME}"
    fi

    if [ -f "../../logs/${LOG_NAME}" ]; then
        num_files_in_log=$(get_num_files_in_log "../../logs/${LOG_NAME}")
        num_files_in_dir=$(get_num_files_in_dir "../../input_data/${NAME}" "${GES_PATTERN}")

        if [ "$num_files_in_dir" -lt "$num_files_in_log" ]; then
            download_missing_files "../../input_data/${NAME}" "../../logs/${LOG_NAME}" "${BASE_URL}" "${GES_PATTERN}"
        else
            echo "All ${NAME} files are up to date"
        fi
    fi
}
