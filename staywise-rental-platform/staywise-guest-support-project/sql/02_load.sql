-- WHERE: SQL file in the StayWise Snowsight workspace, after uploading the five source CSVs listed in RUNBOOK.md to DATA_STAGE.
-- Use Ingestion > Add Data > Load files into a Stage; leave the stage path empty.
-- Snowflake tracks loaded filenames, so rerunning does not duplicate unchanged files.

USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;

-- ABORT_STATEMENT prevents partially loaded files from looking successful.
-- COPY uses the declared column order, so keep the supplied CSV headers/order intact.
COPY INTO STAYWISE_DB.RAW.LISTINGS
FROM @STAYWISE_DB.RAW.DATA_STAGE/listings.csv
    FILE_FORMAT = (FORMAT_NAME = STAYWISE_DB.RAW.CSV_FORMAT)
    ON_ERROR = ABORT_STATEMENT;

COPY INTO STAYWISE_DB.RAW.GUESTS
FROM @STAYWISE_DB.RAW.DATA_STAGE/guests.csv
    FILE_FORMAT = (FORMAT_NAME = STAYWISE_DB.RAW.CSV_FORMAT)
    ON_ERROR = ABORT_STATEMENT;

COPY INTO STAYWISE_DB.RAW.BOOKINGS
FROM @STAYWISE_DB.RAW.DATA_STAGE/bookings.csv
    FILE_FORMAT = (FORMAT_NAME = STAYWISE_DB.RAW.CSV_FORMAT)
    ON_ERROR = ABORT_STATEMENT;

COPY INTO STAYWISE_DB.RAW.LISTING_CALENDAR
FROM @STAYWISE_DB.RAW.DATA_STAGE/listing_calendar.csv
    FILE_FORMAT = (FORMAT_NAME = STAYWISE_DB.RAW.CSV_FORMAT)
    ON_ERROR = ABORT_STATEMENT;

-- Only metadata belongs in this table. The PDF bytes stay in DOC_STAGE.
COPY INTO STAYWISE_DB.KNOWLEDGE.DOCUMENT_MANIFEST
FROM @STAYWISE_DB.RAW.DATA_STAGE/document_manifest.csv
    FILE_FORMAT = (FORMAT_NAME = STAYWISE_DB.RAW.CSV_FORMAT)
    ON_ERROR = ABORT_STATEMENT;

-- Counts should be 30, 150, 500, 5400, and 31 respectively.
SELECT
    'listings' AS source,
    COUNT(*) AS total_rows
FROM STAYWISE_DB.RAW.LISTINGS

UNION ALL

SELECT
    'guests',
    COUNT(*) AS total_rows
FROM STAYWISE_DB.RAW.GUESTS

UNION ALL

SELECT
    'bookings',
    COUNT(*) AS total_rows
FROM STAYWISE_DB.RAW.BOOKINGS

UNION ALL

SELECT
    'calendar',
    COUNT(*) AS total_rows
FROM STAYWISE_DB.RAW.LISTING_CALENDAR

UNION ALL

SELECT
    'documents',
    COUNT(*) AS total_rows
FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_MANIFEST;
