# Eswatini Drought Map Hub - CDI Automation

This repository contains the automation scripts for generating and updating drought-related data for the **Eswatini Drought Map Hub**. The script is designed to run periodically (ideally on a monthly basis) to ensure the data remains up-to-date.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Setup Instructions](#setup-instructions)
4. [Running the Script](#running-the-script)
5. [Environment Variables](#environment-variables)
6. [Automation](#automation)
7. [Contributing](#contributing)
8. [License](#license)

---

## Overview

The Eswatini CDI Automation script (`job.sh`) downloads satellite/climate data, runs the Combined Drought Indicator (CDI) algorithm over Eswatini, and uploads the resulting GeoTiff rasters to a GeoNode instance. It is designed to run monthly via cron on a Linux server.

The CDI integrates four drought indices into a single percentile-ranked map. All inputs come from the [NDMC Regional Percentiles endpoint](https://droughtcenter.unl.edu/Outgoing/Regional_Percentiles/Southern_Africa/) as pre-ranked GeoTIFFs — **no authentication required**:

| Index | Source | Replaces |
|-------|--------|----------|
| ESI — Evaporative Stress Index | `era5_esi_1mn` | MODIS LST |
| EVI2 — Enhanced Vegetation Index | `evi2_1mn` | MODIS NDVI |
| SPI 3-month | `chirps_spi_3mn` | Locally computed SPI |
| NOAH Soil Moisture | `noah_soilm_1mn` | FLDAS SM |

For more information about the CDI methodology, visit the [NDMC website](https://drought.unl.edu/).

---

## Prerequisites

Before running the script, ensure the following prerequisites are met:

1. **Operating System**: Linux-based system.
2. **System tools**: `wget`, `pup`, `curl`
   ```bash
   sudo apt-get install wget curl
   # pup (HTML parser): https://github.com/ericchiang/pup
   ```
3. **Python virtual environment** at `~/.myenv` with packages from `src/data-processing/cdi-scripts/requirements.txt`:
   ```bash
   python3 -m venv ~/.myenv
   source ~/.myenv/bin/activate
   pip install -r src/data-processing/cdi-scripts/requirements.txt
   ```
4. **Environment configuration**: A `.env` file must be created with the necessary environment variables (see [Environment Variables](#environment-variables)).

---

## Setup Instructions

1. **Clone the Repository**:
 ```bash
 git clone https://github.com/akvo/eswatini-droughtmap-hub-cdi.git
 cd eswatini-droughtmap-hub-cdi
 ```

2. **Set Up Environment Variables**:
 - Copy the example environment file to `.env`:
   ```bash
   cp env.example .env
   ```
 - Open the `.env` file and populate it with the required values:
   ```bash
   nano .env
   ```

3. **Install system dependencies**:
   ```bash
   sudo apt-get update && sudo apt-get install wget curl
   # Install pup from https://github.com/ericchiang/pup/releases
   ```

4. **Set up Python virtual environment**:
   ```bash
   python3 -m venv ~/.myenv
   source ~/.myenv/bin/activate
   pip install -r src/data-processing/cdi-scripts/requirements.txt
   deactivate
   ```

---

## Running the Script

To execute the script manually, run the following command:

```bash
./src/background-job/job.sh recent   # last 2 years (default) — for validation
./src/background-job/job.sh all       # full history (SPI from 2023) — for production
```

| Mode | Downloads | CDI output |
|------|-----------|------------|
| `recent` (default) | Last 2 years from NDMC | Latest month only (1 GeoTiff per dataset) |
| `all` | Full history (SPI from 2023) | Every available month |

> **Note**: CDI is never produced for January, July, or August — the NDMC vegetation index (EVI2) is permanently missing those months. This is expected behaviour.

### Upload Behavior

By default, the script uploads **all** GeoTiff files to GeoNode. To upload only the most recent files per category:

```bash
# Upload only 5 most recent files per category (CDI, SPI, ESI, EVI2, SM)
UPLOAD_RECENT_LIMIT=5 ./src/background-job/job.sh recent
```

You can also set `UPLOAD_RECENT_LIMIT` in your `.env` file to make it persistent.

### Notes:
- Ensure the `.env` file is properly configured before running the script.
- The script should ideally be executed on a monthly basis to keep the data updated.

---
## Environment Variables

The script relies on the following environment variables, which must be defined in the `.env` file. These variables configure the data sources, authentication, and target systems for the automation process.

| Variable Name               | Description                                                                                   | Example Value                                |
|-----------------------------|-----------------------------------------------------------------------------------------------|----------------------------------------------|
| `DOWNLOAD_NDMC_BASE_URL`    | Base URL of the NDMC Regional Percentiles endpoint (public, no auth). | `https://droughtcenter.unl.edu/Outgoing/Regional_Percentiles/Southern_Africa` |
| `DOWNLOAD_ESI_DATASET`      | NDMC subdirectory for Evaporative Stress Index (replaces MODIS LST). | `era5_esi_1mn` |
| `DOWNLOAD_EVI2_DATASET`     | NDMC subdirectory for 2-band Enhanced Vegetation Index (replaces MODIS NDVI). | `evi2_1mn` |
| `DOWNLOAD_SPI_DATASET`      | NDMC subdirectory for 3-month SPI (precipitation). | `chirps_spi_3mn` |
| `DOWNLOAD_SM_DATASET`       | NDMC subdirectory for NOAH soil moisture (replaces FLDAS). | `noah_soilm_1mn` |
| `GEONODE_URL`               | Base URL of the GeoNode instance where processed data will be uploaded.                      | `https://yourgeonodeinstance.com`            |
| `GEONODE_USERNAME`          | Username or email for authenticating with the GeoNode instance.                              | `yourgeonodeusernameoremail`                 |
| `GEONODE_PASSWORD`          | Password for authenticating with the GeoNode instance.                                       | `yourgeonodepassword`                        |
| `UPLOAD_RECENT_LIMIT`       | (Optional) Number of most recent files to upload per category. If not set, uploads all files. | `5` (uploads 5 most recent), or omit for all |

---

### Notes:
- The NDMC endpoint is public HTTP — **no NASA Earthdata credentials are needed**.
- Replace placeholder values (e.g., `yourgeonodeinstance`) with actual values.
- Dataset subdirectory names map to the NDMC Regional Percentiles tree; change them only if NDMC reorganizes the endpoint.

---

## Automation

To automate the execution of the script, you can use a cron job. Follow these steps:

1. Open the crontab editor:
 ```bash
 crontab -e
 ```

2. Add the following line to schedule the script to run monthly:
 ```bash
 0 0 1 * * /path/to/repository/src/background-job/job.sh recent >> /path/to/logfile.log 2>&1
 ```
 - Uses `recent` mode: downloads and processes only the last 2 years, uploads the latest month. Efficient for monthly incremental runs.
 - For the **initial production load** (full history), run once manually with `job.sh all` before enabling the cron.
 - Replace `/path/to/repository` with the actual path to your repository.
 - Logs will be appended to `/path/to/logfile.log`.

3. Save and exit the crontab editor.

---

## Contributing

We welcome contributions to improve this project! To contribute:

1. Fork the repository.
2. Create a new branch for your changes:
 ```bash
 git checkout -b feature/your-feature-name
 ```
3. Commit your changes and push them to your fork:
 ```bash
 git commit -m "Add your descriptive commit message"
 git push origin feature/your-feature-name
 ```
4. Submit a pull request to the `main` branch of this repository.

---

## License

This project is licensed under the [MIT License](LICENSE). See the `LICENSE` file for details.

---

If you have any questions or need further assistance, feel free to open an issue in this repository.
