USE ROLE ACCOUNTADMIN;

-- =====================================================
-- 1. WAREHOUSE
-- =====================================================
CREATE OR REPLACE WAREHOUSE FINAL_PROJ
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE WAREHOUSE FINAL_PROJ;

-- =====================================================
-- 2. DATABASE + SCHEMAS
-- =====================================================
CREATE DATABASE IF NOT EXISTS FINAL_PROJ;
USE DATABASE FINAL_PROJ;

CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS FINAL;

-- =====================================================
-- 3. FILE FORMATS
-- =====================================================
CREATE OR REPLACE FILE FORMAT csv_ff
  TYPE = 'CSV'
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER = 1;

CREATE OR REPLACE FILE FORMAT parquet_ff
  TYPE = 'PARQUET';

-- =====================================================
-- 4. STORAGE INTEGRATION + STAGE
-- =====================================================
CREATE OR REPLACE STORAGE INTEGRATION gcs_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://mgmtmsa405-26s-team13-data/processed/');

DESC STORAGE INTEGRATION gcs_int;

CREATE OR REPLACE STAGE FINAL_PROJ.STAGING.gcs_stage
  URL = 'gcs://mgmtmsa405-26s-team13-data/processed/'
  STORAGE_INTEGRATION = gcs_int
  FILE_FORMAT = parquet_ff;

LIST @FINAL_PROJ.STAGING.gcs_stage;

-- =====================================================
-- 5. BUILD TABLES IN STAGING
-- =====================================================
USE SCHEMA STAGING;

-- -----------------------------------------------------
-- processed_accident
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.processed_accident__build (
    ID                   VARCHAR,
    Severity             INTEGER,
    Start_Time           TIMESTAMP,
    End_Time             TIMESTAMP,
    Start_Lat            FLOAT,
    Start_Lng            FLOAT,
    Sunrise_Sunset       VARCHAR,
    Street               VARCHAR,
    City                 VARCHAR,
    County               VARCHAR,
    Start_Date           DATE,
    Start_HH             TIME,
    End_Date             DATE,
    End_HH               TIME
);

COPY INTO STAGING.processed_accident__build
FROM @FINAL_PROJ.STAGING.gcs_stage/processed_accident/
PATTERN = '.*part-.*\.parquet'
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- -----------------------------------------------------
-- processed_weather
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.processed_weather__build (
    STATION                   VARCHAR,
    "NAME"                    VARCHAR,
    LATITUDE                  FLOAT,
    LONGITUDE                 FLOAT,
    ELEVATION                 FLOAT,
    "DATE"                    DATE,
    PRCP                      FLOAT,
    WT01                      FLOAT,
    WT02                      FLOAT,
    WT08                      FLOAT,
    Precipitation_Level       VARCHAR,
    low_visibility            INTEGER
);

COPY INTO STAGING.processed_weather__build
FROM @FINAL_PROJ.STAGING.gcs_stage/processed_weather/
PATTERN = '.*part-.*\.parquet'
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- -----------------------------------------------------
-- weather_dedup (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.weather_dedup__build AS
SELECT
    STATION,
    "NAME",
    LATITUDE,
    LONGITUDE,
    ELEVATION,
    "DATE",
    PRCP,
    WT01,
    WT02,
    WT08,
    Precipitation_Level,
    low_visibility
FROM STAGING.processed_weather__build
WHERE LATITUDE IS NOT NULL
  AND LONGITUDE IS NOT NULL
  AND "DATE" IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY STATION, "DATE"
    ORDER BY STATION
) = 1;

