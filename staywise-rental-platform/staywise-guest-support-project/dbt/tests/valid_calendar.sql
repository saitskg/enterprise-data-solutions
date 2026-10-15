-- Missing/invalid rates must never be interpreted as a free stay.
-- Test uniqueness, completeness, positive prices, and host-block consistency
-- at the same grain used by the availability procedure.

SELECT
    listing_id,
    stay_date
FROM {{ ref('mart_listing_day') }}
GROUP BY 1, 2
HAVING COUNT(*) != 1
    OR COUNT(nightly_rate) != 1
    OR MIN(nightly_rate) <= 0
    OR COUNT_IF(host_blocked AND booking_count > 0) > 0
