-- A failing dbt test returns violating rows; an empty result passes.
-- The 30-night upper bound matches the date spine and quote procedure contract.

SELECT *
FROM {{ ref('fct_booking') }}
WHERE check_out <= check_in
    OR booked_nights > 30
    OR guest_count < 1
    OR booked_nightly_rate <= 0
    OR booked_fees < 0
