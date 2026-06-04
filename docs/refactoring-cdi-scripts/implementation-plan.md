# Implementation Plan: NDMC Regional Percentiles Migration

## Overview

Ordered task list for migrating from MODIS LST/NDVI + CHIRPS + FLDAS to NDMC pre-ranked GeoTIFFs.
Work is grouped into phases. Each phase should be validated before starting the next.

---

## Phase 1: Configuration and Environment

**Goal**: Update all config files and env vars. No runtime code yet.

### 1.1 Update `env.example`
- Remove: `EARTHDATA_USERNAME`, `EARTHDATA_PASSWORD`, `DOWNLOAD_CHIRPS_BASE_URL`, `DOWNLOAD_CHIRPS_PATTERN`, `DOWNLOAD_LST_BASE_URL`, `DOWNLOAD_LST_PATTERN`, `DOWNLOAD_NDVI_BASE_URL`, `DOWNLOAD_NDVI_PATTERN`, `DOWNLOAD_SM_BASE_URL`, `DOWNLOAD_SM_PATTERN`
- Add: `DOWNLOAD_NDMC_BASE_URL`, `DOWNLOAD_ESI_DATASET`, `DOWNLOAD_EVI2_DATASET`, `DOWNLOAD_SPI_DATASET`, `DOWNLOAD_SM_DATASET`

### 1.2 Update `cdi_project_settings.conf`
- Rename `cdi_parameters.names` keys: `lst` → `esi`, `ndvi` → `evi2`
- Update variable names: `lst_anom_pct_rank` → `esi_pct_rank`, `ndvi_anom_pct_rank` → `evi2_pct_rank`, `spi_3_anom_pct_rank` → `spi_pct_rank`, `RootZone2_SM_pct_rank` → `sm_pct_rank`
- Rename `cdi_parameters.weights` keys: `lst` → `esi`, `ndvi` → `evi2`
- Update weights: `esi: 0.3, evi2: 0.3, spi: 0.3, sm: 0.1`

### 1.3 Update `cdi_directory_settings.conf`
- Replace `raw_data_dirs` entries (`lst_hdf`, `ndvi_hdf`, `chirps_tif`, `fldas_data`) with `esi_tif`, `evi2_tif`, `spi_tif`, `sm_tif`
- Update `geotiff_dir` subdirectory references: `LST` → `ESI`, `NDVI` → `EVI2`

### 1.4 Update `cdi_pattern_settings.conf`
- Remove `lst_hdf_regex`, `ndvi_hdf_regex`, `chirps_tif_regex`, `fldas_data_regex`
- Add `ndmc_tif_regex` for pattern `{dataset}_(YYYY)-(MM)-01.tif`

### 1.5 Create new `input_data/` directories
```bash
mkdir -p input_data/ESI input_data/EVI2 input_data/SPI
# input_data/SM/ already exists — keep it
```

### 1.6 Create new `output_data/GeoTiffs/` directories
```bash
mkdir -p output_data/GeoTiffs/ESI output_data/GeoTiffs/EVI2
# CDI/, SPI/, SM/ already exist
```

---

## Phase 2: Bash Pipeline

**Goal**: Replace download jobs, remove auth, add mode flag.

### 2.1 Add `check_and_create_download_log_ndmc()` to `utils.sh`
New function — see [design.md](design.md) for logic:
- Parameters: `BASE_URL DATASET NAME MODE`
- Traverses `{BASE}/{DATASET}/{YYYY}/` structure
- `MODE=recent`: last 2 years; `MODE=all`: 2012–2026
- Calls existing `download_missing_files()` for missing files
- No wget auth flags

### 2.2 Update `download_file()` in `utils.sh`
Remove `--load-cookies ./.urs_cookies`, `--keep-session-cookies`, `--user`, `--password` flags from the `wget` call.

