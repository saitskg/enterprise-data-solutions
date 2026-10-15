-- Optional scheduled dbt execution: created SUSPENDED to avoid accidental recurring spend.

USE ROLE STAYWISE_BUILDER;
CREATE OR REPLACE TASK STAYWISE_DB.ANALYTICS.DAILY_BUILD
    WAREHOUSE = STAYWISE_WH
    SCHEDULE = 'USING CRON 0 6 * * * Asia/Kolkata'
    AS
EXECUTE DBT PROJECT STAYWISE_DB.ANALYTICS.STAYWISE_DBT
    ARGS = 'build --target dev';

-- An administrator must GRANT EXECUTE TASK ON ACCOUNT TO ROLE STAYWISE_BUILDER
-- before you explicitly ALTER TASK ... RESUME. See runbook; scheduling is optional.
