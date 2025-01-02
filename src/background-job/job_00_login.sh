#!/bin/bash

login_and_download_cookies() {
    # Remove .urs_cookies and MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 files if they exist and are older than 1 day
    find . -name ".urs_cookies" -mtime +1 -exec rm {} \;

    # Check if .urs_cookies exists and is created today
    if [ -f ./.urs_cookies ] && [ $(find ./.urs_cookies -mtime -1) ]; then
        echo ".urs_cookies is up to date. Skipping login."
        return 0
    fi

    wget --load-cookies ./.urs_cookies \
        --save-cookies ./.urs_cookies \
        --keep-session-cookies \
        --user="${EARTHDATA_USERNAME}" \
        --password="${EARTHDATA_PASSWORD}" \
        --content-disposition \
        https://goldsmr4.gesdisc.eosdis.nasa.gov/data/MERRA2_MONTHLY/M2TMNXSLV.5.12.4/1981/MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "Login failed"
        exit 1
    fi
}

