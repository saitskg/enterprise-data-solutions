-- Incremental MERGE grain: listing_id + stay_date. New updates replace a night.

{{ config(
    materialized='incremental',
    unique_key=['listing_id', 'stay_date'],
    incremental_strategy='merge'
) }}

-- The compound key updates existing nights instead of appending duplicates.
-- >= re-reads the newest timestamp so equal-time batch rows are not skipped.
SELECT *
FROM {{ ref('stg_listing_calendar') }}

-- On the first build/full-refresh, read all rows. On subsequent builds, read
-- the latest update window; older late corrections require --full-refresh.
{% if is_incremental() %}
WHERE updated_at >= (
    SELECT COALESCE(MAX(updated_at), '1900-01-01'::TIMESTAMP_NTZ)
    FROM {{ this }}
)
{% endif %}
