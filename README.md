# Comm-Log Reconciliation — target_base = 22

## Reconciliation Bridge

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | `SELECT COUNT(*) FROM communication_log` | 30 | Naive starting point — raw row count, no filtering |
| 1 | `SELECT COUNT(DISTINCT customer_id) FROM communication_log` | 25 | First instinct — unique customers overall. Still wrong: ignores campaign eligibility and retry structure |
| 2 | Exclude campaign 9004 (`creation_status = 'approval_awaiting'`) | −4 customers (C11–C14) | Send pipeline can run ahead of approval bookkeeping — unapproved campaign sends don't count toward reporting even though rows exist |
| 3 | Collapse retry chains via `parent_id` to their root campaign, dedupe by customer **within each chain** | Family A (root 9001) → 10; Family B (root 9201) → 5 | A retry chain is one underlying communication — a customer retried multiple times in-chain counts once |
| 4 | For standalone campaigns (no retry chain), do **not** dedupe — count every send row | 9101 → 7 rows (C20 appears twice, both count) | Standalone campaigns treat repeat sends to the same customer as independent events, not retries |
| **final** | 10 + 5 + 7 | **22** | Matches Finance's reported target_base |

## SQL
See [`target_base_reconciliation.sql`](./target_base_reconciliation.sql). Run against comm_log.db.
