# Requirements: NDMC Regional Percentiles Migration

## Functional Requirements

### FR-1: Delete NASA Earthdata authentication
- Delete `src/background-job/job_00_login.sh`
- Remove `source ./job_00_login.sh` from `job.sh`
- Remove `--load-cookies`/`--save-cookies`/`--user`/`--password` wget flags from `download_file()` in `utils.sh`
- Remove `EARTHDATA_USERNAME` and `EARTHDATA_PASSWORD` from `env.example`

### FR-2: Delete CHIRPS raw pipeline
- Delete `src/background-job/job_02_extract-n-rename-chirps.sh`
- Remove `source ./job_02_extract-n-rename-chirps.sh` from `job.sh`
- Remove `check_and_download_dataset CHIRPS` and `extract_and_rename_chirps` calls from `job.sh`
- Remove `DOWNLOAD_CHIRPS_BASE_URL` and `DOWNLOAD_CHIRPS_PATTERN` from `env.example`

### FR-3: Refactor `job_01_check-dataset.sh` with 4 new dataset functions
Replace `check_and_download_LST_dataset`, `check_and_download_NDVI_dataset`, `check_and_download_SM_dataset` with:

| Function | Dataset key | NDMC subdirectory |
|----------|-------------|-------------------|
| `check_and_download_ESI_dataset` | `ESI` | `era5_esi_1mn` |
| `check_and_download_EVI2_dataset` | `EVI2` | `evi2_1mn` |
| `check_and_download_SPI_dataset` | `SPI` | `chirps_spi_3mn` |
| `check_and_download_SM_dataset` | `SM` | `noah_soilm_1mn` |

### FR-4: Add `check_and_create_download_log_ndmc()` to `utils.sh`
New download function for the 2-level `/{dataset}/{YYYY}/` NDMC structure:
- Accepts `BASE_URL`, `DATASET`, `NAME`, `MODE` parameters
- `MODE=recent`: traverses the last 2 years only
- `MODE=all`: traverses all years (2012–2026)
- Fetches year subdirectory listing, collects `.tif` URLs matching `{dataset}_{YYYY}-{MM}-01.tif`
- Parses the **IIS-style** listing: links are `<A HREF="/absolute/path/file.tif">` (uppercase `HREF`, absolute path). Match `HREF` case-insensitively and strip to the bare filename: `grep -oiP '(?<=HREF=")[^"]*\.tif' | sed 's|.*/||'`
- Uses plain `wget` (no cookies, no auth)
- Idempotent: skips files already present in `../../input_data/{NAME}/`
- Saves URL log to `../../logs/all-{NAME}_URLS.log`

### FR-5: Add `--mode` argument to `job.sh`
```bash
MODE=${1:-recent}   # "recent" = last 2 years; "all" = full history 2012–2026
```
- Pass `MODE` to `check_and_create_download_log_ndmc()` to control year range
- Pass `--mode=$MODE` to `STEP_0000_execute_all_steps.py`

Mode effect at each layer:

| Layer | `recent` | `all` |
|-------|----------|-------|
| Bash download | last 2 calendar years from NDMC | 2012–present |
| STEP_0100 (ingest) | last 24 months from `input_data/` | all files in `input_data/` |
| STEP_0301/0302 | process whatever STEP_0100 wrote | same — no mode logic |
| STEP_0303 (export) | export **latest month only** (1 GeoTiff/dataset) | export **every month** (N GeoTiffs/dataset) |

Default argument in `STEP_0000_execute_all_steps.py` and `STEP_0303_export_ranking_data_rasters.py` is `"recent"`. The stale `"updates"` default from the old pipeline has been removed.

### FR-6: Update `env.example` with new env vars
```bash
DOWNLOAD_NDMC_BASE_URL="https://droughtcenter.unl.edu/Outgoing/Regional_Percentiles/Southern_Africa"
DOWNLOAD_ESI_DATASET="era5_esi_1mn"
DOWNLOAD_EVI2_DATASET="evi2_1mn"
DOWNLOAD_SPI_DATASET="chirps_spi_3mn"
DOWNLOAD_SM_DATASET="noah_soilm_1mn"
# (Optional) absolute path to the Python venv; defaults to ~/.myenv, falls back
# to system python3 if absent. Must be absolute ($HOME is not expanded from .env).
# PYTHON_VENV="/home/akvo-app/.myenv"
# Removed: EARTHDATA_*, DOWNLOAD_CHIRPS_*, DOWNLOAD_LST_*, DOWNLOAD_NDVI_*, DOWNLOAD_SM_BASE_URL, DOWNLOAD_SM_PATTERN
```

