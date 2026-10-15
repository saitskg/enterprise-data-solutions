# StayWise — Snowflake setup runbook

Follow these steps in order in **Snowsight**, using an active Snowflake trial account and a user with `ACCOUNTADMIN` access. Have the supplied `staywise` folder available for browser uploads. All builds and application execution take place on Snowflake.

The workspace holds your project files. The scripts create the database, tables, services, and application. **You do not need to create or select a project database before step 2.** For the project overview, see [README.md](README.md).

## 1. Create the project workspace and upload the files

1. Sign in to Snowsight.
2. Open **Projects → Workspaces → + → Private Workspace** and name it `StayWise`.
3. Inside it, select **Add new → Upload Folder** and upload the supplied `staywise` folder.
4. Confirm that the file explorer contains `sql/`, `dbt/`, `app/`, `snowflake_tools/`, `data/`, `streamlit_app.py`, and `environment.yml` under the uploaded project folder.
5. Use this workspace for every SQL step below. Open the indicated file and choose **Run All**, unless the step explicitly says to run selected statements.

Paths below are relative to the uploaded `staywise` folder. For extra verification queries shown in this guide, use **Add new → SQL File** to create `checks.sql` in the workspace and run the relevant query there. Python files are deployed by the supplied SQL scripts; you do not need to run them individually.

**Check:** The project files are visible in `StayWise`. Uploading them into a workspace does not load tables or copy files into runtime stages; those actions come later. See Snowflake's [workspace creation example](https://docs.snowflake.com/en/developer-guide/code-bundles/code-bundles#quickstart-snowsight) and [file upload instructions](https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces-working).

## 2. Create the Snowflake objects

The name `STAYWISE_DB` is reserved for this project. If that database already contains unrelated work, resolve the name conflict before running bootstrap.

1. Open [sql/00_bootstrap.sql](sql/00_bootstrap.sql) in the workspace.
2. Select `ACCOUNTADMIN` as the execution role and run the entire file. The script creates the objects before using them.
3. Refresh Snowsight if the new roles or objects are not yet visible.
4. Now set the SQL editor context to role `STAYWISE_BUILDER`, warehouse `STAYWISE_WH`, database `STAYWISE_DB`, and schema `RAW`. Use this context when opening subsequent SQL files; retain each script's own `USE ROLE` and `USE WAREHOUSE` statements.

The script creates:

| Object | Purpose |
|---|---|
| `STAYWISE_WH` | X-Small warehouse with 60-second auto-suspend |
| `STAYWISE_BUILDER`, `STAYWISE_APP` | Setup role and application role, assigned to your user |
| `STAYWISE_DB` | Project database |
| `RAW`, `ANALYTICS`, `KNOWLEDGE`, `AI`, `APP` | Schemas inside the project database |
| Five internal stages | File storage for CSVs, dbt, PDFs, procedure code, and the app |

**Check:** In **Catalog → Explorer**, expand `STAYWISE_DB` and confirm all five schemas exist.

## 3. Check the account's AI and package access

Open [sql/00_preflight.sql](sql/00_preflight.sql). Run its role/warehouse statements, then each query separately using **Run Selected**.

**Check:** Every package has a nonzero `available_versions` count, and the final `AI_COMPLETE` response contains `status: ready`.

If the model is unavailable, choose a supported structured-output model for your region and update the name in this SQL file, [app/settings.py](app/settings.py), and [sql/09_smoke_checks.sql](sql/09_smoke_checks.sql). Repeat the preflight before continuing, and use the updated files for later uploads. If package terms are requested, complete them as administrator under **Admin → Billing & Terms**.

