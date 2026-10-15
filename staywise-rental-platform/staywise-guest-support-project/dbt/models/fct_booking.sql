-- Grain: one reservation. Booked value is not recognized revenue.
-- datediff counts occupied nights because checkout is excluded. Keep cancelled
-- records here for analysis; downstream revenue/occupancy models filter status.

SELECT
    *,
    DATEDIFF('day', check_in, check_out) AS booked_nights,
    DATEDIFF('day', check_in, check_out) * booked_nightly_rate AS booked_lodging_value
FROM {{ ref('stg_bookings') }}
