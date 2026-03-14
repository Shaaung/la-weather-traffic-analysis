# README
This is the README file for team13.

---

# Project Overview

This project implements a cloud-based data pipeline for analyzing traffic accident data and its relationship with weather conditions. The pipeline uses Google Cloud Platform (GCP) for data storage and distributed processing, Snowflake for data warehousing, and Tableau for visualization.

The pipeline is designed to demonstrate an end-to-end data engineering workflow that includes:

- Cloud data storage
- Distributed data processing
- Data warehousing
- Business intelligence visualization

The full workflow processes raw datasets, transforms them using PySpark, stores processed datasets in Snowflake, and produces dashboards in Tableau.

---

# Pipeline Architecture

The pipeline follows the architecture below:

```
Google Drive (Raw Data)
        ↓
Google Cloud Storage (Raw Layer)
        ↓
Dataproc Serverless (PySpark Processing)
        ↓
Google Cloud Storage (Processed Layer)
        ↓
Snowflake (Data Warehouse)
        ↓
Tableau (Visualization Dashboard)
```

---

# Pipeline Execution Flow

The entire pipeline is executed using a single Bash script.

```
pipeline.sh
     ↓
spark_gcp.py
     ↓
Processed data written to GCS
     ↓
snowflake-load.py
     ↓
Data loaded into Snowflake
     ↓
Tableau dashboard visualization
```

### pipeline.sh

This script orchestrates the entire pipeline and performs the following tasks:

1. Configures pipeline parameters
2. Submits a PySpark job to Dataproc Serverless (Executes `spark_gcp.py`)
3. Executes the Snowflake loading script (Executes `snowflake-load.py`)

### spark_gcp.py

This PySpark script performs the following:

- Data cleaning
- Date formatting
- Feature generation
- Select necessary columns
- Writing processed datasets back to GCS `gs://BUCKET/processed/`

### snowflake-load.py

This script connects to Snowflake and runs SQL commands to load processed datasets into warehouse tables.  
The script executes the SQL statements contained in **`405 new code.sql`**, which includes both:

- data loading commands that ingest processed datasets from GCS into Snowflake tables  
- SQL queries and transformations used to build the final analytical tables

---

# Data Sources

Because our team GCS bucket prevents public access, the raw datasets are provided through publicly accessible download links. The instructor can download these datasets and upload them into their own GCS bucket to reproduce the pipeline.

## Accident Dataset

* Lists out the car accidents that occurred in the United States, including date, time, location, and severity (measures impact to traffic, value 1-4, 1 least impact).
* Time frame: 2016/2/1 – 2023/3/31
* Format: csv file


Original Source:
```
https://www.kaggle.com/datasets/sobhanmoosavi/us-accidents
```

Google Drive download link:

```
https://drive.google.com/uc?id=1f0mnVjNCNrM1oZkXZmUQK4Z8eto58t-Q&export=download
```

Example download command:

```bash
wget "https://drive.google.com/uc?id=1f0mnVjNCNrM1oZkXZmUQK4Z8eto58t-Q&export=download" -O accidents.csv
```

## Weather Dataset

* Lists out the daily weather data of all the weather stations in Los Angeles County, including wind, temperature, and precipitation
* Time frame: 2016/2/1 – 2023/3/31
* Format: csv file
* Note: Due to data availability constraints, meteorological variables are observed at the daily level. We assume that the effects of severe weather persist throughout the day in which they occur and that all accident activities on that day are exposed to the same weather conditions.)


Original Source:
```
https://www.ncei.noaa.gov/cdo-web/search
```

Download link:

```
https://drive.google.com/uc?id=1f0mnVjNCNrM1oZkXZmUQK4Z8eto58t-Q&export=download
```

Example download:

```bash
wget "https://drive.google.com/uc?id=1f0mnVjNCNrM1oZkXZmUQK4Z8eto58t-Q&export=download" -O weather.csv
```

---

# Technologies Used

This project uses the following technologies:

- Google Cloud Platform
- Google Cloud Storage (GCS)
- Google Dataproc Serverless
- PySpark
- Snowflake
- Tableau

---

# Repository Structure

```
team13/
│
├── pipeline.sh
├── spark_gcp.py
├── snowflake-load.py
├── 405 new code.sql
├── pipeline.env.template
│
└── README.md
```

---

# Environment Setup

## Install Google Cloud CLI

Install the Google Cloud CLI:

```bash
sudo apt update
sudo apt install google-cloud-cli
```

Authenticate your Google Cloud account:

```bash
gcloud auth login
```

## Install Snowflake Python Connector

The Snowflake loading script requires the Snowflake Python connector.

Install it using:

```bash
pip install snowflake-connector-python
```

The pipeline reads Snowflake credentials from `pipeline.env`, which are accessed by the Python script through environment variables.

---

# Configure Google Cloud Project

Set your project ID:

```bash
export PROJECT=<YOUR_PROJECT_ID>

gcloud config set project $PROJECT
```

---

# Create a GCS Bucket

Create a new bucket that will store raw and processed datasets.

```bash
export BUCKET=my-accident-pipeline

gcloud storage buckets create gs://$BUCKET \
--location=us-west1 \
--uniform-bucket-level-access
```

---

# Upload Raw Datasets

After downloading the datasets, upload them into the bucket.

```bash
gcloud storage cp accidents.csv gs://$BUCKET/raw/
gcloud storage cp weather.csv gs://$BUCKET/weather/
```

