-- RUN AS STAYWISE_BUILDER after bootstrap. No source data is deleted here.

USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;

-- CSV files have a header and quoted strings (including comma-separated pet rules).
CREATE FILE FORMAT IF NOT EXISTS STAYWISE_DB.RAW.CSV_FORMAT
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('')
    EMPTY_FIELD_AS_NULL = TRUE;

-- Catalogue grain: one property, linked to a specific version of its house rules.
CREATE TABLE IF NOT EXISTS STAYWISE_DB.RAW.LISTINGS (
    listing_id VARCHAR,
    title VARCHAR,
    neighborhood VARCHAR,
    capacity INTEGER,
    bedrooms INTEGER,
    wifi BOOLEAN,
    pets_allowed BOOLEAN,
    rule_set_id VARCHAR
);

-- All guest names are synthetic identifiers.
CREATE TABLE IF NOT EXISTS STAYWISE_DB.RAW.GUESTS (
    guest_id VARCHAR,
    display_name VARCHAR
);

-- Booking grain: one reservation; store the original rate rather than today's rate.
CREATE TABLE IF NOT EXISTS STAYWISE_DB.RAW.BOOKINGS (
    booking_id VARCHAR,
    listing_id VARCHAR,
    guest_id VARCHAR,
    check_in DATE,
    check_out DATE,
    guest_count INTEGER,
    status VARCHAR,
    booked_nightly_rate NUMBER(12, 2),
    booked_fees NUMBER(12, 2),
    rule_set_id VARCHAR
);

-- Calendar grain: property + night + update time. Bookings determine occupancy;
-- host_blocked represents a separate reason the host has withdrawn that night.
CREATE TABLE IF NOT EXISTS STAYWISE_DB.RAW.LISTING_CALENDAR (
    listing_id VARCHAR,
    stay_date DATE,
    nightly_rate NUMBER(12, 2),
    host_blocked BOOLEAN,
    updated_at TIMESTAMP_NTZ
);

-- The manifest connects each PDF filename to its listing and effective rule version.
CREATE TABLE IF NOT EXISTS STAYWISE_DB.KNOWLEDGE.DOCUMENT_MANIFEST (
    doc_id VARCHAR,
    title VARCHAR,
    listing_id VARCHAR,
    rule_set_id VARCHAR,
    effective_from DATE,
    effective_to DATE,
    relative_path VARCHAR
);
