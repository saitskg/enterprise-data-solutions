# SQL execution guide

The SQL is organized by architectural responsibility instead of one long flat
list. Run folders from `00_setup` through `05_operations`; within a folder, run
files in numeric order.

| Folder | Responsibility | Objects created or operated |
|---|---|---|
| `00_setup` | Account and external connectivity prerequisites | Role, warehouse, database, schemas, S3 storage integration, optional GitHub Workspace API integration |
| `01_bronze` | Source landing and event-driven ingestion | JSON file format, external stage, raw tables, Snowpipes, initial reference loads |
| `02_silver` | Data quality and latest-state processing | Clean booking and provider Dynamic Tables |
| `03_gold` | Dimensional model and business processing | Dimensions, provider SCD2 Stream/Task, review AI Stream/Task, booking fact, daily KPI |
| `04_intelligence` | UI configuration reference/fallback | Semantic View, Cortex Agent, Snowflake CoWork access |
| `05_operations` | Verification, demonstration, and optional teardown | Pipeline monitoring, integrity checks, live-event walkthrough, commented cleanup |

## Required order

```text
00_setup/01_account_and_roles.sql
00_setup/02_s3_storage_integration.sql
01_bronze/01_stage_and_raw_tables.sql
01_bronze/02_snowpipe_auto_ingest.sql
01_bronze/03_initial_reference_load.sql
02_silver/01_clean_dynamic_tables.sql
03_gold/01_dimensions.sql
03_gold/02_provider_scd2_automation.sql
03_gold/03_review_ai_enrichment.sql
03_gold/04_booking_fact_and_kpis.sql
05_operations/01_monitoring_and_validation.sql
05_operations/02_live_event_demo.sql
```

Create the Intelligence objects through the Snowsight UI by following sections
17–19 of `docs/RUNBOOK.md`. The files under `04_intelligence` document the exact
equivalent object definitions and provide a troubleshooting fallback; they are
not part of the primary UI execution sequence.

`00_setup/03_github_workspace_integration.sql` is a one-time account setup file
for a Git-connected Snowflake Workspace. Run it from a regular worksheet before
creating the Workspace; it is not part of the data pipeline.

`05_operations/03_cleanup.sql` is optional. Its destructive statements remain
commented and must be reviewed individually before use.

Every file identifies its required role and prerequisites in the opening block.
Comments immediately above each command explain what it changes, why it is
needed, and what the developer should inspect afterward. For the complete AWS,
S3, GitHub, upload, validation, and live-demo procedure, follow the repository
runbook rather than executing files without their checkpoints.
