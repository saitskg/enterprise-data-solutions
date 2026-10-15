-- WHERE: SQL file in the StayWise Snowsight workspace after dbt and document processing.
-- Each row is an explicit pass/fail result; investigate every FALSE before deployment.

USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;

-- Expected row counts prove the supplied corpus was loaded at the right grain.
SELECT
    'listing_count' AS check_name,
    COUNT(*) = 30 AS passed
FROM STAYWISE_DB.ANALYTICS.DIM_LISTING

UNION ALL

SELECT
    'guest_count',
    COUNT(*) = 150
FROM STAYWISE_DB.ANALYTICS.DIM_GUEST

UNION ALL

SELECT
    'booking_count',
    COUNT(*) = 500
FROM STAYWISE_DB.ANALYTICS.FCT_BOOKING

UNION ALL

SELECT
    'calendar_count',
    COUNT(*) = 5400
FROM STAYWISE_DB.ANALYTICS.MART_LISTING_DAY

UNION ALL

SELECT
    'policy_count',
    COUNT(*) = 30
FROM STAYWISE_DB.ANALYTICS.POLICY_RULES

UNION ALL

SELECT
    'documents_with_chunks',
    COUNT(DISTINCT doc_id) = 31
FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_CHUNKS;

-- A reservation must not multiply when joined to dimensions and policy metadata.
SELECT
    'booking_context_grain' AS check_name,
    COUNT(*) = 500
        AND COUNT(DISTINCT booking_id) = 500 AS passed
FROM STAYWISE_DB.ANALYTICS.MART_BOOKING_CONTEXT;

-- Every rule used for pricing needs document evidence for that same rule version.
SELECT
    'policy_document_coverage' AS check_name,
    COUNT(*) = 0 AS passed
FROM STAYWISE_DB.ANALYTICS.POLICY_RULES r
WHERE NOT EXISTS (
    SELECT 1
    FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_CHUNKS c
    WHERE c.doc_id = r.source_document_id
        AND c.rule_set_id = r.rule_set_id
);

-- The source calendar covers every night in the published date interval.
SELECT
    MIN(stay_date) AS first_night,
    MAX(stay_date) AS last_night,
    COUNT(DISTINCT stay_date) AS distinct_nights
FROM STAYWISE_DB.ANALYTICS.MART_LISTING_DAY;