### 2.3 Update `cleanup_output_data()` in `utils.sh`
Remove:
```bash
find ../../src/data-processing/cdi-scripts/working_data/LST -type f -name "*.nc" -delete
find ../../src/data-processing/cdi-scripts/working_data/NDVI -type f -name "*.nc" -delete
find ../../src/data-processing/cdi-scripts/working_data/SPI -type f -name "*.nc" -delete
```
These scratch dirs are no longer used by STEP_0100.

### 2.4 Rewrite `job_01_check-dataset.sh`
Replace all 3 existing functions with 4 new functions:
```bash
check_and_download_ESI_dataset()   # calls check_and_create_download_log_ndmc ... ESI $MODE
check_and_download_EVI2_dataset()  # calls check_and_create_download_log_ndmc ... EVI2 $MODE
check_and_download_SPI_dataset()   # calls check_and_create_download_log_ndmc ... SPI $MODE
check_and_download_SM_dataset()    # calls check_and_create_download_log_ndmc ... SM $MODE
```

### 2.5 Update `job.sh`
- Add `MODE=${1:-recent}` at top
- Remove `source ./job_00_login.sh`
- Remove `source ./job_02_extract-n-rename-chirps.sh`
- Remove `check_and_download_dataset ... CHIRPS` call
- Remove `extract_and_rename_chirps` call
- Replace weight-based conditional block: rename `weight_lst`/`weight_ndvi` → `weight_esi`/`weight_evi2`; add `weight_spi` and `weight_sm` checks for new functions
- Pass `$MODE` to `check_and_create_download_log_ndmc` calls
- Pass `--mode=$MODE` to CDI script in `job_03_run_cdi.sh`

### 2.6 Update `job_03_run_cdi.sh`
Accept and forward `$MODE`:
```bash
run_cdi_scripts() {
    local MODE=${1:-recent}
    source ~/.myenv/bin/activate
    python -u ../data-processing/cdi-scripts/STEP_0000_execute_all_steps.py --mode=$MODE
    ...
}
```

### 2.7 Delete files
```bash
rm src/background-job/job_00_login.sh
rm src/background-job/job_02_extract-n-rename-chirps.sh
```

---

## Phase 3: Python CDI Pipeline

**Goal**: New ingest script, update orchestrator and downstream steps.

### 3.1 Write `STEP_0100_ingest_ndmc_geotiffs.py`
New file in `src/data-processing/cdi-scripts/`.

Core logic per dataset:
```python
1. Build the target grid from config_reader.get('latitudes') / get('longitudes')
   → 44 latitudes × 44 longitudes (inclusive 0.05° grid). DO NOT use rasterio.from_bounds
     (it yields 43×43 and would break STEP_0301 shape assumptions).
2. List all .tif files in input_data/{DATASET}/
3. Parse date from filename: dataset_YYYY-MM-01.tif
4. Filter by mode (recent=last 24 months, all=full history)
5. For each file:
   a. Open with rasterio
   b. Map the 44×44 config grid corners to NDMC pixel indices via src.index(lon, lat)
      (config centres align exactly with NDMC pixel centres — no resampling needed)
   c. Read the 44×44 window; assert shape == (44, 44)
   d. Mask nodata (-1) → -9999.0  (BEFORE scaling, so -1 never becomes -0.01)
   e. Divide valid values by 100 (0–100 → 0–1)
6. Write all time steps to NetCDF using existing netcdf_functions.initialize_dataset()
   passing the SAME config latitudes/longitudes used by STEP_0301/0303.
```

Output NetCDF schema:
- Dimensions: `time` (n months), `latitude` (44), `longitude` (44)
- Variable: `{key}_pct_rank` (float32, missing=-9999.0)
- Time: days since 1900-01-01 as float, computed as `(date(Y,M,1) - date(1900,1,1)).days`
  — must be byte-identical across all 4 datasets for STEP_0301's `set.intersection` of common dates to work

