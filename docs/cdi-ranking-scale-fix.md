# Prompt — fix the CDI ranking scale (run in `eswatini-droughtmap-hub-cdi`)

The CDI rasters this pipeline publishes to GeoNode are on a broken scale. The
May 2026 map (`step_0303_cdi_pct_rank_eswatini_202605`, GeoNode pk 691) put all
59 Tinkhundla in **D4 Exceptional Drought** in a month when all four component
indicators were in the 60th–99th percentile (i.e. genuinely wet). Diagnosis is
already done — do not re-derive it. Implement the fix.

## Diagnosis (verified against the live GeoNode + NDMC, 2026-07-29)

`STEP_0302_percent_rank_CDI_weighted_sum.py` percent-ranks each calendar month
against the other years present in `STEP_0301_CDI_weighted_sum_Eswatini.nc`.
`StatisticOperations.rank_parameter` divides by `amax(ranked_data, axis=0) + 1`,
computed **per pixel**. So the published value is `rank / N` where N is the
number of years in the file — and N collapsed.

Denominators read directly out of the published rasters:

| Month   | pk  | Distinct grid values                     | Denominator N |
|---------|-----|------------------------------------------|---------------|
| 2000-02 | 298 | multiples of 1/26                        | 26            |
| 2024-01 | 194 | multiples of 0.04                        | 25            |
| 2025-01 | 355 | multiples of 0.04                        | 25            |
| 2026-03 | 638 | 0, .125, .25, .286, .375, .5, .75        | 8 and 7       |
| 2026-04 | 633 | 0, .25, .375, .5, .75                    | 4 and 8       |
| 2026-05 | 691 | 0, 0.5                                   | **2**         |

The 2000–2025 archive was ranked against ~25 years. Everything produced after
the NDMC refactor was ranked against 2–8 samples, and N varies *within a single
raster* because the denominator is per-pixel. The published number is therefore
not comparable between months, or even between pixels.

2026-05 is the floor case: N=2, and May 2026's weighted sum was below May 2025's
at every in-country pixel → rank 0 → value `0.0` at all 631 in-country pixels.
Downstream, the hub's `get_category()` maps `0.0 ≤ v ≤ 0.02` to D4.

Two independent causes:

1. **`STEP_0100_ingest_ndmc_geotiffs.py` truncates the ranking basis.**
   `RECENT_MONTHS = 24` (L37) and the slice at L93-94 keep only the last 24
   files in `recent` mode. 24 months == exactly 2 samples per calendar month.
   `src/background-job/job.sh` defaults `MODE=recent`, so this is what the
   monthly production run does. Ranking is a climatological operation; it must
   never be scoped by the export window.

2. **`--mode=all` cannot fix it either.** NDMC year directories under
   `https://droughtcenter.unl.edu/Outgoing/Regional_Percentiles/Southern_Africa/`:

   | dataset          | years available |
   |------------------|-----------------|
   | `era5_esi_1mn`   | 2012–2026 (15)  |
   | `evi2_1mn`       | 2012–2026 (15)  |
   | `noah_soilm_1mn` | 2012–2026 (15)  |
   | `chirps_spi_3mn` | **2023–2026 (4)** |

   `STEP_0301.get_common_dates()` intersects all four time axes, so SPI caps the
   CDI series at ~4 years per calendar month — permanently, in every mode.

**Conclusion: the cross-year re-ranking in STEP_0302 cannot produce a valid
percentile from the current inputs, and never will while SPI starts in 2023.**

## Second defect, found while fixing the first (2026-07-29)

Independent of the ranking bug, and **not** fixed by removing STEP_0302.

`STEP_0301.__get_time_range` returned a *contiguous* `range(start, end)` over
each input's time axis and indexed it positionally with `data_ranges[param][t]`.
The common dates are not contiguous: NDMC publishes no EVI2 for January, July
or August, so those months drop out of the four-way intersection while
ESI/SPI/SM still carry them. The gap-free inputs were therefore walked straight
past the gaps, drifting one month earlier for every month EVI2 was missing.

Measured on the live staged data (32 common dates, 2023-02 → 2026-05):

| Time step | Raster labelled | ESI/SPI/SM actually read |
|-----------|-----------------|--------------------------|
| t=0       | 2023-02         | 2023-02 (aligned)        |
| t=31      | 2026-05         | **2025-09**              |

An 8-month error by the end of the series, growing monotonically. Every CDI
raster ever produced under the NDMC pipeline is affected, so the backfill is
the **whole** series, not only the months on the broken rank scale.

Fixed by resolving each common date against the source's own time axis
(`__get_time_indices`). After the fix the pipeline reproduces an independent
blend of the source rasters to within 4e-4 — the rounding STEP_0100 applies at
three decimals.

