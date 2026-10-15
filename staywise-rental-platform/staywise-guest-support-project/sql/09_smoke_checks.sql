-- Run as STAYWISE_APP AFTER deployment. These checks exercise actual Snowflake tools.

USE ROLE STAYWISE_APP;
USE SECONDARY ROLES NONE;
USE WAREHOUSE STAYWISE_WH;

SELECT
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE();

SELECT *
FROM STAYWISE_DB.ANALYTICS.MART_BOOKING_CONTEXT
WHERE booking_id = 'B-1042';

-- Expected: unavailable; original listing is occupied on the extra nights.
CALL STAYWISE_DB.AI.QUOTE_STAY_OPTION(
    'L001',
    '2026-09-23',
    '2026-09-25',
    2,
    'cat',
    'extension',
    'B-1042'
);

-- Expected: ineligible; dogs-only rule rejects a cat.
CALL STAYWISE_DB.AI.QUOTE_STAY_OPTION(
    'L002',
    '2026-09-23',
    '2026-09-25',
    2,
    'cat',
    'new_stay',
    ''
);

-- Expected: eligible, total 8500, lodging 7000, cleaning 500, pet 300, service 700.
CALL STAYWISE_DB.AI.QUOTE_STAY_OPTION(
    'L003',
    '2026-09-23',
    '2026-09-25',
    2,
    'cat',
    'new_stay',
    ''
);

CALL STAYWISE_DB.AI.FIND_AVAILABLE_STAYS(
    '2026-09-23',
    '2026-09-25',
    'Candolim',
    2,
    'cat',
    9000.0
);

SELECT AI_COMPLETE(
    'claude-sonnet-4-6',
    'Reply with exactly: StayWise ready'
);
