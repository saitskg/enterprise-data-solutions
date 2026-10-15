-- Equal timestamps are allowed only when the actual values agree.
-- Group by source key AND timestamp. More than one distinct price/block value
-- would make the latest-row choice nondeterministic and must fail the build.

SELECT
    listing_id,
    stay_date,
    updated_at
FROM {{ source('raw', 'listing_calendar') }}
GROUP BY 1, 2, 3
HAVING COUNT(DISTINCT CONCAT(nightly_rate, '|', host_blocked)) > 1
