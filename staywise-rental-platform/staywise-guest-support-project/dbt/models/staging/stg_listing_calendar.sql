-- A later uploaded row replaces an older rate/block for the same listing-night.
-- Conflicting updates with the same timestamp are caught by a singular test.

SELECT
    listing_id::VARCHAR AS listing_id,
    stay_date::DATE AS stay_date,
    nightly_rate::NUMBER(12, 2) AS nightly_rate,
    host_blocked::BOOLEAN AS host_blocked,
    updated_at::TIMESTAMP_NTZ AS updated_at
FROM {{ source('raw', 'listing_calendar') }}
-- QUALIFY runs after the window function and retains only the newest update.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY listing_id, stay_date
    ORDER BY updated_at DESC
) = 1
