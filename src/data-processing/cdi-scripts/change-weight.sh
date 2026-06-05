#!/bin/bash
# Update the CDI weights in cdi_project_settings.conf.
#
# The CDI now uses the NDMC indices ESI / EVI2 / SPI / SM (ESI replaced LST and
# EVI2 replaced NDVI). This script also deletes any stale `lst`/`ndvi` weight
# keys left over from the old pipeline — those would otherwise be summed by
# STEP_0301 and push the total past 1.0.

# Check jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq to run this script."
    exit 1
fi

# Display usage information and exit.
usage() {
    echo "Usage: $0 [--esi_weight=<value>] [--evi2_weight=<value>] [--spi_weight=<value>] [--sm_weight=<value>]"
    echo "Example: $0 --esi_weight=0.3 --evi2_weight=0.3 --spi_weight=0.3 --sm_weight=0.1"
    exit 1
}

# Validate argument names
for arg in "$@"; do
    case $arg in
    --esi_weight=*) ;;
    --evi2_weight=*) ;;
    --spi_weight=*) ;;
    --sm_weight=*) ;;
    *)
        echo "Invalid argument: $arg"
        usage
        ;;
    esac
done

# Initialize variables (defaults match cdi_project_settings.conf)
ESI_WEIGHT=0.3
EVI2_WEIGHT=0.3
SPI_WEIGHT=0.3
SM_WEIGHT=0.1

# Parse command line arguments
for arg in "$@"; do
    case $arg in
    --esi_weight=*)
        ESI_WEIGHT="${arg#*=}"
        ;;
    --evi2_weight=*)
        EVI2_WEIGHT="${arg#*=}"
        ;;
    --spi_weight=*)
        SPI_WEIGHT="${arg#*=}"
        ;;
    --sm_weight=*)
        SM_WEIGHT="${arg#*=}"
        ;;
    *)
        usage
        ;;
    esac
done

# Check if all weights are provided
if [ -z "$ESI_WEIGHT" ] || [ -z "$EVI2_WEIGHT" ] || [ -z "$SPI_WEIGHT" ] || [ -z "$SM_WEIGHT" ]; then
    usage
fi

# Warn if the weights do not sum to 1.0 (STEP_0301 requires a total of 1.0,
# checked with a 1e-6 tolerance). awk handles the floating-point comparison.
if ! awk -v e="$ESI_WEIGHT" -v v="$EVI2_WEIGHT" -v s="$SPI_WEIGHT" -v m="$SM_WEIGHT" \
    'BEGIN { t = e + v + s + m; exit (t > 0.999999 && t < 1.000001) ? 0 : 1 }'; then
    total=$(awk -v e="$ESI_WEIGHT" -v v="$EVI2_WEIGHT" -v s="$SPI_WEIGHT" -v m="$SM_WEIGHT" 'BEGIN { print e + v + s + m }')
    echo "WARNING: weights sum to ${total}, not 1.0 — STEP_0301 will reject this configuration."
fi

# Path to the config file
BASE_PATH=$(dirname "$0")
CONFIG_FILE="$BASE_PATH/cdi_project_settings.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Update the weights with jq. Delete any stale lst/ndvi keys first so they can
# never be re-introduced or left behind, then set the four current indices.
jq --arg esi "$ESI_WEIGHT" \
    --arg evi2 "$EVI2_WEIGHT" \
    --arg spi "$SPI_WEIGHT" \
    --arg sm "$SM_WEIGHT" \
    'del(.cdi_parameters.weights.lst, .cdi_parameters.weights.ndvi)
     | .cdi_parameters.weights.esi = ($esi | tonumber)
     | .cdi_parameters.weights.evi2 = ($evi2 | tonumber)
     | .cdi_parameters.weights.spi = ($spi | tonumber)
     | .cdi_parameters.weights.sm = ($sm | tonumber)' \
    "$CONFIG_FILE" | jq . --indent 4 >tmp.$$.json && mv tmp.$$.json "$CONFIG_FILE"
if [ $? -ne 0 ]; then
    echo "Failed to update the config file."
    rm -f tmp.$$.json
    exit 1
fi

echo "Weights updated successfully in $CONFIG_FILE:"
echo "ESI Weight:  $ESI_WEIGHT"
echo "EVI2 Weight: $EVI2_WEIGHT"
echo "SPI Weight:  $SPI_WEIGHT"
echo "SM Weight:   $SM_WEIGHT"
echo "Updated config file:"
cat "$CONFIG_FILE"

# Notes:
# - Requires jq:  sudo apt-get install jq   (Linux)  /  brew install jq  (macOS)
# - chmod +x change-weight.sh, then e.g.:
#   ./change-weight.sh --esi_weight=0.3 --evi2_weight=0.3 --spi_weight=0.4 --sm_weight=0.0
# - Weights must sum to 1.0 (a warning is printed otherwise).
