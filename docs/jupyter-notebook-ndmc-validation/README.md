# NDMC Validation Notebook

## Purpose

This Jupyter notebook is designed to be shared with NDMC team via Google Colab so that NDMC can validate our interpretation and processing of their new Regional Percentiles data before we deploy the refactored Eswatini CDI pipeline.

## Background

As agreed in the May–June 2026 email thread, the project team committed to preparing a shareable Colab notebook that:
1. Downloads data directly from the new NDMC endpoint
2. Shows how we interpret the data (scale, nodata, clipping)
3. Demonstrates the CDI computation using the new indices
4. Produces visual output for validation

## Files

- `eswatini_cdi_ndmc_validation.ipynb` — the notebook (open in Google Colab)

## How to Open in Google Colab

1. Upload `eswatini_cdi_ndmc_validation.ipynb` to Google Drive
2. Right-click → Open with → Google Colaboratory
3. Runtime → Run all
4. No credentials needed — all data is fetched directly from the public NDMC endpoint

## What NDMC Should Validate

- [ ] Filename pattern parsing is correct (`{dataset}_{YYYY}-{MM}-01.tif`)
- [ ] NoData value `-1` is correctly masked
- [ ] Value range 0–100 is correctly interpreted as percentile rank
- [ ] Our 0–100 ÷ 100 scaling to internal 0–1 is acceptable
- [ ] ESI orientation is "high percentile = low stress = wet" (same polarity as EVI2/SPI/SM)
- [ ] Eswatini clipping bounds are correct (30.675–32.825°E, 25.675–27.825°S)
- [ ] CDI weights are reasonable as a starting point (ESI 0.3, EVI2 0.3, SPI 0.3, SM 0.1)
- [ ] Output CDI maps look geographically plausible for Eswatini

## Data Source

`https://droughtcenter.unl.edu/Outgoing/Regional_Percentiles/Southern_Africa/`

No authentication required.
