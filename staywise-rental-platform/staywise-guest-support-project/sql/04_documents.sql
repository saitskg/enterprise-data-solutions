-- WHERE: SQL file in the StayWise Snowsight workspace, after uploading all 31 PDFs.
-- Run sections separately: setup, one-document check, remaining calls, then validation.
-- PDF filenames at DOC_STAGE root must match DOCUMENT_MANIFEST.relative_path.

USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;

-- Refresh the stage directory after browser uploads.
ALTER STAGE STAYWISE_DB.KNOWLEDGE.DOC_STAGE REFRESH;

CREATE TABLE IF NOT EXISTS STAYWISE_DB.KNOWLEDGE.PARSED_DOCUMENTS (
    doc_id VARCHAR,
    parsed VARIANT,
    parsed_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Parse and save ONE document per CALL, separating the AI request from the write.
-- Input: requested_doc_id must identify exactly one row in DOCUMENT_MANIFEST.
-- Output: an object with doc_id, status (saved/skipped/failed), and details.
-- Side effects: inserts a parsed document or replaces an invalid existing payload.
-- Valid existing documents are skipped. Use a new doc_id for a revised policy.
-- Errors: document/SQL errors are returned with the filename when available;
-- a cancelled or timed-out CALL may instead terminate with a Snowflake error.
-- Run CALLs sequentially as standalone statements, without an enclosing transaction.
CREATE OR REPLACE PROCEDURE STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT(
    requested_doc_id VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    manifest_rows INTEGER;
    document_path VARCHAR;
    text_pages INTEGER;
    response VARIANT;
    document_payload VARIANT;
    parse_error VARIANT;
BEGIN
    -- Resolve the filename and reject missing or ambiguous manifest entries.
    SELECT COUNT(*), MIN(relative_path)
    INTO :manifest_rows, :document_path
    FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_MANIFEST
    WHERE doc_id = :requested_doc_id;

    IF (manifest_rows != 1) THEN
        RETURN OBJECT_CONSTRUCT(
            'doc_id', requested_doc_id,
            'status', 'failed',
            'error', 'Expected exactly one manifest row for this document ID.'
        );
    END IF;

    -- A row counts as already parsed only when it contains actual page text.
    -- Null, string, diagnostic-wrapper, and empty payloads remain eligible for retry.
    SELECT COUNT(*) INTO :text_pages
    FROM STAYWISE_DB.KNOWLEDGE.PARSED_DOCUMENTS p,
        LATERAL FLATTEN(INPUT => p.parsed:pages) pg
    WHERE p.doc_id = :requested_doc_id
        AND TYPEOF(pg.value:content) = 'VARCHAR'
        AND LENGTH(TRIM(pg.value:content::VARCHAR)) > 0;

    IF (text_pages > 0) THEN
        RETURN OBJECT_CONSTRUCT('doc_id', requested_doc_id, 'status', 'skipped');
    END IF;

    -- Exactly one AI request, with no INSERT, MERGE, or manifest scan in this SELECT.
    -- TRUE requests the diagnostic result, including errors returned as data.
    SELECT AI_PARSE_DOCUMENT(
        TO_FILE('@STAYWISE_DB.KNOWLEDGE.DOC_STAGE', :document_path),
        {'mode': 'LAYOUT', 'page_split': TRUE},
        TRUE
    ) INTO :response;

    -- Accept either the diagnostic envelope's value or a direct document object.
    -- Decode only a string payload; passing an OBJECT to PARSE_JSON is invalid.
    document_payload := COALESCE(response:value, response);
    IF (TYPEOF(document_payload) = 'VARCHAR') THEN
        document_payload := TRY_PARSE_JSON(document_payload::VARCHAR);
    END IF;

    -- JSON null and SQL NULL both mean there is no top-level parsing error.
    parse_error := response:error;
    IF (parse_error IS NULL OR IS_NULL_VALUE(parse_error)) THEN
        parse_error := document_payload:error;
    END IF;
    IF (parse_error IS NULL OR IS_NULL_VALUE(parse_error)) THEN
        parse_error := document_payload:errorInformation;
    END IF;
    IF (parse_error IS NOT NULL AND NOT IS_NULL_VALUE(parse_error)) THEN
        RETURN OBJECT_CONSTRUCT(
            'doc_id', requested_doc_id,
            'file', document_path,
            'status', 'failed',
            'error', parse_error
        );
    END IF;

    -- Require real text before saving; an empty/error response must not be evidence.
    SELECT COUNT(*) INTO :text_pages
    FROM TABLE(FLATTEN(INPUT => GET(:document_payload, 'pages'))) pg
    WHERE TYPEOF(pg.value:content) = 'VARCHAR'
        AND LENGTH(TRIM(pg.value:content::VARCHAR)) > 0;

    IF (text_pages = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'doc_id', requested_doc_id,
            'file', document_path,
            'status', 'failed',
            'error', 'No nonempty page text was returned. Inspect response.',
            'response', response
        );
    END IF;

    -- The AI call has finished. This write uses only the validated in-memory payload.
    -- Repair an invalid existing row or insert a previously unseen document.
    MERGE INTO STAYWISE_DB.KNOWLEDGE.PARSED_DOCUMENTS target
    USING (
        SELECT :requested_doc_id AS doc_id, :document_payload AS parsed
    ) incoming
        ON target.doc_id = incoming.doc_id
    WHEN MATCHED THEN UPDATE SET
        target.parsed = incoming.parsed,
        target.parsed_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (doc_id, parsed)
        VALUES (incoming.doc_id, incoming.parsed);

    RETURN OBJECT_CONSTRUCT(
        'doc_id', requested_doc_id,
        'status', 'saved',
        'pages_with_text', text_pages
    );
EXCEPTION
    -- Surface an unexpected SQL error with the document that was being processed.
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(
            'doc_id', requested_doc_id,
            'file', document_path,
            'status', 'failed',
            'error', SQLERRM
        );
END;
$$;

-- Run this CALL first. Continue only when status is saved or skipped.
-- A successful SQL execution with status=failed still means document parsing failed.
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R001');

-- Run the remaining CALLs sequentially. Each is a separate one-document operation.
-- Previously saved documents are skipped, so these calls can be rerun after a failure.
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R002');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R003');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R004');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R005');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R006');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R007');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R008');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R009');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R010');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R011');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R012');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R013');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R014');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R015');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R016');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R017');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R018');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R019');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R020');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R021');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R022');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R023');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R024');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R025');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R026');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R027');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R028');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R029');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_R030');
CALL STAYWISE_DB.KNOWLEDGE.PARSE_ONE_DOCUMENT('DOC_GENERAL');