`CompositeDroughtIndicator` also leaked its input NetCDF handles; harmless in
production because the process exits, but it prevents a second run in the same
process (HDF5 keeps a lock). A `close()` was added so the pipeline is testable.

## The fix (Option A — recommended, implement this)

`STEP_0100`'s own module docstring states it: the NDMC inputs are *already*
percentile-ranked (0–100, rescaled to 0–1) against NDMC's own long climatology.
`STEP_0302`'s re-ranking is a leftover from the pre-NDMC pipeline, when inputs
were raw anomalies from LST/NDVI/CHIRPS that genuinely needed ranking. It is now
redundant *and* destructive: it collapses a continuous 0–1 percentile into a
rank out of ≤4.

This is corroborated by the validation notebook already committed at
`docs/jupyter-notebook-ndmc-validation/eswatini_cdi_ndmc_validation.ipynb` — the
reference NDMC reviewed and approved on 11 Jun 2026. It runs download → clip →
scale → `compute_cdi_weighted_sum` → plot, with **no ranking step anywhere**.
The approved design and the shipped pipeline disagree, and the shipped pipeline
is the one that is wrong. Treat this as a deployment divergence rather than a
design error; see `docs/cdi-scale-fix-requirements.md` REQ-2.

`STEP_0301`'s weighted sum (`0.3·esi + 0.3·evi2 + 0.3·spi + 0.1·sm`, weights sum
to 1) is already a valid CDI: continuous on 0–1, comparable across months, and
with the **same polarity as before** (all NDMC percentiles are high = wet, so
low = dry — matching what the old 25-year rank meant). The consumer's thresholds
(`get_category` in the hub: D4 ≤0.02, D3 ≤0.05, D2 ≤0.10, D1 ≤0.20, D0 ≤0.30)
are the US Drought Monitor percentile scheme, which is designed to be applied to
exactly this kind of blended percentile. **No downstream change is required.**

Verified target output (computed from the published component rasters):

```
2026-05 blend → per-Inkhundla 0.824–0.940 → 59/59 "Wet/normal conditions"
2026-04 blend → per-Inkhundla 0.738–0.888 → 59/59 "Wet/normal conditions"
```

### Tasks

1. **`STEP_0303_export_ranking_data_rasters.py`** — export the CDI from
   `STEP_0301_CDI_weighted_sum_{region}.nc` (variable `cdi_weighted_sum`)
   instead of `STEP_0302_CDI_pct_rank_{region}.nc` (`cdi_wt_sum_pr`). The
   component exports (esi/evi2/spi/sm) already read the STEP_0100 files and stay
   as they are. Keep the output filename pattern unchanged
   (`STEP_0303_CDI_pct_rank_{region}_{YYYYMM}.tif`) so GeoNode upload, the
   hub's `find_component_resource`, and the existing archive keep working —
   or, if you rename, update `src/background-job/upload_to_geonode/` and tell
   me, because the hub matches on the GeoNode *category*, not the title.

2. **Drop `STEP_0302` from the chain** in `STEP_0000_execute_all_steps.py`.
   Delete `STEP_0302_percent_rank_CDI_weighted_sum.py` rather than leaving it
   orphaned — it is the bug, and a dormant copy invites its return. If you keep
   it for reference, make `STEP_0000` not call it and say so in the docstring.

3. **`STEP_0100_ingest_ndmc_geotiffs.py`** — remove `RECENT_MONTHS` and the
   truncation at L93-94; always ingest every staged file. `--mode` must control
   only what gets *downloaded* and *exported*, never the analysis basis. This
   is correct regardless of options A/B/C and should land either way.

4. **Lock the missing-data path with a test — it is not broken.** An earlier
   draft of this document claimed `-9999` failed to propagate and that this was
   how a no-signal pixel became an indistinguishable `0.0`. Both claims were
   wrong and have been retracted. Verified by executing the code paths directly:

   - `StatisticOperations.rank_parameter` **preserves** the mask through
     `np.add(..., out=…)`.
   - `netcdf.initialize_dataset` sets `missing_value = -9999.0` on the dataset,
     so netCDF4 writes masked entries back as `-9999` rather than the default
     fill value.
   - `-9999` therefore survives STEP_0100 → 0301 → 0302 → 0303 intact today.

   The reason no post-refactor raster carries `-9999` is that **the NDMC inputs
   have no nodata pixels over Eswatini**. Across the staged GeoTIFFs (ESI 173,
   EVI2 152, SM 173, SPI 40) the 44×44 in-country window contains zero values
   `≤ -1`; the `nodata` tag is `-1.0` throughout, matching NDMC's 3 Jun 2026
   note. The 2000–2025 archive carried `-9999` because MODIS LST/NDVI had
   cloud-masked gaps — an artifact of the retired products, not a property the
   new feed shares.

   So the requirement here is a **regression lock, not a remediation**: add the
   assertion so a future refactor cannot silently break a path that live data
   never exercises. Do not present it as contributing to the 2026-05 incident.

   Removing STEP_0302 strengthens this for free: `STEP_0301`'s explicit
   `.filled(-9999)` becomes the last writer before export, so the hub's
   `negative → "No Data"` contract is structurally guaranteed rather than
   incidental.

