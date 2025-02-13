run_cdi_scripts() {
    source ~/.myenv/bin/activate
    python -u ../data-processing/cdi-scripts/STEP_0000_execute_all_steps.py
    if [[ $? -ne 0 ]]; then
        echo "CDI script execution failed!"
        exit 1
    fi
    deactivate
}
