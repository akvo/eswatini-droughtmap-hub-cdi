# Requirements — CDI scale fix, reconciled against the NDMC email thread

Output of a requirements-discovery pass over `docs/cdi-ranking-scale-fix.md` and the
NDMC correspondence — thread *"Operational Query: MODIS LST Feed Disruption and NDVI
GeoTIFF Transition"*, 23 Apr – 11 Jun 2026, held outside this repository. Every passage
relied on below is quoted inline, so this document stands alone. This is a
**requirements document, not an implementation plan.**

It does not restate the fix doc. It records where the correspondence **confirms** it,
where it **corrects** it, and what it surfaces that the fix doc does not cover.

---

## 1. Option A is not a judgement call — it is the design NDMC specified

The fix doc presents Option A as "recommended, implement this" and invites disagreement.
The email removes the ambiguity. Jeff Wisner (NDMC), 23 Apr 2026, describing Option 1
which Akvo formally accepted on 29 Apr:

> **Simpler architecture on your end: pull indices, perform a weighted sum, and export
> final images**

There is no ranking step in that sentence. And the reason STEP_0302 ever existed is
stated outright in the same email:

> The rankings are now true percentiles; **the older method had to use plain rankings
> due to the shorter histories of NDVI/LST.** […] We now use rolling windows of 40-year
> histories for each index (SPI, NDVI, etc.), rather than the older method of
> overwriting each year.

STEP_0302 is the compensation for a defect NDMC has since fixed upstream. Keeping it
re-ranks a 40-year true percentile against 2–4 samples.

Jeff then signed off on the weighted-sum output directly, 11 Jun 2026, after reviewing
Iwan's validation notebook (which ran "through to a draft CDI output"):

> The assumptions for questions 1-10 are correct, and the output looks good.

**REQ-1 (confirmed, blocking).** Drop the cross-year re-ranking. Export the CDI from
`STEP_0301_CDI_weighted_sum_{region}.nc` (`cdi_weighted_sum`). Fix-doc tasks 1–3 stand
as written.

**REQ-2 (new — resolved, and it reframes the incident).** The notebook Jeff approved is
committed in this repository at
`docs/jupyter-notebook-ndmc-validation/eswatini_cdi_ndmc_validation.ipynb`. It was
inspected: the pipeline is download → clip → scale 0–100 → 0–1 →
`compute_cdi_weighted_sum(clipped, CDI_WEIGHTS)` → plot. There is **no ranking step**,
no `argsort`, and no reference to STEP_0302 anywhere in its 20 cells.

So the validated reference and the production pipeline disagree, and production is the
one that is wrong. **This is a deployment-divergence defect, not a design error**: the
correct design was written down, reviewed by the data provider, approved, committed to
this repo — and then not carried into `src/data-processing/cdi-scripts/`, because
STEP_0302 was left in the chain from the pre-NDMC pipeline.

Two consequences:

- The incident record should say this plainly. The process gap (no check that the
  shipped pipeline matches the approved reference) is the reusable lesson; the code bug
  is not.
- The notebook is the natural oracle for the integration test in fix-doc task 5. Assert
  the pipeline's exported CDI against `compute_cdi_weighted_sum` on the same inputs,
  rather than against hand-derived expected values.

---

## 2. Supporting evidence: the `-9999` path is **not** broken

An earlier draft of fix-doc task 4 asserted that missing data fails to propagate, and
that this was "how a no-signal pixel became an indistinguishable `0.0`". Both halves
were wrong. **Fix-doc task 4 has since been corrected**; the evidence is recorded here.
Checked directly:

- `StatisticOperations.rank_parameter` **preserves** the mask through
  `np.add(..., out=…)` — verified by executing the exact code path on a masked input.
- `netcdf.initialize_dataset` sets `missing_value = -9999.0`, so netCDF4 writes masked
  entries back as `-9999`, not as the default fill. Verified with a round-trip write/read.
- So `-9999` survives STEP_0100 → 0301 → 0302 → 0303 intact today.

The real reason no post-refactor raster carries `-9999` is simpler: **the NDMC inputs
have no nodata pixels over Eswatini.** Sampled across the 538 staged GeoTIFFs
(ESI 173, EVI2 152, SM 173, SPI 40), the 44×44 in-country window contains **zero**
values `≤ -1` in every file checked. `nodata` tag is `-1.0` throughout, matching Jeff's
3 Jun note. The 2000–2025 archive carried `-9999` because MODIS LST/NDVI had
cloud-masked gaps — a QC artifact of the retired products, not a property the new feed
shares.

