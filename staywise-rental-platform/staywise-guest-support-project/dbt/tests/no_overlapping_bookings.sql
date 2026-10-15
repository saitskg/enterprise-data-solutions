-- One property cannot have two active reservations for the same occupied night.
-- Return offending listing-nights; zero returned rows means the test passes.

SELECT
    listing_id,
    stay_date,
    COUNT(*) AS occupied_by
FROM {{ ref('fct_booking_night') }}
GROUP BY 1, 2
HAVING COUNT(*) > 1
