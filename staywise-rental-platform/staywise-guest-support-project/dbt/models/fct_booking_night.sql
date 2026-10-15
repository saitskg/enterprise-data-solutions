-- Expand active stays into occupied nights. Checkout is EXCLUDED.
-- A small fixed date-offset spine avoids an external dbt package dependency.

WITH offsets AS (
    -- Offsets 0 through 29 cover the maximum supported 30-night stay.
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n
    FROM TABLE(GENERATOR(ROWCOUNT => 30))
)

-- Grain becomes booking_id + stay_date. A later test rejects overlapping
-- active reservations for a listing-night.
SELECT
    b.booking_id,
    b.listing_id,
    DATEADD('day', o.n, b.check_in)::DATE AS stay_date,
    b.booked_nightly_rate
FROM {{ ref('fct_booking') }} b
JOIN offsets o
    ON o.n < b.booked_nights
-- Cancelled reservations do not occupy nights; completed stays retain history.
WHERE b.status IN ('confirmed', 'completed')