**REQ-3 (revised).** Keep the `-9999` regression test from fix-doc task 5, but scope it
honestly: it is a **lock**, not a fix. Nothing is currently broken; the assertion exists
so that a future refactor cannot silently break a path that live data never exercises.
Do not describe it as remediating the 2026-05 incident — it did not contribute to it.
Because live NDMC data contains no nodata pixels over Eswatini, the test must inject
`-9999` synthetically or it will pass vacuously.

Note the residual this closes anyway: with STEP_0302 gone, `STEP_0301`'s explicit
`.filled(-9999)` is the last writer before export, so the negative-value contract the
hub relies on (`negative → "No Data"`) is structurally guaranteed rather than incidental.

---

## 3. Correction: the 2023 SPI cutoff is a *publication* window, not a climatology limit

The fix doc's "One decision that needs a human" section treats SPI's 2023 start as a
hard scientific constraint, and floats rebuilding SPI locally from CHIRPS via
`libs/spi_calculations.py` as the remedy if partners reject the discontinuity.

The email undercuts both. NDMC computes **40-year rolling histories** for every index,
SPI included. The percentiles inside `chirps_spi_3mn_2023-01-01.tif` are already ranked
against 40 years. What starts in 2023 is only the **directory** — how far back Jeff
chose to export files for Southern Africa.

This changes the cost of the fix by orders of magnitude:

