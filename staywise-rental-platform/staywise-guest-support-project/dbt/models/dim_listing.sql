-- Stable property attributes; rules stay linked by an explicit versioned key.
-- ref() declares dbt lineage and resolves the upstream view in ANALYTICS.
-- This dimension has exactly one row per listing_id.

SELECT *
FROM {{ ref('stg_listings') }}
