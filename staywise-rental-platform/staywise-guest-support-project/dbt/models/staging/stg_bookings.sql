-- Preserve booking-time rates; current calendar prices must not rewrite history.
-- Normalize status once and use fixed-precision currency throughout dbt.
-- rule_set_id preserves the policy agreed at booking time.

SELECT
    booking_id::VARCHAR AS booking_id,
    listing_id::VARCHAR AS listing_id,
    guest_id::VARCHAR AS guest_id,
    check_in::DATE AS check_in,
    check_out::DATE AS check_out,
    guest_count::INTEGER AS guest_count,
    LOWER(TRIM(status)) AS status,
    booked_nightly_rate::NUMBER(12, 2) AS booked_nightly_rate,
    booked_fees::NUMBER(12, 2) AS booked_fees,
    rule_set_id::VARCHAR AS rule_set_id
FROM {{ source('raw', 'bookings') }}
