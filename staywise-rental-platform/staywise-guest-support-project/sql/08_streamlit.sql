-- WHERE: SQL file in the StayWise Snowsight workspace, after uploading application sources.
-- APP_STAGE needs streamlit_app.py, environment.yml, app/, and
-- data/evaluation_cases.json at the paths listed in RUNBOOK.md.
-- The runbook upload matrix lists every file. Stage paths are case-sensitive.

USE ROLE STAYWISE_APP;
USE SECONDARY ROLES NONE;
USE WAREHOUSE STAYWISE_WH;

-- Pin the warehouse runtime because account defaults can change. Snowflake resolves the
-- environment.yml packages and supplies the active session inside that runtime.
-- The app's owner role restricts the permissions available to generated SQL.
CREATE OR REPLACE STREAMLIT STAYWISE_DB.APP.STAYWISE
    FROM '@STAYWISE_DB.APP.APP_STAGE'
    MAIN_FILE = 'streamlit_app.py'
    RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME'
    QUERY_WAREHOUSE = STAYWISE_WH
    TITLE = 'StayWise - Guest support';

-- Publish the copied version so the app can be opened in Snowsight.
ALTER STREAMLIT STAYWISE_DB.APP.STAYWISE ADD LIVE VERSION FROM LAST;
SHOW STREAMLITS IN SCHEMA STAYWISE_DB.APP;
