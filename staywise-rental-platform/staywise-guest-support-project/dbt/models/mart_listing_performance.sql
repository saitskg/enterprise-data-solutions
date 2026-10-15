-- Occupancy is computed from listing-days; booking money is aggregated separately.
-- This prevents a booking-to-night join from multiplying reservation values.

WITH days AS (
    -- Offered nights exclude host blocks; occupied nights come from bookings.
    SELECT
        listing_id,
        DATE_TRUNC('month', stay_date)::DATE AS month,
        COUNT_IF(NOT host_blocked) AS offered_nights,
        COUNT_IF(booking_count > 0) AS occupied_nights
    FROM {{ ref('mart_listing_day') }}
    GROUP BY 1, 2
),

values_by_month AS (
    -- Attribute the whole reservation's booked value to its check-in month.
    SELECT
        listing_id,
        DATE_TRUNC('month', check_in)::DATE AS month,
        COUNT(*) AS booking_count,
        SUM(booked_lodging_value) AS booked_lodging_value
    FROM {{ ref('fct_booking') }}
    WHERE status != 'cancelled'
    GROUP BY 1, 2
)

-- NULLIF makes months with no offered nights return NULL occupancy, not an
-- error or a misleading zero. coalesce fills months with no bookings with zero.
SELECT
    d.*,
    l.neighborhood,
    l.title,
    d.occupied_nights / NULLIF(d.offered_nights, 0)::FLOAT AS occupancy_rate,
    COALESCE(v.booking_count, 0) AS booking_count,
    COALESCE(v.booked_lodging_value, 0) AS booked_lodging_value
FROM days d
JOIN {{ ref('dim_listing') }} l
    USING (listing_id)
LEFT JOIN values_by_month v
    ON d.listing_id = v.listing_id
    AND d.month = v.month
