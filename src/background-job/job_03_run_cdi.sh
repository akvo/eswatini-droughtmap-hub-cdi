run_cdi_scripts() {
    source ~/.myenv/bin/activate
    # Get --year_month argument if provided
    local YEAR_MONTH_ARG=""
    for arg in "$@"; do
        if [[ $arg == --year_month=* ]]; then
            YEAR_MONTH_ARG="$arg"
            break
        fi
    done
    # Get the current year and month
    local CURRENT_YEAR_MONTH
    CURRENT_YEAR_MONTH=$(date +%Y-%m)
    # Run the CDI scripts based on the year_month argument
    if [[ -n $YEAR_MONTH_ARG ]]; then
        local YEAR_MONTH_VALUE="${YEAR_MONTH_ARG#*=}"
        echo "Running CDI scripts for year_month: $YEAR_MONTH_VALUE"
        # Compare YEAR_MONTH_VALUE with CURRENT_YEAR_MONTH
        # If YEAR_MONTH_VALUE is 2 months or more in the past, run all steps
        # If YEAR_MONTH_VALUE is the current month, run only the latest step
        local YEAR_MONTH_DIFF
        YEAR_MONTH_DIFF=$(( ($(date -d "$CURRENT_YEAR_MONTH-01" +%s) - $(date -d "$YEAR_MONTH_VALUE-01" +%s)) / (30*24*3600) ))
        if [[ $YEAR_MONTH_DIFF -ge 2 ]]; then
            # Run all steps for past months
            python -u ../data-processing/cdi-scripts/STEP_0000_execute_all_steps.py --mode=all
        else
            # Run only the latest step for the current month
            python -u ../data-processing/cdi-scripts/STEP_0000_execute_all_steps.py
    if [[ $? -ne 0 ]]; then
        # Handle error
        echo "CDI script execution failed!"
        exit 1
    fi
    deactivate
}