### 3.2 Update `STEP_0301_CDI_weighted_sum.py`
In `__init__`, update `__ranking_files` dict:
```python
self.__ranking_files = {
    "esi":  os.path.join(self.__output_dir, "STEP_0100_ESI_pct_rank_{}.nc".format(self.__region)),
    "evi2": os.path.join(self.__output_dir, "STEP_0100_EVI2_pct_rank_{}.nc".format(self.__region)),
    "spi":  os.path.join(self.__output_dir, "STEP_0100_SPI_pct_rank_{}.nc".format(self.__region)),
    "sm":   os.path.join(self.__output_dir, "STEP_0100_SM_pct_rank_{}.nc".format(self.__region)),
}
```

### 3.3 Update `STEP_0303_export_ranking_data_rasters.py`
- Change `parameters` list (line 171): `["cdi", "lst", "ndvi", "spi", "sm"]` → `["cdi", "esi", "evi2", "spi", "sm"]`
- Update `input_files` dict: new `STEP_0100_*` filenames, keys `esi`/`evi2`
- Update working dir lookups: `LST` → `ESI`, `NDVI` → `EVI2`
- Fix stale `default="updates"` in `ArgumentParser` → `default="recent"` (the old string was left over from the pre-NDMC pipeline and would confuse manual invocation)
- Mode behaviour is unchanged: `mode == 'all'` exports every time slice; any other value (including `"recent"`) exports only the latest CDI month (1 GeoTiff per dataset)

### 3.4 Update `STEP_0000_execute_all_steps.py`
- Remove 6 imports: step_0101–0103, step_0201–0203
- Add: `from STEP_0100_ingest_ndmc_geotiffs import main as step_0100`
- In `main()`, replace 6 `log_time` calls with: `log_time("Step 0100", step_0100, args)`
- Fix stale `default="updates"` in `ArgumentParser` → `default="recent"`

### 3.4b Rewrite STEP_0302 to rank by calendar month (FR-17)
Replace the `for index in range(0, 12)` + `index + 12` positional logic with a
`__group_by_calendar_month()` helper that maps each time index to its real calendar
month (via `date(1900,1,1) + timedelta(days=int(t))`), then percent-rank within each
group. Required because the NDMC vegetation inputs have permanent monthly gaps.

### 3.4c Fix STEP_0301 weight-total check (FR-18)
Change `if total_weight != 1.0` to `if abs(total_weight - 1.0) > 1e-6` — the new
four-way weights do not sum to exactly 1.0 in floating point.

### 3.5 Delete old Python scripts
```bash
rm src/data-processing/cdi-scripts/STEP_0101_read_hdf_create_LST_anom_netcdf.py
rm src/data-processing/cdi-scripts/STEP_0102_read_hdf_create_NDVI_anom_netcdf.py
rm src/data-processing/cdi-scripts/STEP_0103_read_chirps_create_precip_netcdf_and_spi_netcdf.py
rm src/data-processing/cdi-scripts/STEP_0201_percent_rank_LST_anom_netcdf.py
rm src/data-processing/cdi-scripts/STEP_0202_percent_rank_NDVI_anom_netcdf.py
rm src/data-processing/cdi-scripts/STEP_0203_percent_rank_SPI_anom.py
```

---

## Phase 4: GeoNode Upload

**Goal**: Update category identifiers for renamed datasets.

### 4.1 Update `upload_to_geonode_job.py`
In `get_categories()`, update `selected_categories`:
```python
selected_categories = [
    "cdi-raster-map",
    "spi-raster-map",
    "evi2-raster-map",  # was ndvi-raster-map
    "esi-raster-map",   # was lst-raster-map
]
```

### 4.2 Delete the stale category cache
Remove `src/background-job/geonode_category.json` once — it caches the old
`lst`/`ndvi` category ids and would override the new mapping. It is gitignored and
regenerates on the next upload.

### 4.3 Verify GeoNode categories exist
Before the first production upload, confirm that `esi-raster-map`, `evi2-raster-map`,
and `sm-raster-map` categories exist on the GeoNode instance. Create them if not.

---

## Phase 5: Documentation and Cleanup

