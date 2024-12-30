#!/bin/bash

login_and_download_cookies() {
    # Remove .urs_cookies and MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 files if they exist and are older than 1 day
    find . -name ".urs_cookies" -o -name "MERRA2_100.tavgM_2d_slv_Nx.198101.nc4" -mtime +1 -exec rm {} \;

    # Check if .urs_cookies and MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 exist and are created today
    if [ -f ./.urs_cookies ] && [ -f MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 ] && [ $(find ./.urs_cookies -mtime -1) ] && [ $(find MERRA2_100.tavgM_2d_slv_Nx.198101.nc4 -mtime -1) ]; then
        echo "Files are up to date. Skipping login and download."
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

