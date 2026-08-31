AR Global - V2 two-call item creation package

Execution order:

00_optional_drop_v2_objects.sql
    Optional cleanup. Drops only V2 objects.

01_create_custom_tables_v2_as_ops.sql
    Run as OPS. Creates OPS.XINV_ITEM_TYPES_V2 and OPS.XINV_ITEM_CREATION_STG_V2.

02_seed_item_type_id_1_v2_as_ops.sql
    Run as OPS. Seeds ITEM_TYPE_ID = 1.

03_grants_and_synonyms_v2.sql
    Run as OPS/DBA and APPS/DBA as indicated inside the file.

04_create_apps_xinv_item_api_pkg_v2_TWO_EXPLICIT_CALLS.sql
    Run as APPS or DBA. This is the main file.
    Inside PCD_CALL_ITEM_API there are two explicit APPS.EGO_ITEM_PUB.PROCESS_ITEM calls:
        CALL #1: MASTER_ORG_CODE + MASTER_TEMPLATE_NAME, e.g. MAS + GLOBAL ITEM
        CALL #2: TARGET_ORG_CODE + TARGET_TEMPLATE_NAME, e.g. GRI + ADHESIVES

05_insert_test_staging_row_v2_as_ops.sql
    Run as OPS. Inserts one test row with ITEM_TYPE_ID = 1.

06_manual_test_call_and_validation_v2.sql
    Run manually to call APPS.XINV_ITEM_API_PKG_V2.PCD_CALL_ITEM_API and validate MAS/GRI.

07_apex_button_process_v2.sql
    PL/SQL code for the APEX button process.

08_troubleshooting_queries_v2.sql
    Queries to check compilation errors, staging status, item org assignment, and API messages.

Important staging values for this requirement:
    MASTER_ORG_CODE       = MAS
    MASTER_TEMPLATE_NAME  = GLOBAL ITEM
    TARGET_ORG_CODE       = GRI
    TARGET_TEMPLATE_NAME  = ADHESIVES

One staging row is still correct. The package performs the two internal EBS API operations.