### 5.1 Update `CLAUDE.md`
- Update pipeline flow diagram to reflect new structure
- Update dataset names and directory listing
- Update CDI weights table
- Remove references to NASA Earthdata auth

### 5.2 Update `README.md` (root)
- Update prerequisites section (remove NASA Earthdata credential requirement)
- Update environment variables table
- Update dataset descriptions

### 5.3 Update `logs/` gitignore
Ensure new log files (`all-ESI_URLS.log`, `all-EVI2_URLS.log`, `all-SPI_URLS.log`, `all-SM_URLS.log`) follow existing gitignore pattern.

---

## Validation Steps

### After Phase 1–2 (bash validation)
```bash
# Test download of recent data only
./src/background-job/job.sh recent
# Verify files appear in input_data/{ESI,EVI2,SPI,SM}/
ls input_data/ESI/ input_data/EVI2/ input_data/SPI/ input_data/SM/
```

### After Phase 3 (Python validation)
```bash
source ~/.myenv/bin/activate
cd src/data-processing/cdi-scripts

# Run recent mode only (last 24 months)
python -u STEP_0000_execute_all_steps.py --mode=recent

# Verify NetCDF files are created
ls ../../output_data/STEP_0100_*.nc

# Check NetCDF contents (values should be 0-1, not 0-100; grid must be time×44×44)
python -c "
from netCDF4 import Dataset
import numpy as np
ds = Dataset('../../output_data/STEP_0100_ESI_pct_rank_Eswatini.nc')
data = np.array(ds.variables['esi_pct_rank'])
valid = data[data != -9999.0]
print('ESI min:', valid.min(), 'max:', valid.max(), 'shape:', data.shape)
assert data.shape[1:] == (44, 44), 'grid must be 44x44 to match STEP_0301/0303'
ds.close()
"

# Verify GeoTiff output
# --mode=recent → STEP_0303 exports only the latest CDI month (1 file per dataset)
ls ../../output_data/GeoTiffs/CDI/
ls ../../output_data/GeoTiffs/ESI/

# --mode=all → STEP_0303 exports every month (N files per dataset)
python -u STEP_0000_execute_all_steps.py --mode=all
ls ../../output_data/GeoTiffs/CDI/ | wc -l   # should match number of common CDI months
```

### After Phase 4 (upload validation)
```bash
# Test with limit=1 to avoid bulk upload
UPLOAD_RECENT_LIMIT=1 python -u upload_to_geonode/upload_to_geonode_job.py
# Check GeoNode UI that file appeared under correct category
```

### Full run (production)
```bash
# Full history — use on VM only, takes significant time
./src/background-job/job.sh all
```

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| NDMC data gaps (missing months in some years) | Medium | Medium | STEP_0100 handles missing files gracefully; STEP_0301 finds common dates across all inputs |
| EVI2 starts February 2026 (not January) | Confirmed | Low | STEP_0301 takes intersection of common dates — January 2026 CDI will simply not include EVI2 |
| GeoNode categories `esi-raster-map`/`evi2-raster-map` don't exist yet | High | High | Verify and create in GeoNode admin before first upload (Phase 4.2) |
| NDMC value range changes in future (currently 0–100) | Low | High | Document the /100 scaling in STEP_0100 clearly; add assertion on first file read |
| STEP_0100 writes wrong grid shape (43×43 vs 44×44) | Medium | High | Build grid from `config_reader.get('latitudes'/'longitudes')`; assert read window == (44, 44); never use `from_bounds` |
| ESI polarity differs from retired LST term | Confirmed | Medium | ESI percentile is "high = wet" (same as EVI2/SPI/SM); do NOT invert. Old LST term was "high = dry". Confirm ESI orientation with NDMC via validation notebook |
| CDI weight change needs the national authority sign-off | Confirmed | Medium | Ship with esi=0.3, evi2=0.3, spi=0.3, sm=0.1 (matches the validation notebook). Flag for the national authority confirmation before production; weights are config-only so adjustable without code change |