| Approach | Effort | Result |
|---|---|---|
| Ask Jeff to backfill `chirps_spi_3mn` to 2012 | one email | 15-year CDI series, NDMC's 40-year percentiles, no new code |
| Rebuild SPI locally from CHIRPS (fix doc's fallback) | weeks | shorter climatology than NDMC's, and reintroduces exactly the local-computation dependency Option 1 was chosen to eliminate |

**REQ-4 (new, highest leverage in this document).** Before accepting any scale
discontinuity, ask NDMC to extend the SPI export back to 2012 to match ESI/EVI2/SM.
Frame it as an export-window request, not a reprocessing request. **Do not build SPI
locally** — it is a strictly worse product and contradicts the agreed architecture.

**REQ-5 (retained).** The blend-vs-rank scale discontinuity at the archive boundary is
still real and still needs partner sign-off, independent of REQ-4. REQ-4 shrinks the
gap; it does not remove it.

---

## 3b. A second defect the fix doc did not anticipate

Found while implementing REQ-1, and **independent of the ranking bug** — it
would have survived the fix and shipped silently.

`STEP_0301.__get_time_range` indexed each input by a contiguous range rather
than by date. EVI2's missing Jan/Jul/Aug make the common-date axis
non-contiguous, so ESI/SPI/SM drifted one month earlier per gap: by the end of
the live series the raster labelled 2026-05 was blending **2025-09** ESI, SPI
and SM. Full detail and the measured drift table are in the fix doc.

**REQ-12 (new, blocking).** Resolve each common date against the source's own
time axis. Done — the pipeline now reproduces an independent blend of the
source rasters to within 4e-4.

**REQ-13 (revises fix-doc task 6).** The backfill is the **entire** series, not
only the months produced on the broken rank scale. The fix doc's list of ~12
GeoNode pks from 2025-05 onward is the scope of the *ranking* defect; the
alignment defect reaches every CDI raster the NDMC pipeline has ever produced.
Corrected series is 32 months, 2023-02 → 2026-05.

**REQ-14 (process).** This defect predates the NDMC migration in its logic but
could only manifest once an input with calendar gaps was introduced. Any
external account of the incident that attributes it to NDMC's restructuring is
wrong on this second defect — it is entirely ours, and the restructuring only
exposed it.

---

## 4. Validation questions the fix doc leaves open — pre-answered

Computed from the staged inputs using the config weights (ESI .3, EVI2 .3, SPI .3, SM .1),
44×44 in-country window, pixel-level:

| Month | min | mean | max |
|---|---|---|---|
| 2026-05 | 0.352 | **0.897** | 0.974 |
| 2026-04 | 0.264 | **0.822** | 0.938 |
| 2026-03 | 0.423 | 0.736 | 0.938 |
| 2025-11 | 0.285 | 0.595 | 0.892 |
| 2024-02 | **0.085** | 0.442 | 0.735 |

**Confirmed against the real pipeline (2026-07-29).** After REQ-1 and REQ-12,
`STEP_0000 --mode=all` reproduces every figure above to within 4e-4. The
exported 2026-05 raster carries **1,203 distinct values**; the published one
carried a single value, `0.0`. Driest months in the corrected 32-month series
are 2024-12 (pixel mean 0.437) and 2024-02 (0.442, floor 0.085).

- **2026-05 and 2026-04 confirmed.** Consistent with the fix doc's predicted
  per-Inkhundla 0.824–0.940 and 0.738–0.888 (zonal means compress the pixel range).
  No D4. The published `0.0`-everywhere raster is refuted from the source data.
- **The fix doc's threshold-calibration worry does not materialise.** It asks whether
  any month reaches D2 or below on the new scale. 2024-02 bottoms at **0.085**, which is
  D2 (`≤0.10`) at pixel level. The blend does produce drought categories.
  Re-check after zonal aggregation to 59 Tinkhundla before treating this as settled —
  averaging will lift the floor.

**REQ-6.** These are pixel-level. The acceptance criterion must be evaluated on the
**zonal** values the hub actually stores, since that is where 2026-05 produced 59 rows
of `0.0`.

---

## 5. Requirements the fix doc does not cover at all

Jeff's 23 Apr offer under Option 1 was broader than what the pipeline consumes:

> SPI **and SPEI** from both CHIRPS3 and ERA5 · ESI from **both FLDAS and ERA5** ·
> NDVI and **EVI2 with modeled backups (in case of significant satellite outages)** ·
> 100cm Soil Moisture from **both FLDAS and ERA5**

**REQ-7 (new, operationally significant).** The pipeline has **no CDI for January, July,
or August** — `evi2_1mn` has no files for those months, and `get_common_dates()`
intersects, so those months vanish entirely. That is 25% of the year with no product.
"EVI2 with modeled backups" reads like the intended answer. Ask Jeff whether the modeled
backup covers the gap months and how it is published. This is arguably a bigger
availability defect than the scale bug and it is currently undocumented as a problem.

**REQ-8 (new).** Single-source dependency. ESI and SM are each offered from two
independent sources (FLDAS and ERA5); the pipeline pulls one. No fallback exists if a
directory goes empty — which is precisely the failure that opened this thread on
23 April. Decide whether a fallback source is in scope.

**REQ-9 (new).** SPEI is offered and unused. Not necessarily wanted, but it is a
deliberate omission that should be recorded as one rather than left implicit.

**REQ-10 (new).** Weights are provisional and NDMC has committed to a calibration tool:

> I have been working on ML methods to generate a master reference CDI based on the
> North American Drought Monitor; once complete, it will be available to help tweak
> the weights.

Track this. Until it lands, do not hand-tune `cdi_project_settings.conf` weights to make
maps look right — the fix doc's warning against tuning-until-alarming applies equally in
the other direction.

**REQ-11 (new, unclosed deliverable).** Lotte asked on 9 Jun to what extent
`https://cdie.ndma.org.sz/about` should be updated. Jeff never answered. The methodology
has now changed three times over: LST→ESI, NDVI→EVI2, and (with REQ-1) rank→blend.
The public explanation is stale and the page is the platform's scientific credibility
surface. Owner unassigned.

---

## 6. Open questions requiring a human

1. **NDMC:** can `chirps_spi_3mn` be exported back to 2012? (REQ-4 — ask first, it may
   make REQ-5 mostly moot)
2. **NDMC:** what is the modeled EVI2 backup, and does it fill Jan/Jul/Aug? (REQ-7)
3. **NDMA/partners:** accept the blend-vs-rank scale discontinuity at the archive
   boundary, with the numbers in §4 attached? (REQ-5)
4. **Akvo:** who owns the `/about` rewrite? (REQ-11)
5. **Akvo:** should the fix-doc task 5 integration test assert against the approved
   notebook's `compute_cdi_weighted_sum` directly, rather than against hand-derived
   values? (REQ-2)

*Previously open, now closed:* whether the approved Colab notebook contains a re-ranking
step — it does not; see REQ-2.

---

## 7. Scope boundary

Unchanged from the fix doc: the `generate_initial_cdi_values` variance guard and
Publication 321 recomputation belong to `eswatini-droughtmap-hub`, not here. Noted so
the fix in this repo is not designed around a guard that does not yet exist.
