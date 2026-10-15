-- One-to-one dimension joins preserve the reservation grain for Cortex Analyst.
-- Analyst sees one easy-to-query relation with booking, guest, listing, and
-- policy provenance. Unique-key dbt tests protect each side of these joins.

SELECT
    b.*,
    l.title,
    l.neighborhood,
    l.capacity,
    l.pets_allowed,
    g.display_name,
    p.source_document_id
FROM {{ ref('fct_booking') }} b
JOIN {{ ref('dim_listing') }} l
    USING (listing_id)
JOIN {{ ref('dim_guest') }} g
    USING (guest_id)
JOIN {{ ref('policy_rules') }} p
    ON b.rule_set_id = p.rule_set_id
