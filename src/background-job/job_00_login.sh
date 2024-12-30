#!/bin/bash

login_and_download_cookies() {
    # Remove .urs_cookies file and MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 file if they exist
    if [ -f ./.urs_cookies ]; then
        rm ./.urs_cookies
    fi
    if [ -f MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 ]; then
        rm MERRA2_100.tavgM_2d_slv_Nx.198101.nc4
    fi

    wget --load-cookies ./.urs_cookies \
        --save-cookies ./.urs_cookies \
        --keep-session-cookies \
        --user="${EARTHDATA_USERNAME}" \
        --password="${EARTHDATA_PASSWORD}" \
        --content-disposition \
        https://goldsmr4.gesdisc.eosdis.nasa.gov/data/MERRA2_MONTHLY/M2TMNXSLV.5.12.4/1981/MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 > /dev/null 2>&1

    # Check if the download was successful
    if [ $? -ne 0 ]; then
        echo "Login failed"
        exit 1
    fi
}

