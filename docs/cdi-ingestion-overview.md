# CDI Ingestion — Overview

Short description of how raw NDMC data becomes CDI-ready NetCDF, done by
`STEP_0100_ingest_ndmc_geotiffs.py`.

## Where the data comes from

All four inputs (ESI, EVI2, SPI, SM) are downloaded as **pre-ranked GeoTIFFs**
from the public NDMC Regional Percentiles endpoint. No auth. The values are
already percentiles on a **0–100** scale with **-1** as nodata, so ingestion
only has to reshape and rescale them — no anomaly/ranking math at this stage.

## What ingestion does

For each dataset, for each monthly GeoTIFF (`{dataset}_YYYY-MM-01.tif`):

1. **Clip** a fixed 44×44 window over Eswatini. The config-derived grid centres
   line up exactly with NDMC pixel centres, so it's a direct window read — no
   resampling.
2. **Shape check** — fail fast if the clipped block isn't 44×44 (means the
   raster extent shifted).
3. **Mask nodata** — map NDMC `-1` to the internal missing value `-9999`
   *before* scaling.
4. **Scale** valid pixels `0–100 → 0–1` (divide by 100, round to 3 dp).
5. **Quality gate** — raise if any scaled value falls outside `[0,1]` (corrupt
   tile), and warn if a tile is >50% nodata.
6. **Write NetCDF** — one `STEP_0100_<DATASET>_pct_rank_Eswatini.nc` per
   dataset, a `time × lat × lon` cube using the same lat/lon arrays the later
   steps read, so grids match downstream.

Mode controls history depth: `recent` keeps the last 24 months, `all` ingests
everything.

## Output

```
output_data/STEP_0100_ESI_pct_rank_Eswatini.nc
output_data/STEP_0100_EVI2_pct_rank_Eswatini.nc
output_data/STEP_0100_SPI_pct_rank_Eswatini.nc
output_data/STEP_0100_SM_pct_rank_Eswatini.nc
```

These feed STEP_0301 (weighted sum) → STEP_0302 (rank) → STEP_0303 (export).

## Polarity note

Every NDMC percentile is "high = wetter / less drought" (ESI included). Nothing
is inverted during ingestion.
