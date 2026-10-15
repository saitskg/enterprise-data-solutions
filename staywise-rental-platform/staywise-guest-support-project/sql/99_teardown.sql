-- WHERE: open this file in the Snowsight workspace and choose Run All once.
-- DESTRUCTIVE: removes the deployed StayWise project so setup can start again.
-- Close the StayWise app and stop submitting setup/build queries before running.
-- Every operation uses a fixed project name; unrelated account objects are untouched.
-- IF EXISTS allows reruns and cleanup after an incomplete setup.

USE ROLE ACCOUNTADMIN;

-- 1. Cancel running/queued project work, including unfinished parsing queries.
-- Remove compute first so the app and scheduled task cannot start new warehouse work.
-- The remaining DROP and SHOW commands do not require a running warehouse.
ALTER WAREHOUSE IF EXISTS STAYWISE_WH ABORT ALL QUERIES;
DROP WAREHOUSE IF EXISTS STAYWISE_WH;

-- 2. CASCADE removes every schema and object inside the dedicated database:
--    APP: Streamlit app and its deployed files, APP_STAGE, REQUEST_LOG.
--    RAW: DATA_STAGE, CODE_STAGE, DBT_STAGE, CSV_FORMAT, and raw tables.
--    ANALYTICS: dbt project, seed tables, models, views, and DAILY_BUILD task.
--    KNOWLEDGE: DOC_STAGE, manifest, parsed documents, chunks, parsing procedure,
--               and STAY_SEARCH (including its serving/indexing resources).
--    AI: semantic view and availability/quote procedures.
-- Dropping internal stages also removes their uploaded CSV/PDF/code files.
-- This also covers additional objects created inside STAYWISE_DB while debugging.
-- Drop the database directly: individual child-object drops can fail when a
-- previous cleanup already removed their containing database or schema.
DROP DATABASE IF EXISTS STAYWISE_DB CASCADE;

-- 3. Remove account-level project roles after their owned objects are gone.
-- Role deletion also removes their grants and assignments to users/parent roles,
-- including Cortex access and the optional EXECUTE TASK account privilege.
DROP ROLE IF EXISTS STAYWISE_APP;
DROP ROLE IF EXISTS STAYWISE_BUILDER;

-- 4. Each result should contain ZERO rows for the named project object.
-- SHOW uses metadata and remains usable after STAYWISE_WH has been dropped.
SHOW DATABASES LIKE 'STAYWISE_DB';
SHOW WAREHOUSES LIKE 'STAYWISE_WH';
SHOW ROLES LIKE 'STAYWISE_APP';
SHOW ROLES LIKE 'STAYWISE_BUILDER';

-- Fresh setup: follow RUNBOOK.md from step 2 (00_bootstrap.sql), reusing the workspace.
-- Snowsight workspace source files are separate from deployed database objects.
-- Snowflake retains query/account history and data under its retention rules;
-- this does not prevent immediately creating a fresh STAYWISE_DB with the same name.