-- -----------------------------------------------------
-- accident_candidates (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_candidates__build AS
SELECT
    a.ID,
    a.Severity,
    a.Start_Time,
    a.End_Time,
    a.Start_Lat,
    a.Start_Lng,
    a.Sunrise_Sunset,
    a.Street,
    a.City,
    a.County,
    a.Start_Date,
    a.Start_HH,
    a.End_Date,
    a.End_HH,

    w.STATION AS matched_station,
    w."NAME" AS station_name,
    w.LATITUDE AS station_latitude,
    w.LONGITUDE AS station_longitude,
    w.ELEVATION,
    w."DATE" AS weather_date,
    w.PRCP,
    w.WT01,
    w.WT02,
    w.WT08,
    w.Precipitation_Level,
    w.low_visibility,

    6371 * 2 * ASIN(
        SQRT(
            POWER(SIN(RADIANS(w.LATITUDE - a.Start_Lat) / 2), 2) +
            COS(RADIANS(a.Start_Lat)) *
            COS(RADIANS(w.LATITUDE)) *
            POWER(SIN(RADIANS(w.LONGITUDE - a.Start_Lng) / 2), 2)
        )
    ) AS distance_km
FROM STAGING.processed_accident__build a
JOIN STAGING.weather_dedup__build w
  ON a.Start_Date = w."DATE"
WHERE a.Start_Lat IS NOT NULL
  AND a.Start_Lng IS NOT NULL
  AND a.Start_Date IS NOT NULL;

-- -----------------------------------------------------
-- best_match (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.best_match__build AS
SELECT *
FROM STAGING.accident_candidates__build
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ID
    ORDER BY distance_km ASC
) = 1;

-- -----------------------------------------------------
-- accident_weather_joined
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_weather_joined__build AS
SELECT
    ID,
    Severity,
    Start_Time,
    End_Time,
    Start_Lat,
    Start_Lng,
    Sunrise_Sunset,
    Street,
    City,
    County,
    Start_Date,
    Start_HH,
    End_Date,
    End_HH,
    matched_station,
    station_name,
    station_latitude,
    station_longitude,
    ELEVATION,
    weather_date,
    PRCP,
    WT01,
    WT02,
    WT08,
    Precipitation_Level,
    low_visibility,
    distance_km
FROM STAGING.best_match__build;

-- -----------------------------------------------------
-- accident_weather_filtered
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_weather_filtered__build AS
SELECT *
FROM STAGING.accident_weather_joined__build
WHERE distance_km <= 15;

-- -----------------------------------------------------
-- accident_flags (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_flags__build AS
SELECT
    Start_Date,
    Severity,
    YEAR(Start_Date) AS accident_year,
    MONTH(Start_Date) AS accident_month_num,
    MONTHNAME(Start_Date) AS accident_month,
    CASE
        WHEN low_visibility = 1 AND PRCP > 0 THEN 'Dual Hazard'
        WHEN low_visibility = 1 THEN 'Fog, Smoke, Haze'
        WHEN PRCP > 0 THEN 'Rain'
        ELSE 'Clear'
    END AS visibility_flag
FROM STAGING.accident_weather_filtered__build;

-- -----------------------------------------------------
-- accident_rollup (former rollup query)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_rollup__build AS
SELECT
    accident_year,
    accident_month_num,
    accident_month,
    visibility_flag,
    COUNT(*) AS accident_count,
    COUNT_IF(severity >= 3) AS high_severity_count,
    ROUND(100 * COUNT_IF(severity >= 3) / NULLIF(COUNT(*), 0), 2) AS pct_high_severity
FROM STAGING.accident_flags__build
GROUP BY ROLLUP (accident_year, accident_month_num, accident_month, visibility_flag);

-- -----------------------------------------------------
-- daily_stats (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.daily_stats__build AS
SELECT
    "DATE",
    AVG(PRCP) AS AVG_DAILY_PRCP,
    SUM(low_visibility) AS STATIONS_REPORTING_FOG,
    COUNT(STATION) AS TOTAL_STATIONS
FROM STAGING.processed_weather__build
GROUP BY 1;

-- -----------------------------------------------------
-- la_weather_daily_baseline
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.la_weather_daily_baseline__build AS
SELECT
    "DATE",
    AVG_DAILY_PRCP,
    CASE
        WHEN (STATIONS_REPORTING_FOG * 1.0 / TOTAL_STATIONS) > 0.5 THEN 1
        ELSE 0
    END AS COUNTY_LOW_VIS_FLAG
FROM STAGING.daily_stats__build;

-- -----------------------------------------------------
-- weather_conditions (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.weather_conditions__build AS
SELECT
    "DATE",
    YEAR("DATE") AS weather_year,
    MONTH("DATE") AS weather_month_num,
    MONTHNAME("DATE") AS weather_month,
    CASE
        WHEN AVG_DAILY_PRCP > 0 AND COUNTY_LOW_VIS_FLAG = 1 THEN 'Dual Hazard'
        WHEN COUNTY_LOW_VIS_FLAG = 1 THEN 'Fog, Smoke, Haze'
        WHEN AVG_DAILY_PRCP > 0 THEN 'Rain'
        ELSE 'Clear'
    END AS county_low_vis_flag
FROM STAGING.la_weather_daily_baseline__build;

-- -----------------------------------------------------
-- weather_rollup (former rollup query)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.weather_rollup__build AS
SELECT
    weather_year,
    weather_month_num,
    weather_month,
    county_low_vis_flag,
    COUNT(*) AS weather_count
FROM STAGING.weather_conditions__build
GROUP BY ROLLUP (weather_year, weather_month_num, weather_month, county_low_vis_flag);

-- -----------------------------------------------------
-- accident_rain_flags (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_rain_flags__build AS
SELECT
    Start_Date,
    Severity,
    YEAR(Start_Date) AS accident_year,
    MONTH(Start_Date) AS accident_month_num,
    MONTHNAME(Start_Date) AS accident_month,
    precipitation_level
FROM STAGING.accident_weather_filtered__build;

-- -----------------------------------------------------
-- rain_accident_rollup (former rollup query)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.rain_accident_rollup__build AS
SELECT
    accident_year,
    accident_month_num,
    accident_month,
    precipitation_level,
    COUNT(*) AS accident_count,
    COUNT_IF(severity >= 3) AS high_severity_count,
    ROUND(100 * COUNT_IF(severity >= 3) / NULLIF(COUNT(*), 0), 2) AS pct_high_severity
FROM STAGING.accident_rain_flags__build
GROUP BY ROLLUP (accident_year, accident_month_num, accident_month, precipitation_level);

-- -----------------------------------------------------
-- rain_conditions (former CTE)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.rain_conditions__build AS
SELECT
    "DATE",
    YEAR("DATE") AS weather_year,
    MONTH("DATE") AS weather_month_num,
    MONTHNAME("DATE") AS weather_month,
    CASE
        WHEN AVG_DAILY_PRCP < 0.00000001 THEN 'No Rain'
        WHEN AVG_DAILY_PRCP <= 0.5 THEN 'Light Rain'
        WHEN AVG_DAILY_PRCP <= 1 THEN 'Moderate Rain'
        ELSE 'Heavy Rain'
    END AS rain_intensity_baseline
FROM STAGING.la_weather_daily_baseline__build;

-- -----------------------------------------------------
-- rain_weather_rollup (former rollup query)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.rain_weather_rollup__build AS
SELECT
    weather_year,
    weather_month_num,
    weather_month,
    rain_intensity_baseline,
    COUNT(*) AS weather_count
FROM STAGING.rain_conditions__build
GROUP BY ROLLUP (weather_year, weather_month_num, weather_month, rain_intensity_baseline);

-- -----------------------------------------------------
-- accident_weather (selected columns for visualizations)
-- -----------------------------------------------------
CREATE OR REPLACE TABLE STAGING.accident_weather_simple__build AS
SELECT
    ID,
    Severity,
    Start_Time,
    YEAR(Start_Time) AS accident_year,
    MONTH(Start_Time) AS accident_month_num,
    Start_Lng,
    Start_Lat,
    SUNRISE_SUNSET,
    precipitation_level,
    low_visibility
FROM STAGING.accident_weather_filtered__build;


-- =====================================================
-- 6. ATOMIC PUBLISH TO FINAL USING SWAP
-- Publish only final-serving tables and rollups.
-- Keep former CTE/intermediate tables in STAGING.
-- =====================================================
USE SCHEMA FINAL;

CREATE TABLE IF NOT EXISTS FINAL.processed_accident LIKE STAGING.processed_accident__build;
ALTER TABLE STAGING.processed_accident__build SWAP WITH FINAL.processed_accident;
DROP TABLE IF EXISTS STAGING.processed_accident__build;

CREATE TABLE IF NOT EXISTS FINAL.processed_weather LIKE STAGING.processed_weather__build;
ALTER TABLE STAGING.processed_weather__build SWAP WITH FINAL.processed_weather;
DROP TABLE IF EXISTS STAGING.processed_weather__build;

CREATE TABLE IF NOT EXISTS FINAL.accident_weather_joined LIKE STAGING.accident_weather_joined__build;
ALTER TABLE STAGING.accident_weather_joined__build SWAP WITH FINAL.accident_weather_joined;
DROP TABLE IF EXISTS STAGING.accident_weather_joined__build;

CREATE TABLE IF NOT EXISTS FINAL.accident_weather_filtered LIKE STAGING.accident_weather_filtered__build;
ALTER TABLE STAGING.accident_weather_filtered__build SWAP WITH FINAL.accident_weather_filtered;
DROP TABLE IF EXISTS STAGING.accident_weather_filtered__build;

CREATE TABLE IF NOT EXISTS FINAL.la_weather_daily_baseline LIKE STAGING.la_weather_daily_baseline__build;
ALTER TABLE STAGING.la_weather_daily_baseline__build SWAP WITH FINAL.la_weather_daily_baseline;
DROP TABLE IF EXISTS STAGING.la_weather_daily_baseline__build;

CREATE TABLE IF NOT EXISTS FINAL.accident_rollup LIKE STAGING.accident_rollup__build;
ALTER TABLE STAGING.accident_rollup__build SWAP WITH FINAL.accident_rollup;
DROP TABLE IF EXISTS STAGING.accident_rollup__build;

CREATE TABLE IF NOT EXISTS FINAL.weather_rollup LIKE STAGING.weather_rollup__build;
ALTER TABLE STAGING.weather_rollup__build SWAP WITH FINAL.weather_rollup;
DROP TABLE IF EXISTS STAGING.weather_rollup__build;

CREATE TABLE IF NOT EXISTS FINAL.rain_accident_rollup LIKE STAGING.rain_accident_rollup__build;
ALTER TABLE STAGING.rain_accident_rollup__build SWAP WITH FINAL.rain_accident_rollup;
DROP TABLE IF EXISTS STAGING.rain_accident_rollup__build;

CREATE TABLE IF NOT EXISTS FINAL.rain_weather_rollup LIKE STAGING.rain_weather_rollup__build;
ALTER TABLE STAGING.rain_weather_rollup__build SWAP WITH FINAL.rain_weather_rollup;
DROP TABLE IF EXISTS STAGING.rain_weather_rollup__build;

CREATE TABLE IF NOT EXISTS FINAL.accident_weather_simple LIKE STAGING.accident_weather_simple__build;
ALTER TABLE STAGING.accident_weather_simple__build SWAP WITH FINAL.accident_weather_simple;
DROP TABLE IF EXISTS STAGING.accident_weather_simple__build;

-- =====================================================
-- 7. OPTIONAL CHECKS / QUERY OUTPUTS
-- =====================================================
SELECT * FROM FINAL.la_weather_daily_baseline
LIMIT 20;

SELECT *
FROM FINAL.accident_rollup
ORDER BY accident_year DESC, accident_month_num ASC;

SELECT *
FROM FINAL.weather_rollup
ORDER BY weather_year DESC, weather_month_num ASC;

SELECT *
FROM FINAL.rain_accident_rollup
ORDER BY accident_year DESC, accident_month_num ASC;

SELECT *
FROM FINAL.rain_weather_rollup
ORDER BY weather_year DESC, weather_month_num ASC;

SELECT * 
FROM FINAL.accident_weather_simple
ORDER BY accident_year DESC, accident_month_num ASC;