5. **Add the integration test** described in `docs/cdi-integration-test-plan.md`
   (synthetic GeoTIFFs, no committed binaries, `pytest`, following
   `src/background-job/upload_to_geonode/__tests__/`). Minimum assertions:
   - a month whose components are all high (wet) exports a CDI **> 0.3**
     (i.e. "normal"), never 0.0 — this is the 2026-05 regression;
   - `-9999` injected into any input propagates to `-9999` in the exported CDI
     (a lock on behaviour that already works — see task 4 — and that live NDMC
     data never exercises, so it must be tested synthetically);
   - the exported CDI equals the weighted sum of the inputs within tolerance;
   - the export is invariant to how many months are staged — ingest 2 years
     and 5 years of the same data, assert the latest month's CDI is identical.
     That last one is the property the old pipeline violated.

6. **Re-run and backfill.** `job.sh all`, then re-upload. Every CDI raster from
   2025-05 onward (GeoNode pks 619, 624, 625, 628, 630, 631, 632, 633, 638, 639,
   690, 691 — check for others) was produced on the broken scale and needs
   replacing. Flag which historical months change category.

### Validation before you push anything

- Recompute 2026-05 and confirm 59/59 land in "Wet/normal", values ~0.82–0.94.
- Recompute 2026-04 and confirm ~0.74–0.89, no D4.
- Pick the driest month available in 2023–2026 and confirm it reaches a drought
  category. If nothing in the record ever reaches D2 or below, say so — that
  is a real finding about threshold calibration, not a reason to tune numbers
  until the map looks alarming.

### One decision that needs a human, not a commit

The blend and the old 25-year rank are **different scales**. A rank is uniform
on [0,1]; a weighted mean of four percentiles clusters toward the middle, so the
same USDM thresholds will yield fewer extreme categories than the 2000–2025
archive did. That is how the real USDM blended indicator behaves and it is
defensible, but it means:

- published maps for 2000 – 2025-01 (old rank) and 2023+ (blend) are not
  strictly comparable; and
- pre-2023 months **cannot** be recomputed on the new scale, because NDMC has no
  SPI before 2023.

Do not silently accept a permanent scale discontinuity at 2023. Surface it, with
the numbers, for partner sign-off. Options if they reject it: rebuild a long SPI
locally from CHIRPS (`libs/spi_calculations.py` still exists and the old pipeline
did exactly this), which restores ~15 years and makes Option B viable.

## Options B and C — for context, do not implement without asking

- **B — keep the re-ranking, fix the history.** Compute SPI locally from CHIRPS
  back to 2012 so all four inputs span 15 years, then rank as before with a hard
  minimum sample count. Preserves uniform-rank semantics and comparability with
  the 2000–2025 archive. Materially more work, and 15 years is still thin for a
  percentile.
- **C — guard only.** Refuse to emit a rank when a calendar-month group has
  fewer than N years, writing `-9999` instead. This is a safety net, not a
  resolution: on today's data it masks every month and the pipeline publishes
  nothing. Worth adding *alongside* A or B, never instead of.

If you think A is wrong, say so before writing code and explain why — but the
brief is a working scale, not a stopped pipeline.

## Companion change in the other repo (`eswatini-droughtmap-hub`) — do NOT do it here

Tracked separately; noted so you understand the whole failure and don't design
around a guard that isn't there yet:

- `backend/api/v1/v1_jobs/job.py::generate_initial_cdi_values` — reject a raster
  whose zonal values have no variance across all 59 administrations, so a
  degenerate raster fails the job instead of publishing D4 nationwide. Fixtures
  copied from the incident: `backend/api/v1/v1_jobs/fixtures/cdi_202605_degenerate.tif`
  (pk 691, uniform) and `cdi_200002_healthy.tif` (pk 298, 26-year rank).
- `generate_initial_cdi_values_results` (job.py:456-480) only checks
  `len(initial_values)`, and on the `is_seeder` branch copies `initial_values`
  into `validated_values` and stamps `published_at` — so bad CDI data reaches
  the public map with no human review. That path needs the same guard.
- Publication 321 (2026-05) currently holds 59 rows of `value: 0.0,
  category: 5`. It must be recomputed once the CDI raster is fixed, not
  hand-edited.
