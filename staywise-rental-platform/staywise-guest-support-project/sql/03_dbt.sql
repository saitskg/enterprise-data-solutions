-- WHERE: SQL file in the StayWise Snowsight workspace, after uploading the dbt files to DBT_STAGE.
-- Preserve models/, models/staging/, data/, and tests/ paths from the runbook.
-- No external dbt packages are required for this project.

USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;

-- Snowflake reads dbt_project.yml and dbt_projects_profiles.yml at the stage root.
-- This version supports the nested generic-test arguments used in schema.yml.
CREATE DBT PROJECT IF NOT EXISTS STAYWISE_DB.ANALYTICS.STAYWISE_DBT
    FROM '@STAYWISE_DB.RAW.DBT_STAGE'
    DBT_VERSION = '1.11.11'
    DEFAULT_TARGET = 'dev';

-- build runs the policy seed, dependency-ordered models, and all dbt tests.
EXECUTE DBT PROJECT STAYWISE_DB.ANALYTICS.STAYWISE_DBT
    ARGS = 'build --target dev';

-- For source changes, use the version-aware update steps in RUNBOOK.md.
