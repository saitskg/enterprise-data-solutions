-- Cast and name catalogue fields once so downstream models share a clean contract.
-- pets_allowed is only a coarse search attribute. POLICY_RULES determines
-- which species are allowed, so a true flag must not approve a cat by itself.

SELECT
    listing_id::VARCHAR AS listing_id,
    title::VARCHAR AS title,
    neighborhood::VARCHAR AS neighborhood,
    capacity::INTEGER AS capacity,
    bedrooms::INTEGER AS bedrooms,
    wifi::BOOLEAN AS wifi,
    pets_allowed::BOOLEAN AS pets_allowed,
    rule_set_id::VARCHAR AS rule_set_id
FROM {{ source('raw', 'listings') }}
