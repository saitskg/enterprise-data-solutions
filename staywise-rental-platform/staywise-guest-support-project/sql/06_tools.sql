-- WHERE: SQL file in the StayWise Snowsight workspace, after uploading stay_tools.py to CODE_STAGE.
-- Both procedure handlers import the shared availability and pricing implementation.
-- Snowflake imports this source and supplies the first session argument itself.

USE ROLE STAYWISE_BUILDER;

-- FIND_AVAILABLE_STAYS: shortlist properties with complete, available date coverage.
-- Inputs: check_in/check_out are inclusive/exclusive ISO dates; neighborhood is an
-- exact match; guests is required capacity; pet_type is none/cat/dog; max_total is INR.
-- Returns: VARIANT containing up to five candidates, lodging estimates, and a note.
-- Invalid dates/inputs raise a handler error. Detailed pet rules and fees are checked
-- by QUOTE_STAY_OPTION. This procedure performs parameterized reads only.
CREATE OR REPLACE PROCEDURE STAYWISE_DB.AI.FIND_AVAILABLE_STAYS(
    check_in VARCHAR,
    check_out VARCHAR,
    neighborhood VARCHAR,
    guests INTEGER,
    pet_type VARCHAR,
    max_total FLOAT
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
IMPORTS = ('@STAYWISE_DB.RAW.CODE_STAGE/stay_tools.py')
HANDLER = 'stay_tools.find_available_stays'
EXECUTE AS OWNER;

-- QUOTE_STAY_OPTION: validate a property and return its complete itemized price.
-- Inputs: listing_id, inclusive/exclusive ISO dates, guests, pet_type, mode
-- (new_stay/extension), and booking_id (required for extension; otherwise empty).
-- Returns: VARIANT with eligible/ineligible/unavailable/needs_review status and
-- reason; eligible results include INR amounts, dates, and policy provenance.
-- Extensions must match the original booking's listing, guests, and checkout.
-- Invalid date syntax/duration raises a handler error. No booking is modified.
CREATE OR REPLACE PROCEDURE STAYWISE_DB.AI.QUOTE_STAY_OPTION(
    listing_id VARCHAR,
    check_in VARCHAR,
    check_out VARCHAR,
    guests INTEGER,
    pet_type VARCHAR,
    mode VARCHAR,
    booking_id VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
IMPORTS = ('@STAYWISE_DB.RAW.CODE_STAGE/stay_tools.py')
HANDLER = 'stay_tools.quote_stay_option'
EXECUTE AS OWNER;

-- Owner rights expose only the fixed, parameterized reads in stay_tools.py.
CALL STAYWISE_DB.AI.QUOTE_STAY_OPTION(
    'L003',
    '2026-09-23',
    '2026-09-25',
    2,
    'cat',
    'new_stay',
    ''
);
