-- Expose booking attributes and metrics through one reservation-grain semantic view.
-- It intentionally excludes availability: the deterministic tools handle that.

USE ROLE STAYWISE_BUILDER;

CREATE OR REPLACE SEMANTIC VIEW STAYWISE_DB.AI.STAY_ANALYTICS
    -- Declare the physical table and its reservation key for Analyst grounding.
    TABLES (
        bookings AS STAYWISE_DB.ANALYTICS.MART_BOOKING_CONTEXT
            PRIMARY KEY (booking_id)
    )

    -- Facts are row-level numeric expressions; metrics aggregate them.
    FACTS (
        bookings.lodging_value AS booked_lodging_value,
        bookings.nights AS booked_nights
    )

    -- Dimensions are attributes the user can filter, group, or ask to retrieve.
    DIMENSIONS (
        bookings.booking_id AS booking_id
            COMMENT = 'Reservation ID such as B-1042',
        bookings.listing_id AS listing_id,
        bookings.title AS title,
        bookings.neighborhood AS neighborhood,
        bookings.guest_id AS guest_id,
        bookings.guest_name AS display_name,
        bookings.guest_count AS guest_count,
        bookings.check_in AS check_in,
        bookings.check_out AS check_out
            COMMENT = 'Checkout is exclusive',
        bookings.status AS status,
        bookings.rule_set_id AS rule_set_id,
        bookings.source_document_id AS source_document_id
    )

    -- The value metric explicitly excludes cancelled reservations and fees.
    METRICS (
        bookings.reservation_count AS COUNT(booking_id),
        bookings.active_booked_value AS SUM(
            IFF(status != 'cancelled', booked_lodging_value, 0)
        )
            COMMENT = 'INR lodging value by reservation check-in date. Excludes cancelled bookings and fees. Not recognized revenue.'
    )
    COMMENT = 'StayWise synthetic booking data. Use check_in for monthly booked-value questions.';
