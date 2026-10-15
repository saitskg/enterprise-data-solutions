-- Rebuild the small availability mart each run so booking cancellations are visible.

WITH occupied AS (
    -- Aggregate occupied booking-nights before joining the calendar.
    SELECT
        listing_id,
        stay_date,
        COUNT(*) AS booking_count
    FROM {{ ref('fct_booking_night') }}
    GROUP BY
        listing_id,
        stay_date
)

-- Grain: one listing-night, including unavailable nights. coalesce maps no
-- booking match to zero; rates and host blocks still decide availability.
SELECT
    c.*,
    COALESCE(o.booking_count, 0) AS booking_count,
    NOT c.host_blocked
        AND COALESCE(o.booking_count, 0) = 0
        AND c.nightly_rate > 0 AS is_available
FROM {{ ref('int_calendar_current') }} c
LEFT JOIN occupied o
    USING (listing_id, stay_date)
