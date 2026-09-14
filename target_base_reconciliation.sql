-- Comm-Log Reconciliation: target_base for merchant 501, October 2026
-- Result: 22

WITH RECURSIVE
-- Walk each campaign up its parent_id chain to find the ultimate root
-- (the earliest campaign in its retry lineage, or itself if it has no parent).
chain(id, current_id) AS (
    SELECT id, id FROM campaign
    UNION ALL
    SELECT ch.id, c.parent_id
    FROM chain ch
    JOIN campaign c ON c.id = ch.current_id
    WHERE c.parent_id IS NOT NULL
),
roots AS (
    SELECT ch.id, ch.current_id AS root_id
    FROM chain ch
    WHERE NOT EXISTS (
        SELECT 1 FROM campaign c
        WHERE c.id = ch.current_id AND c.parent_id IS NOT NULL
    )
),

-- A campaign only counts toward reporting once its creation workflow has
-- cleared AND its send pipeline has finished processing.
eligible_campaign AS (
    SELECT id FROM campaign
    WHERE creation_status IN ('approved','aborted','resumed','stopped')
      AND processing_status = 'processed'
),

-- A root is part of a genuine retry chain if some other campaign's
-- parent_id points back at it. Roots with no retries are standalone leaves.
has_retry AS (
    SELECT DISTINCT parent_id AS root_id
    FROM campaign
    WHERE parent_id IS NOT NULL
),

tagged AS (
    SELECT
        cl.id AS log_id,
        cl.customer_id,
        r.root_id,
        CASE WHEN hr.root_id IS NOT NULL THEN 1 ELSE 0 END AS is_chain
    FROM communication_log cl
    JOIN eligible_campaign ec ON ec.id = cl.communication_id
    JOIN roots r ON r.id = cl.communication_id
    LEFT JOIN has_retry hr ON hr.root_id = r.root_id
)

-- Retry chains: dedupe by (root, customer) - a customer retried multiple
--   times within one underlying communication counts once.
-- Standalone campaigns: every send row counts as its own event, even if
--   the same customer appears more than once.
SELECT
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT root_id, customer_id FROM tagged WHERE is_chain = 1
    ))
    +
    (SELECT COUNT(*) FROM tagged WHERE is_chain = 0)
    AS target_base;