-- Verify all manifest entries have stored page text. This must return ZERO rows.
-- Unlike checking only stored rows, this also detects documents never inserted.
WITH documents_with_text AS (
    SELECT DISTINCT p.doc_id
    FROM STAYWISE_DB.KNOWLEDGE.PARSED_DOCUMENTS p,
        LATERAL FLATTEN(INPUT => p.parsed:pages) pg
    WHERE TYPEOF(pg.value:content) = 'VARCHAR'
        AND LENGTH(TRIM(pg.value:content::VARCHAR)) > 0
)
SELECT
    m.doc_id,
    m.relative_path
FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_MANIFEST m
LEFT JOIN documents_with_text d
    ON m.doc_id = d.doc_id
WHERE d.doc_id IS NULL
ORDER BY m.doc_id;

-- STOP HERE if the preceding failure query returns any rows.
-- Flatten pages, then create 1,600-character chunks with 200-character overlap.
-- Stable document/page/chunk IDs let final answers cite actual retrieved text.
CREATE OR REPLACE TABLE STAYWISE_DB.KNOWLEDGE.DOCUMENT_CHUNKS AS
SELECT
    m.doc_id,
    m.title,
    m.listing_id,
    m.rule_set_id,
    m.effective_from,
    m.effective_to,
    m.relative_path,
    pg.value:index::INTEGER + 1 AS page_number,
    m.doc_id || ':' || pg.index || ':' || ch.index AS chunk_id,
    m.title || '\n' || ch.value::VARCHAR AS chunk_text
FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_MANIFEST m
JOIN STAYWISE_DB.KNOWLEDGE.PARSED_DOCUMENTS p
    ON m.doc_id = p.doc_id,
LATERAL FLATTEN(input => p.parsed:pages) pg,
LATERAL FLATTEN(
    input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
        pg.value:content::VARCHAR,
        'markdown',
        1600,
        200
    )
) ch
WHERE LENGTH(TRIM(ch.value::VARCHAR)) > 0;

-- Search indexes the chunk text; attributes permit exact listing/rule filters.
-- TARGET_LAG controls index freshness, not a delay added to each user question.
CREATE OR REPLACE CORTEX SEARCH SERVICE STAYWISE_DB.KNOWLEDGE.STAY_SEARCH
    ON chunk_text
    ATTRIBUTES listing_id, rule_set_id, doc_id
    WAREHOUSE = STAYWISE_WH
    TARGET_LAG = '1 hour'
    AS
SELECT *
FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_CHUNKS;

-- SQL preview is for validating retrieval; the app uses the lower-latency Search REST API.
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'STAYWISE_DB.KNOWLEDGE.STAY_SEARCH',
    '{"query":"Are cats allowed?","columns":["DOC_ID","CHUNK_TEXT","PAGE_NUMBER"],"filter":{"@eq":{"LISTING_ID":"L002"}},"limit":3}'
);
