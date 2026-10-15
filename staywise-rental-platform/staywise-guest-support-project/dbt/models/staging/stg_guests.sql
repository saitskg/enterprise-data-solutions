-- Guest records are intentionally synthetic and contain only display names.
-- source() points at the already-loaded RAW table and records dbt lineage.

SELECT
    guest_id::VARCHAR AS guest_id,
    display_name::VARCHAR AS display_name
FROM {{ source('raw', 'guests') }}
