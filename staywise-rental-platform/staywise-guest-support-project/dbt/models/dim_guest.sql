-- A separate dimension shows a familiar star-schema relationship.
-- Grain: one guest_id. Keeping this separate avoids repeated guest attributes
-- in raw booking records. ref() ensures staging is built first.

SELECT *
FROM {{ ref('stg_guests') }}
