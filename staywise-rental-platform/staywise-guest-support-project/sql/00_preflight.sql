-- WHERE: SQL file in the StayWise Snowsight workspace, AFTER 00_bootstrap.sql and BEFORE data loading.
-- Run each section separately so a missing feature is caught before later work.

USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;

-- Record the account/region/runtime context in the SQL results.
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_ROLE(),
    CURRENT_VERSION();

-- All application dependencies must be present in Snowflake's package channel.
-- Expect a nonzero count for every name below. Resolve missing packages or package
-- policy restrictions with the account administrator before deploying Streamlit.
WITH required AS (
    SELECT column1 AS package_name
    FROM VALUES
        ('streamlit'),
        ('snowflake-snowpark-python'),
        ('pandas'),
        ('sqlglot'),
        ('jsonschema')
)
SELECT
    r.package_name,
    COUNT(p.version) AS available_versions
FROM required r
LEFT JOIN STAYWISE_DB.INFORMATION_SCHEMA.PACKAGES p
    ON p.package_name = r.package_name
    AND p.language = 'python'
GROUP BY r.package_name
ORDER BY r.package_name;

-- One small real LLM request proves model access, privileges, and trial allowance.
-- If this model is unavailable, choose a supported structured-output model in your
-- region and use the same name in app/settings.py and 09_smoke_checks.sql.
-- A trial/feature denial is an account prerequisite failure, not a code failure.
SELECT AI_COMPLETE(
    model => 'claude-sonnet-4-6',
    prompt => 'Return an object with status equal to ready.',
    model_parameters => {
        'temperature': 0,
        'max_tokens': 100
    },
    response_format => {
        'type': 'json',
        'schema': {
            'type': 'object',
            'properties': {
                'status': {'type': 'string'}
            },
            'required': ['status'],
            'additionalProperties': FALSE
        }
    }
) AS cortex_preflight;

-- Package terms, model permissions, and region availability are explained in
-- RUNBOOK.md. No account billing or cross-region settings are changed here.