Note: Google Cloud Storage uses object prefixes rather than real directories, so the directory structure will automatically appear when files are uploaded.

Expected bucket layout:

```
gs://BUCKET/

raw/
pipe/
processed/
```

---

# Upload Spark Pipeline Code

The pipeline expects the Spark script to exist at:

```
gs://BUCKET/pipe/spark_gcp.py
```

Upload the script:

```bash
gcloud storage cp spark_gcp.py gs://$BUCKET/pipe/
```

---

# Configure the Pipeline Script

Open `pipeline.sh` and update the bucket parameter:

```bash
BUCKET="your-bucket-name"
```

Example:

```bash
BUCKET="my-accident-pipeline"
```
All GCS paths used by the pipeline are derived from this variable.

If the script was created on Windows, remove Windows line endings:

```bash
sed -i 's/\r$//' pipeline.sh
```

Apply execution permission:

```bash
chmod +x pipeline.sh
```
---

# Snowflake Setup

This project uses Snowflake as the cloud data warehouse to load processed datasets from Google Cloud Storage (GCS), perform SQL transformations, and publish analytical tables for downstream analysis and visualization.

## Create a Snowflake account:

```
https://signup.snowflake.com/
```

## Configure Snowflake Credentials

Set the required environment variables:

```bash
export SNOWFLAKE_USER=<user>
export SNOWFLAKE_PASSWORD=<password>
export SNOWFLAKE_ACCOUNT=<account>
export SNOWFLAKE_WAREHOUSE=<warehouse>
export SNOWFLAKE_DATABASE=<database>
export SNOWFLAKE_SCHEMA=<schema>
export SNOWFLAKE_ROLE=<role>
```

---

## Create pipeline.env

The pipeline reads Snowflake credentials from a local environment file.

A template is provided:

```
pipeline.env.template
```

Create your own environment file by copying the template:

```bash
cp pipeline.env.template pipeline.env
```

Then open `pipeline.env` and fill in your Snowflake credentials:

```
SNOWFLAKE_USER=your_user
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_ACCOUNT=your_account
SNOWFLAKE_WAREHOUSE=your_warehouse
SNOWFLAKE_DATABASE=your_database
SNOWFLAKE_SCHEMA=your_schema
SNOWFLAKE_ROLE=your_role
```

The `pipeline.sh` script automatically loads these variables before executing the Snowflake loader script.

---

## Granting Snowflake Access to the GCS Bucket
To allow Snowflake to load data stored in Google Cloud Storage (GCS), a Snowflake storage integration must be created. This integration generates a Snowflake-managed GCP service account that needs permission to read the bucket.

### Step 1 — Create the Snowflake storage integration

```
CREATE OR REPLACE STORAGE INTEGRATION gcs_int
TYPE = EXTERNAL_STAGE
STORAGE_PROVIDER = 'GCS'
ENABLED = TRUE
STORAGE_ALLOWED_LOCATIONS = ('gcs://your-bucket/processed/');
```

### Step 2 — Retrieve the Snowflake GCP service account

Run:

```
DESC STORAGE INTEGRATION gcs_int;
```

Look for the field:

```
STORAGE_GCP_SERVICE_ACCOUNT
```

Example output:

```
snowflake-gcs-12345@snowflake-project.iam.gserviceaccount.com
```

### Step 3 — Grant the service account permission in GCP
In the Google Cloud Console:

1. Go to **Cloud Storage**
2. Open your **GCS bucket**
3. Click the **Permissions** tab
4. Click **Grant Access**
5. Paste the service account email from Step 2
6. Assign the role **Storage Object Viewer**

This allows Snowflake to read files in the bucket.

### Step 4 — Initialize Snowflake Objects
The required Snowflake warehouse, database, schemas, file formats, stages, tables, and analytical queries are defined in `405 new code.sql`. 

This SQL script is automatically executed by **`snowflake-load.py`** during the pipeline execution.

---

# Running the Data Pipeline

Run the pipeline:

```bash
bash pipeline.sh
```

The script will:

1. Load Snowflake credentials from `pipeline.env`
2. Submit a PySpark job to Dataproc Serverless
3. Process accident and weather datasets
4. Write processed datasets to GCS
5. Execute `snowflake-load.py`, which runs `405 new code.sql` to load and transform data in Snowflake

---

# Expected Output Structure

After the pipeline runs successfully, the bucket will contain:

```
gs://BUCKET/

raw/
  (contains raw data files)

pipe/
   spark_gcp.py

logs/

processed/
   (processed accident data)
   (processed weather data)
```

---

# Tableau Dashboard

Visualization dashboard:

```
<INSERT TABLEAU PUBLIC LINK>
```

The dashboard shows:

- accident counts, by weather types
- accident counts per day, by weather type
- accident severity distribution, by weather type
- geographic distribution for severe car accidents

---

# Reproducing the Pipeline

To reproduce the pipeline from scratch:

1. Create a new GCS bucket
2. Download datasets from Google Drive
3. Upload datasets to your bucket
4. Upload `spark_gcp.py` to `gs://BUCKET/pipe/`
5. Configure Snowflake credentials
6. Update the `BUCKET` variable in `pipeline.sh`
7. Run:

```bash
bash pipeline.sh
```

This will execute the full pipeline and reproduce the data processing workflow.
