import rasterio
import numpy as np
import geopandas as gpd
import matplotlib.pyplot as plt
import rioxarray as rxr
from rasterstats import zonal_stats

file_path = "../../sample_data/"
input_file = f"{file_path}/eswatini_sample_CDI.tif"
output_percentile_file = f"{file_path}/eswatini_percentile_50.tif"
nodata_value = -9999
percentile = 50
geojson_file = f"{file_path}/eswatini.geojson"

# Read the raster data
with rasterio.open(input_file) as src:
    # Read all bands into a 3D array (bands, rows, columns)
    raster_stack = src.read()
    # Get raster metadata
    profile = src.profile

# Mask NoData values
mask = raster_stack == nodata_value

# Calculate the percentile for each pixel (ignoring NoData values)
percentile_array = np.percentile(
    np.where(mask, np.nan, raster_stack),  # Replace NoData with NaN
    percentile,
    axis=0,
    overwrite_input=False
)
# Update metadata for the output file
profile.update(dtype=rasterio.float32, count=1, nodata=np.nan)

# Save the resulting percentile raster
with rasterio.open(output_percentile_file, "w", **profile) as dst:
    dst.write(percentile_array.astype(rasterio.float32), 1)

print(f"Percentile raster saved as {output_percentile_file}")
fig, ax = plt.subplots(1, 1)
fig.set_size_inches(12, 10)
rds = rxr.open_rasterio(output_percentile_file)
band = rds.sel(band=1)
band.plot.imshow(ax=ax, cmap='Greys_r')
ax.set_title('esWatini percentile')
# plt.show()

# Calculate zonal statistics
stats = zonal_stats(
    geojson_file,          # GeoJSON or GeoDataFrame
    output_percentile_file,           # Input raster file
    stats=["median"],      # Statistics to calculate (e.g., 'median')
    nodata=np.nan,         # Ignore NoData values in the raster
    geojson_out=True       # Include GeoJSON data in the output
)

# Convert the result to a GeoDataFrame
stats_gdf = gpd.GeoDataFrame.from_features(stats)

# Display the resulting GeoDataFrame with the calculated 'median' field
# print(stats_gdf[["geometry", "median"]])

# Load Raster
with rasterio.open(input_file) as src:
    print("Raster CRS:", src.crs)
# Ensure CRS is set before saving
stats_gdf.geometry.set_crs(src.crs, inplace=True)
# Display the resulting GeoDataFrame with the calculated 'median' field
# stats_gdf[["geometry", "median"]]

# Save to a new GeoJSON file
geojson_data = f"{file_path}/eswatini_with_median.geojson"
stats_gdf.to_file(geojson_data, driver="GeoJSON")

print(f"Output saved to {geojson_data}")
