# CDI Pipeline — Integration Tests

Scope: the CDI processing steps under `src/data-processing/cdi-scripts/`
(STEP_0100 → STEP_0301 → STEP_0303). Before this work they had **no automated
tests** — only the GeoNode upload had a suite.

**Status: implemented.** `__tests__/test_cdi_pipeline.py`, 5 tests, all passing.
This document records what was built and why, and what was deliberately left out.

## Why integration, not just unit

The steps hand NetCDF files to each other on disk and are wired together by
`STEP_0000_execute_all_steps.py`. The bugs that actually bit us were all
cross-step: a redundant ranking that destroyed the scale, a positional index
that silently blended the wrong months, a truncation in one step that changed
the statistical basis of another. A unit test on any single function would have
missed every one of them.

Both production defects are now covered by a test that fails against the old
code — verified by reverting each fix and watching the suite go red.

## How the fixture works

No mocking of the pipeline, no committed binaries, no network.

`ConfigParser` reads the three `.conf` files from a fixed path next to `libs/`,
but `raw_data_dirs` and `output_dir` inside `cdi_directory_settings.conf` are
**relative** (`../../input_data/...`) and resolve against the current working
directory. So the fixture:

1. builds an isolated `input_data/` + `output_data/` tree under `tmp_path`,
2. `chdir`s into `tmp_path/src/background-job` (two levels down, matching how
   `job_03_run_cdi.sh` invokes the pipeline in production),
3. writes synthetic NDMC-shaped GeoTIFFs — 0–100 scale, `-1` nodata, an
   `Affine` transform whose pixel centres align with the config grid so
   `src.index(lon, lat)` lands on the NW corner,
4. calls the real `main()` of each step in order.

The production config is therefore exercised as-is: real bounds, real 44×44
grid, real weights. Only the data location is redirected.

EVI2 is deliberately staged **without January, July or August**, matching NDMC.
That gap is what makes the CDI time axis non-contiguous, and it is the
condition the month-alignment bug needed to manifest.

## The tests

| Test | Locks in | Fails against old code? |
|---|---|---|
| `test_cdi_equals_weighted_sum_of_inputs` | export is the blend, not a rank of it | yes — STEP_0302 reintroduced |
| `test_all_inputs_wet_never_exports_zero` | the 2026-05 D4-nationwide regression | yes |
| `test_inputs_are_not_shifted_by_the_evi2_gaps` | every input contributes the month the raster is labelled with | yes — reports the drift in months |
| `test_export_is_invariant_to_how_much_history_is_staged` | analysis basis is independent of the export window | yes |
| `test_missing_data_propagates_to_the_export` | `-9999` survives to the GeoTIFF | no — see below |

The alignment test asserts **every** exported month, not a sample, and its
failure message states the drift in months — which is how the bug was
characterised in the first place.

### On the missing-data test

This one is a **lock, not a fix**. The `-9999` path was verified to work
correctly before any change was made; it was never implicated in the 2026-05
incident. It is untested in practice only because live NDMC data has no gaps
over Eswatini — every staged file has zero values ≤ -1 in the in-country
window. The test therefore injects nodata synthetically; against real inputs it
would pass vacuously.

## Running

```bash
cd src/data-processing/cdi-scripts
pytest __tests__/
```

`pytest` is now pinned in `requirements.txt`. Note it is **not** installed in
`~/.myenv` — the tests need an interpreter that has it.

## Not in scope

- **QGIS map export** (`FinalMapOutput-*.py`, `mapping/`) — heavy GUI/GDAL
  dependencies, separate effort.
- **GeoNode upload** — already covered by `upload_to_geonode/__tests__/`.
- **STEP_0100 input quality gates.** An earlier draft of this plan specified
  tests for an out-of-range check and a mostly-nodata warning. Those guards do
  not exist in the code; the plan described them aspirationally. They are worth
  adding — a raster of `5000`s or one that is 90% nodata should not pass
  silently — but the tests must follow the guards, not precede them.
- **A zonal-aggregation assertion.** The Hub reduces each raster to 59
  Inkhundla means, and that is where the incident surfaced. The boundaries live
  in `eswatini-droughtmap-hub`, so the check belongs there, alongside the
  no-variance guard.