Trial credits, feature access, and regional availability still apply. This check verifies completion and package access; later steps verify dbt, parsing, Search, and Analyst. See [trial limitations](https://docs.snowflake.com/en/user-guide/admin-trial-account#current-limitations-for-trial-accounts) and [Cortex availability](https://docs.snowflake.com/en/user-guide/snowflake-cortex/llm-functions#availability).

## 4. Create the raw tables and load the CSVs

1. Return to the workspace and run [sql/01_raw_tables.sql](sql/01_raw_tables.sql). This creates the empty tables and CSV format.
2. Upload these **five files** from `data/` to `STAYWISE_DB.RAW.DATA_STAGE`: `listings.csv`, `guests.csv`, `bookings.csv`, `listing_calendar.csv`, and `document_manifest.csv`.

Use this stage-upload procedure here and for every later upload:

1. Select role `STAYWISE_BUILDER` in Snowsight.
2. Open **Ingestion → Add Data → Load files into a Stage**.
3. Select the supplied files, then database `STAYWISE_DB`, the specified schema, and stage.
4. Leave **Path** empty when the instructions say *root*. Otherwise select/create the exact destination path shown.
5. Select **Upload** and wait for success. Return to the `StayWise` workspace afterwards.

These are file uploads to an existing stage. The supplied SQL handles table creation and loading. See [Snowflake's stage-upload guide](https://docs.snowflake.com/en/user-guide/data-load-local-file-system-stage-ui).

Verify the five CSVs are at the stage root:

```sql
USE ROLE STAYWISE_BUILDER;
LIST @STAYWISE_DB.RAW.DATA_STAGE;
```

Then run [sql/02_load.sql](sql/02_load.sql).

**Check:** Its final query reports these counts:

| Dataset | Rows |
|---|---:|
| listings | 30 |
| guests | 150 |
| bookings | 500 |
| calendar | 5,400 |
| documents | 31 |

If a count differs, inspect the corresponding `COPY INTO` result before continuing. Normal reruns skip previously loaded files; do not add `FORCE=TRUE`, which can duplicate rows.

## 5. Upload and build the dbt project

**Select individual files, in five upload batches. Do not select the whole `dbt` folder, its subfolders, or a ZIP file.** You can select multiple files together in each batch. The workspace upload from step 1 has not populated this stage.

1. Select role `STAYWISE_BUILDER` in Snowsight.
2. Open **Ingestion → Add Data → Load files into a Stage**.
3. In the file picker, open the folder listed below and select the specified files from the supplied `staywise` project.
4. Choose database **`STAYWISE_DB`**, schema **`RAW`**, and stage **`DBT_STAGE`**. Set the destination **Path** exactly as listed, then select **Upload**.
5. Wait for success and repeat the upload dialog for the next batch. Use the same database, schema, and stage for all five batches.

| Batch | Folder to open in the file picker | Files to select | Destination Path |
|---|---|---|---|
| 1 | `staywise/dbt/` | Only `dbt_project.yml` and `dbt_projects_profiles.yml` — **2 files** | **Leave empty** |
| 2 | `staywise/dbt/models/` | All **10 files directly in this folder**: 8 SQL files plus `sources.yml` and `schema.yml`. Do not select the `staging` folder. | `models` |
| 3 | `staywise/dbt/models/staging/` | All **4 SQL files** | `models/staging` |
| 4 | `staywise/dbt/tests/` | All **4 SQL files** | `tests` |
| 5 | `staywise/data/` | Only `policy_rules.csv` — **1 file** | `data` |

The Path is relative to `DBT_STAGE`. For example, uploading `stg_bookings.sql` with Path `models/staging` creates `DBT_STAGE/models/staging/stg_bookings.sql`. Do not enter `dbt/models/staging` or the full stage name in the Path field.

After the five uploads, the stage must contain this exact layout:

```text
DBT_STAGE/
├── dbt_project.yml
├── dbt_projects_profiles.yml
├── models/
│   ├── sources.yml
│   ├── schema.yml
│   ├── dim_guest.sql
│   ├── dim_listing.sql
│   ├── fct_booking.sql
│   ├── fct_booking_night.sql
│   ├── int_calendar_current.sql
│   ├── mart_booking_context.sql
│   ├── mart_listing_day.sql
│   ├── mart_listing_performance.sql
│   └── staging/
│       ├── stg_bookings.sql
│       ├── stg_guests.sql
│       ├── stg_listing_calendar.sql
│       └── stg_listings.sql
├── tests/
│   ├── no_ambiguous_calendar_updates.sql
│   ├── no_overlapping_bookings.sql
│   ├── valid_booking_windows.sql
│   └── valid_calendar.sql
└── data/
    └── policy_rules.csv
```

Return to `checks.sql` in the `StayWise` workspace and run:

```sql
USE ROLE STAYWISE_BUILDER;
LIST @STAYWISE_DB.RAW.DBT_STAGE;
```

**Check before building:** The listing contains **21 files**, arranged as above. The two configuration files are immediately under `DBT_STAGE`, with no extra `dbt/` directory. If a file is misplaced, remove that misplaced copy through **Catalog → Explorer → STAYWISE_DB → RAW → DBT_STAGE** and upload it again using the correct Path.

Now open and run [sql/03_dbt.sql](sql/03_dbt.sql) in the workspace. It creates `STAYWISE_DB.ANALYTICS.STAYWISE_DBT` and runs `dbt build` on Snowflake, loading the policy seed, building the models, and running tests.

**Check:** Inspect the execution result and dbt logs; all models, the seed, and tests must succeed. In `checks.sql`, run:

```sql
USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;
SELECT COUNT(*) FROM STAYWISE_DB.ANALYTICS.MART_BOOKING_CONTEXT; -- Expected: 500
SELECT COUNT(*) FROM STAYWISE_DB.ANALYTICS.MART_LISTING_DAY;     -- Expected: 5400
SELECT COUNT(*) FROM STAYWISE_DB.ANALYTICS.POLICY_RULES;         -- Expected: 30
```

If Snowflake rejects the configured dbt version `1.11.11`, select an available native version at least `1.10.5` in `03_dbt.sql` and retry. See [CREATE DBT PROJECT](https://docs.snowflake.com/en/sql-reference/sql/create-dbt-project).

## 6. Upload the PDFs and create document search

1. Upload all **31 PDFs** from `data/pdfs/` to the root of **`STAYWISE_DB.KNOWLEDGE.DOC_STAGE`**. Do not add a `pdfs/` destination folder.
2. In the workspace, run `LIST @STAYWISE_DB.KNOWLEDGE.DOC_STAGE;` as builder. Expect `DOC_R001.pdf` through `DOC_R030.pdf`, plus `DOC_GENERAL.pdf`.
3. Open [sql/04_documents.sql](sql/04_documents.sql). **Run selected sections in the following order, not Run All:**

| Order | Statements to execute | Result to check |
|---|---|---|
| 1 | `USE` statements, stage `REFRESH`, `CREATE TABLE`, and the entire `CREATE PROCEDURE ... $$;` statement | Table and `KNOWLEDGE.PARSE_ONE_DOCUMENT` procedure created |
| 2 | The first `CALL ... PARSE_ONE_DOCUMENT('DOC_R001')` | Returned `status` is `saved` or `skipped`; inspect `error`/`response` if it is `failed` |
| 3 | The remaining 30 `CALL` statements, in order | Each PDF is processed separately; previously saved documents are skipped |
| 4 | Coverage query beginning `WITH documents_with_text AS (...)` | **Zero rows**; every manifest document has stored page text |
| 5 | `CREATE OR REPLACE TABLE ... DOCUMENT_CHUNKS` | Text chunks created with document/page identifiers |
| 6 | `CREATE OR REPLACE CORTEX SEARCH SERVICE ... STAY_SEARCH` | Search service created and initial indexing succeeds |
| 7 | Final `SEARCH_PREVIEW` query | L002 policy text says dogs are allowed and cats are not |

The procedure makes one `AI_PARSE_DOCUMENT` request, validates its response, and then saves the document in a separate SQL statement. `parsed` stores the document with its `pages` array, not the diagnostic envelope. Run the calls as standalone statements without wrapping them in a transaction. If replacing an earlier bulk INSERT, cancel that running attempt before starting these calls.

In `checks.sql`, verify coverage and service status:

```sql
USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;
SELECT COUNT(DISTINCT doc_id)
FROM STAYWISE_DB.KNOWLEDGE.DOCUMENT_CHUNKS; -- Expected: 31
DESCRIBE CORTEX SEARCH SERVICE STAYWISE_DB.KNOWLEDGE.STAY_SEARCH;
```

If a call returns `status: failed`, inspect its `error` and filename, correct the cause, and rerun that document's call. The procedure retries invalid existing rows and preserves valid ones; no manual deletion is needed. A timed-out call may terminate with a SQL error instead. Earlier completed standalone calls remain saved. Do not continue to chunking until the coverage query returns zero rows.

This per-document loader replaces the bulk INSERT that stalled during account execution. Its source has been checked; the revised procedure still requires execution in your account. The one-document checkpoint above verifies it before processing the rest.

## 7. Create the agent's data and pricing tools

1. Run [sql/05_semantic_view.sql](sql/05_semantic_view.sql) in the workspace. It creates `AI.STAY_ANALYTICS`, which Cortex Analyst uses to understand booking data.
2. Upload `snowflake_tools/stay_tools.py` to the root of **`STAYWISE_DB.RAW.CODE_STAGE`**.
3. Run `LIST @STAYWISE_DB.RAW.CODE_STAGE;` and confirm `stay_tools.py` is at the root.
4. Run [sql/06_tools.sql](sql/06_tools.sql). It creates `FIND_AVAILABLE_STAYS` and `QUOTE_STAY_OPTION` on Snowflake.

**Check:** The example procedure call at the end of `06_tools.sql` returns `status: eligible` and `total: 8500` for L003. The amount comprises ₹7,000 lodging, ₹500 cleaning, ₹300 pet fee, and ₹700 service fee.

## 8. Create the request log and grant app access

Run [sql/07_grants.sql](sql/07_grants.sql) in the workspace as `STAYWISE_BUILDER`.

This creates `STAYWISE_DB.APP.REQUEST_LOG` and gives `STAYWISE_APP` access to the required curated tables, semantic view, Search service, procedures, and application stage. The app can save investigation results in the log.

**Check:** The script completes successfully and `APP.REQUEST_LOG` appears in Catalog. It is empty until an investigation is saved.

## 9. Upload and deploy the Streamlit app

Upload the following **nine files** to **`STAYWISE_DB.APP.APP_STAGE`**, using `STAYWISE_BUILDER` for the upload:

| Source files | Destination path |
|---|---|
| `streamlit_app.py`, `environment.yml` | Root |
| All six `.py` files inside `app/`, including `__init__.py` | `app` |
| `data/evaluation_cases.json` | `data` |

Use the updated `settings.py` if you changed the model in step 3. Verify the file placement:

```sql
USE ROLE STAYWISE_BUILDER;
LIST @STAYWISE_DB.APP.APP_STAGE;
```

1. Return to the workspace and run [sql/08_streamlit.sql](sql/08_streamlit.sql). It switches to `STAYWISE_APP`, creates the app with the **warehouse runtime**, and publishes its live version.
2. In Snowsight, select `STAYWISE_APP`, then open **Projects → Streamlit → StayWise**, or find `STAYWISE_DB.APP.STAYWISE` in Catalog and open it.
3. Allow the first launch to resolve the packages declared in `environment.yml`.

The supplied dependency file leaves Python selection to the managed runtime. Newly created apps currently default to Python 3.11. If needed, open the app editor's **Packages** menu and select **Python 3.11** using the Python version selector; do not add `python` through the package search. If startup reports `Packages not found: python==3.11`, remove the `python=3.11` dependency from the app's `environment.yml` and redeploy the corrected file. Keep `RUNTIME_VERSION = '3.11'` in the stored-procedure SQL; that setting is separate. See [Python versions and package selection](https://docs.snowflake.com/en/developer-guide/streamlit/app-development/dependency-management).

**Dependency syntax:** The warehouse runtime accepts package names, `package=version`, and wildcard versions such as `jsonschema=4.*`. Do not use `>=` or `<=`; an entry such as `streamlit>=1.35` can be read as the invalid package name `streamlit>`. See [Snowflake dependency syntax](https://docs.snowflake.com/en/developer-guide/streamlit/app-development/dependency-management#best-practices-for-declaring-dependencies).

**If the app already fails with this error:** Upload the corrected `environment.yml` to the root of `STAYWISE_DB.APP.APP_STAGE` as `STAYWISE_BUILDER`, replacing the existing file. Rerun `08_streamlit.sql` to copy and publish the corrected source, then reopen the app. A stage upload alone does not update the deployed app. If you made changes directly in the app editor, preserve them before recreating the app from the stage.

**Check:** The sidebar shows **Booking desk**, **Stay comparison**, **Operations overview**, and **Integration checks**. If an import fails, check the stage paths and package-resolution message before continuing. See [Streamlit SQL deployment](https://docs.snowflake.com/en/sql-reference/sql/create-streamlit).

## 10. Run the deployment checks

Return to the workspace:

1. Run [sql/09_smoke_checks.sql](sql/09_smoke_checks.sql). It checks access using `STAYWISE_APP`.
2. Run [sql/11_data_checks.sql](sql/11_data_checks.sql). It switches to builder and checks data counts, booking grain, and document coverage. Every `passed` value must be `TRUE`.

The smoke checks should show:

| Check | Expected result |
|---|---|
| B-1042 | L001, checkout 2026-09-23, two guests |
| L001 extension, September 23–25 | `unavailable` |
| L002 with a cat | `ineligible` |
| L003 with a cat | `eligible`, total 8500 |
| Candolim candidate search | Includes L002 and L003 |
| Completion call | Successful AI response |

Next, open the app's **Integration checks** page:

1. Leave **Include live Cortex agent checks** unchecked and select **Run checks**. Expect **7/7** procedure checks to pass.
2. Enable **Include live Cortex agent checks** and run again. Expect **12/12** total checks to pass, including five live agent scenarios. These calls consume AI credits.
3. Download the check results. Inspect any failed case's details and tool evidence before treating deployment as complete.

`10_schedule.sql` is optional; it is not part of the initial setup sequence.

## 11. Test one complete investigation

In the Streamlit **Booking desk**:

1. Select booking **B-1042**.
2. Set check-in **2026-09-23**, checkout **2026-09-25**, neighborhood **Candolim**, guests **2**, pet **cat**, and budget **9000**. Keep these fixed sample dates when verifying the supplied data.
3. Choose **Stay resolution** and enter:

   > Can I extend my stay by two nights? If it is unavailable, find a stay in Candolim for those extra nights, under ₹9,000 total. I am traveling with my cat.

4. Select **Investigate request** once.
5. Confirm the recommendation is **L003 / ₹8,500 excluding taxes**, with itemized fees and a **DOC_R003** policy citation. Inspect the tool evidence for the unavailable extension and rejected alternatives.
6. Open **Stay comparison** and **Operations overview** to verify the other pages load.

Back in the workspace, inspect the saved investigation:

```sql
USE ROLE STAYWISE_BUILDER;
USE WAREHOUSE STAYWISE_WH;
-- One row stores the completed investigation and its public tool evidence.
SELECT created_at, request_id, question, result:status::VARCHAR AS status,
       result:quote:listing_id::VARCHAR AS recommended_listing,
       result:quote:total::NUMBER(12,2) AS quoted_total
FROM STAYWISE_DB.APP.REQUEST_LOG
ORDER BY created_at DESC LIMIT 10;
```

**Setup is complete when:** dbt and data checks pass, the app's integration checks pass, and the reference investigation returns the verified quote and policy evidence. Deployment in a live Snowflake account has not been executed as part of preparing these files; the steps above verify your account's actual result.

## After setup: stop usage and resume later

Close the app. In the workspace, run:

```sql
USE ROLE STAYWISE_BUILDER;
-- Suspend Search serving/indexing as well as warehouse compute.
ALTER CORTEX SEARCH SERVICE STAYWISE_DB.KNOWLEDGE.STAY_SEARCH SUSPEND;
ALTER TASK IF EXISTS STAYWISE_DB.ANALYTICS.DAILY_BUILD SUSPEND;
ALTER WAREHOUSE STAYWISE_WH SUSPEND;
```

If the warehouse is already suspended, leave it that way. Suspending only the warehouse does not stop Search serving. See [Search suspension](https://docs.snowflake.com/en/sql-reference/sql/alter-cortex-search).

To use the app again, run the following as builder, wait for Search to be ready, and reopen the app. The warehouse resumes on demand.

```sql
USE ROLE STAYWISE_BUILDER;
ALTER CORTEX SEARCH SERVICE STAYWISE_DB.KNOWLEDGE.STAY_SEARCH RESUME;
```

## Optional: updates, scheduling, and removal

- **App changes:** Edit and publish through the Streamlit editor, or replace the corresponding files in `APP_STAGE` and rerun `08_streamlit.sql`. Uploading files alone does not publish a new app version.
- **Procedure changes:** Replace `CODE_STAGE/stay_tools.py`, then rerun `06_tools.sql`, `07_grants.sql`, and the procedure checks.
- **Data changes:** Load new source records and rerun `EXECUTE DBT PROJECT STAYWISE_DB.ANALYTICS.STAYWISE_DBT ARGS = 'build --target dev';`. Calendar corrections need a newer `updated_at`; older corrections require `build --full-refresh --target dev`.
- **dbt source changes:** Replace the files at their existing `DBT_STAGE` paths, deploy the updated project using the applicable [ALTER DBT PROJECT](https://docs.snowflake.com/en/sql-reference/sql/alter-dbt-project) command, and execute the build. `03_dbt.sql` creates the project only if absent; rerunning it does not publish changed source files.
- **Daily scheduling:** Run [sql/10_schedule.sql](sql/10_schedule.sql) to create a suspended task. To enable it, run the following; leave it suspended when scheduled builds are unnecessary.

```sql
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE STAYWISE_BUILDER;
USE ROLE STAYWISE_BUILDER;
ALTER TASK STAYWISE_DB.ANALYTICS.DAILY_BUILD RESUME;
```

To remove the deployment and start fresh:

1. Close the StayWise app and stop submitting project setup/build queries.
2. In your Snowsight workspace, open [sql/99_teardown.sql](sql/99_teardown.sql) and choose **Run All** once. It switches to `ACCOUNTADMIN`, cancels work on `STAYWISE_WH`, drops that warehouse, drops `STAYWISE_DB` with all its contents, and removes both project roles. The script can also be rerun after an incomplete setup or cleanup.
3. Check the final four `SHOW` results: each should have zero rows for the named project object.
4. Start again at **step 2**, running `00_bootstrap.sql`, then repeat the remaining upload/build/deployment steps.

The database cleanup includes the **Streamlit app, all five stages and their uploaded files, Cortex Search service, dbt project, scheduled task, semantic view, procedures, tables, views, and application request log**. Your private Snowsight workspace and its source files remain available for the fresh setup; to remove those too, delete that workspace separately in Snowsight. Snowflake-managed query/account history and retained data follow Snowflake's retention rules; they do not prevent rebuilding with the same names. See [DROP DATABASE](https://docs.snowflake.com/en/sql-reference/sql/drop-database).
