#!/usr/bin/env bash
set -euo pipefail

# Configuration
REGION="us-west1"
BUCKET="mgmtmsa405-26s-team13-data"
JOB_NAME="LA-accident-$(date +%s)"

# Paths
SPARK="spark/test_spark.py"
RUN_OUTPUT="curated/products/${JOB_NAME}"
OUTPUT_URI="gs://${BUCKET}/${RUN_OUTPUT}/"
SPARK_URI="gs://${BUCKET}/${SPARK}"

# Load environment variables if they exist
if [ -f pipeline.env ]; then
    export $(grep -v '^#' pipeline.env | xargs)
fi

cleanup_output() {
    echo "!!!! Cleaning failed run output: ${OUTPUT_URI}"
    gcloud storage rm -r "${OUTPUT_URI}" --quiet || true
    echo "!!!! Cleanup complete."
}

echo "----------------------------------------------------"
echo "Submitting Dataproc Serverless Job: ${JOB_NAME}"
echo "Source: BigQuery Public Data"
echo "Output: ${OUTPUT_URI}"
echo "----------------------------------------------------"

# Submit the job
if gcloud dataproc batches submit pyspark "${SPARK_URI}" \
    --region="${REGION}" \
    --batch="${JOB_NAME}" \
    --properties="spark.dynamicAllocation.enabled=true,spark.dynamicAllocation.minExecutors=2,spark.dynamicAllocation.maxExecutors=8,spark.executor.memory=4g,spark.executor.cores=4,spark.driver.memory=4g"
then
    echo "#### Spark job finished successfully."
else
    STATUS=$?
    echo "!!!! Spark job failed with exit code ${STATUS}."
    cleanup_output
    exit "${STATUS}"
fi