### FR-6b: Make the Python virtual environment configurable
The hardcoded `source ~/.myenv/bin/activate` failed on the production VM (no
`~/.myenv`, and `python` is not installed — only `python3`). Add helpers to
`utils.sh` and use them from `job_03_run_cdi.sh` and `job_04_upload_to_geonode.sh`:
- `activate_python_env` — activates `${PYTHON_VENV:-$HOME/.myenv}` only if its
  `bin/activate` exists; otherwise warns and continues with system Python.
- `python_bin` — resolves `python`, else `python3` (the VM has only `python3`).
- `deactivate_python_env` — calls `deactivate` only if it is defined.

### FR-7: Update `input_data/` directory structure
- Create: `input_data/ESI/`, `input_data/EVI2/`, `input_data/SPI/`
- Reuse: `input_data/SM/` (same name, new source)
- Remove: `input_data/CHIRPS/`, `input_data/LST/`, `input_data/NDVI/`

### FR-8: Update `cleanup_output_data()` in `utils.sh`
- Remove references to `working_data/LST` and `working_data/NDVI`
- STEP_0100 writes directly to `output_dir` — no scratch files in `working_data/`
- Keep cleanup of `output_data/*.nc` and `output_data/GeoTiffs/**/*.tif`

### FR-9: New Python script `STEP_0100_ingest_ndmc_geotiffs.py`
Replaces STEP_0101, STEP_0102, STEP_0103, STEP_0201, STEP_0202, STEP_0203.

