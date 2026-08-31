AR Global - XINV Item Creation V2 Execution Pack
==================================================

This pack recreates the complete item creation solution using V2 object names.
The V2 objects can run side-by-side with the original non-V2 objects.

Main V2 objects
---------------
OPS.XINV_ITEM_TYPES_V2
OPS.XINV_ITEM_CREATION_STG_V2
APPS.XINV_ITEM_API_PKG_V2

Main design
-----------
One staging row represents one item request.
The row stores two templates:

MASTER_ORG_CODE       = MAS
MASTER_TEMPLATE_NAME  = GLOBAL ITEM
TARGET_ORG_CODE       = GRI
TARGET_TEMPLATE_NAME  = ADHESIVES

The package performs two internal steps when needed:
1. Create or verify the item in MAS using MASTER_TEMPLATE_NAME.
2. Create or verify the item in GRI using TARGET_TEMPLATE_NAME.

Execution order
---------------
00_optional_drop_v2_objects.sql
   Optional. Drops only V2 objects so you can reinstall cleanly.

01_create_custom_tables_v2_as_ops.sql
   Run as OPS. Creates OPS.XINV_ITEM_TYPES_V2 and OPS.XINV_ITEM_CREATION_STG_V2.

02_seed_item_type_id_1_v2_as_ops.sql
   Run as OPS. Inserts ITEM_TYPE_ID = 1 for Adhesive Coating.

03_grants_and_synonyms_v2.sql
   Run grants as OPS or DBA before package compile.
   Run APPS synonyms as APPS or DBA if desired.
   Run package grant back to OPS after package compile.

04_create_apps_xinv_item_api_pkg_v2.sql
   Run as APPS. Creates APPS.XINV_ITEM_API_PKG_V2.

05_insert_test_staging_row_v2_as_ops.sql
   Run as OPS. Inserts one test row for MH-94904-992 using MAS/GLOBAL ITEM and GRI/ADHESIVES.

06_manual_test_call_and_validation_v2.sql
   Run as OPS, APPS, or a schema with EXECUTE privilege. Calls the V2 package and validates MAS/GRI.

07_apex_button_process_v2.sql
   Copy this PL/SQL into the APEX button process.

08_troubleshooting_queries_v2.sql
   Use this if the package does not compile or the API returns an error.

APEX button call
----------------
The button should call:

APPS.XINV_ITEM_API_PKG_V2.PCD_CALL_ITEM_API

The APEX process should pass the staging row ID from OPS.XINV_ITEM_CREATION_STG_V2.

Important
---------
Do not set MASTER_ORG_CODE to GRI.
For the MAS to GRI flow, keep:

MASTER_ORG_CODE = MAS
TARGET_ORG_CODE = GRI

The master template and target template are stored separately.
