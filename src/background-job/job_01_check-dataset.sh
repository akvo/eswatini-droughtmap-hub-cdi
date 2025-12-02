#!/bin/bash

check_and_download_LST_dataset() {
    printf "\n===Check and download LST dataset===\n\n"
    check_and_download_dataset  "${DOWNLOAD_LST_BASE_URL}" "${DOWNLOAD_LST_PATTERN}" "LST"
}

check_and_download_NDVI_dataset() {
    printf "\n===Check and download NDVI dataset===\n\n"
    check_and_download_dataset  "${DOWNLOAD_NDVI_BASE_URL}" "${DOWNLOAD_NDVI_PATTERN}" "NDVI"
}

check_and_download_SM_dataset() {
    printf "\n===Check and download SM dataset===\n\n"
    check_and_create_download_log  "${DOWNLOAD_SM_BASE_URL}" "${DOWNLOAD_SM_PATTERN}" "SM"
}