Responsibilities:
- Read all `.tif` files from `input_data/{ESI,EVI2,SPI,SM}/` sorted by date
- Parse date from filename pattern `{dataset}_{YYYY}-{MM}-01.tif`
- Sample each raster onto the **config-generated 44×44 grid** from `config_reader.get('latitudes')` / `get('longitudes')` — **not** `rasterio.from_bounds` (which yields 43×43 and breaks STEP_0301's shape assumptions). Config cell centres align exactly with NDMC pixel centres, so index-by-coordinate (`src.index(lon, lat)`) reads the block without resampling.
- Map NDMC nodata `-1` → internal missing `-9999.0` (**before** scaling, so `-1` never becomes `-0.01`)
- **Divide valid values by 100** (NDMC range 0–100 → internal 0–1 for STEP_0301 compatibility)
- Preserve NDMC polarity (high percentile = wetter). **Do not invert any dataset** — ESI percentile is "high = low stress = wet", matching EVI2/SPI/SM. (The retired LST term was "high = dry"; see design.md.)
- Write 4 NetCDF files to `output_dir/`:
  - `STEP_0100_ESI_pct_rank_Eswatini.nc` (variable: `esi_pct_rank`)
  - `STEP_0100_EVI2_pct_rank_Eswatini.nc` (variable: `evi2_pct_rank`)
  - `STEP_0100_SPI_pct_rank_Eswatini.nc` (variable: `spi_pct_rank`)
  - `STEP_0100_SM_pct_rank_Eswatini.nc` (variable: `sm_pct_rank`)
- Time axis: days since 1900-01-01, derived from filename dates
- `--mode=recent`: process last 24 months only; `--mode=all`: full 2012–2026 history

### FR-10: Update `cdi_project_settings.conf`
Rename CDI parameter keys from `lst`/`ndvi` to `esi`/`evi2`:

```json
"cdi_parameters": {
    "names": {
        "esi":  "esi_pct_rank",
        "evi2": "evi2_pct_rank",
        "spi":  "spi_pct_rank",
        "sm":   "sm_pct_rank"
    },
    "weights": {
        "esi":  0.3,
        "evi2": 0.3,
        "spi":  0.3,
        "sm":   0.1
    }
}
```

Note: weights must sum to 1.0. Exact distribution to be validated with the national authority.

### FR-11: Update `cdi_directory_settings.conf`
Replace old raw data dir keys:

```json
"raw_data_dirs": {
    "esi_tif":  "../../input_data/ESI",
    "evi2_tif": "../../input_data/EVI2",
    "spi_tif":  "../../input_data/SPI",
    "sm_tif":   "../../input_data/SM"
}
```

Update GeoTiff output subdirs: `LST/` → `ESI/`, `NDVI/` → `EVI2/`.

### FR-12: Update `cdi_pattern_settings.conf`
Replace HDF/CHIRPS/FLDAS regex patterns with NDMC GeoTIFF pattern:

```json
"file_patterns": {
    "ndmc_tif_regex": "{dataset}_((?:19|20)\\d\\d)-(0[1-9]|1[0-2])-01\\.tif"
}
```

### FR-13: Update `STEP_0301_CDI_weighted_sum.py`
Change `__ranking_files` dict keys from `lst`/`ndvi`/`spi`/`sm` to `esi`/`evi2`/`spi`/`sm` and update filenames to `STEP_0100_*` pattern.

### FR-14: Update `STEP_0303_export_ranking_data_rasters.py`
- Line 171: `parameters = ["cdi", "lst", "ndvi", "spi", "sm"]` → `["cdi", "esi", "evi2", "spi", "sm"]`
- Update `input_files` dict with new `STEP_0100_*` filenames
- Update output directory paths: `LST/` → `ESI/`, `NDVI/` → `EVI2/`

### FR-15: Update `STEP_0000_execute_all_steps.py`
- Remove imports of STEP_0101, STEP_0102, STEP_0103, STEP_0201, STEP_0202, STEP_0203
- Add import of `STEP_0100_ingest_ndmc_geotiffs`
- Replace 6 `log_time` calls with 1 call to STEP_0100

### FR-16: Update GeoNode upload category identifiers
In `upload_to_geonode_job.py`, update `selected_categories`:

```python
selected_categories = [
    "cdi-raster-map",
    "spi-raster-map",
    "evi2-raster-map",   # was ndvi-raster-map
    "esi-raster-map",    # was lst-raster-map
]
```

And update `sort_key` category list comment. Also delete the runtime-cached
`src/background-job/geonode_category.json` once (it caches the old `lst`/`ndvi`
category ids and would otherwise override the new mapping; it regenerates on the
next upload). It is gitignored.

### FR-17: STEP_0302 must rank by true calendar month
The NDMC vegetation inputs are permanently missing some months (EVI2: Jan/Jul/Aug;
NDVI: Jul/Aug), so the CDI series has recurring gaps. STEP_0302's original
positional `index + 12` ranking assumes a gap-free series and would silently rank
the wrong months together. Rewrite STEP_0302 to group time slices by the calendar
month derived from each slice's `time` value, then percent-rank within each group.
CDI is produced only for months where all weighted inputs exist (not Jan/Jul/Aug).

### FR-18: STEP_0301 weight-total check must use a tolerance
`0.3 + 0.3 + 0.3 + 0.1` is `0.9999999999999999` in floating point. Replace the exact
`total != 1.0` check with `abs(total - 1.0) > 1e-6` so valid weight configs are
accepted.

---

## Non-Functional Requirements

### NFR-1: No credentials in pipeline
No NASA Earthdata credentials anywhere. NDMC endpoint is public HTTP — no authentication required.

### NFR-2: Idempotent downloads
Re-running `job.sh` skips files already present in `input_data/`. Partial downloads use `.tmp` extension until complete.

### NFR-3: Backward-compatible log format
Log file naming convention `all-{NAME}_URLS.log` preserved for consistency with existing monitoring.

### NFR-4: Two-mode operation
- `./src/background-job/job.sh recent` — downloads last 2 years, processes last 24 months, exports latest month only. For post-refactor validation.
- `./src/background-job/job.sh all` — downloads full history (SPI from 2023), processes everything, exports one GeoTiff per month. For VM production deployment.

### NFR-5: NetCDF intermediate required
STEP_0301, STEP_0302, STEP_0303 all operate on time-series NetCDF files. STEP_0100 must write NetCDF output; it cannot be skipped.

### NFR-6: Internal value scale is 0–1
NDMC data arrives at 0–100; divide by 100 before writing to NetCDF so STEP_0301 weighted sum math is unchanged.

### NFR-7: SSL verification remains enabled
`VERIFY = True` in all Python upload scripts. Do not disable.

---

## Files to Delete

| File | Reason |
|------|--------|
| `src/background-job/job_00_login.sh` | NASA Earthdata auth no longer needed |
| `src/background-job/job_02_extract-n-rename-chirps.sh` | CHIRPS raw download removed |
| `src/data-processing/cdi-scripts/STEP_0101_read_hdf_create_LST_anom_netcdf.py` | Replaced by STEP_0100 |
| `src/data-processing/cdi-scripts/STEP_0102_read_hdf_create_NDVI_anom_netcdf.py` | Replaced by STEP_0100 |
| `src/data-processing/cdi-scripts/STEP_0103_read_chirps_create_precip_netcdf_and_spi_netcdf.py` | Replaced by STEP_0100 |
| `src/data-processing/cdi-scripts/STEP_0201_percent_rank_LST_anom_netcdf.py` | Replaced by STEP_0100 |
| `src/data-processing/cdi-scripts/STEP_0202_percent_rank_NDVI_anom_netcdf.py` | Replaced by STEP_0100 |
| `src/data-processing/cdi-scripts/STEP_0203_percent_rank_SPI_anom.py` | Replaced by STEP_0100 |
