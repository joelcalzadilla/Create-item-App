AR Global - XINV Two-Template Item Creation Package
Execution order

Purpose
-------
This set recreates the custom staging table and compiles APPS.XINV_ITEM_API_PKG
for the one-row / two-template flow:

1. Master item step:
   MASTER_ORG_CODE      = MAS
   MASTER_TEMPLATE_NAME = GLOBAL ITEM

2. Target organization step:
   TARGET_ORG_CODE      = GRI
   TARGET_TEMPLATE_NAME = ADHESIVES

One APEX button calls one package procedure. The package internally performs
up to two EBS API operations if needed.

Execution order
---------------
00_optional_drop_old_org_assign_pkg_as_apps.sql
   Run as APPS or DBA.
   Optional. Drops the old temporary APPS.XINV_ITEM_ORG_ASSIGN_PKG.

01_create_custom_tables_as_ops.sql
   Run as OPS.
   WARNING: Drops and recreates XINV_ITEM_TYPES and XINV_ITEM_CREATION_STG.
   Back up existing staging data first if needed.

02_seed_item_type_id_1_as_ops.sql
   Run as OPS.
   Inserts ITEM_TYPE_ID = 1 for Adhesive Coating.

03_grants_and_synonyms.sql
   Run the first section as OPS or DBA before compiling the package.
   Run the synonym section as APPS or DBA if desired.
   Run the final grant back to OPS after package compilation.

04_create_apps_xinv_item_api_pkg.sql
   Run as APPS.
   Creates/replaces APPS.XINV_ITEM_API_PKG.

05_insert_test_staging_row_as_ops.sql
   Run as OPS.
   Inserts the test staging row for MH-94904-992 with:
   MAS / GLOBAL ITEM and GRI / ADHESIVES.

06_manual_test_call_and_validation.sql
   Run as OPS, APPS, or another schema with EXECUTE on APPS.XINV_ITEM_API_PKG.
   Calls the package and validates that the item exists in MAS and GRI.

07_apex_button_process.sql
   Copy this PL/SQL into the APEX button process.
   Replace PXX_* page item names with the real APEX page item names.

08_troubleshooting_queries.sql
   Use only if something fails.

Important notes
---------------
- Do not set MASTER_ORG_CODE = GRI.
- The staging row should use MASTER_ORG_CODE = MAS and TARGET_ORG_CODE = GRI.
- Do not use one TEMPLATE_NAME for both orgs.
- Use MASTER_TEMPLATE_NAME for MAS and TARGET_TEMPLATE_NAME for GRI.
- The package uses OPS-qualified custom objects and APPS EBS public APIs.
