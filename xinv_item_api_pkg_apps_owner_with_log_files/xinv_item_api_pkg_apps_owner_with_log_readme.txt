AR Global - XINV Item API Package with APPS-qualified EBS calls

Files:
1. xinv_item_api_pkg_apps_owner_with_log.pks
   Package specification.

2. xinv_item_api_pkg_apps_owner_with_log.pkb
   Package body.

3. xinv_item_api_pkg_apps_owner_with_log_all.sql
   Combined package specification and body.

4. xinv_item_api_pkg_apps_owner_with_log_test_call.sql
   Sample validation calls.

Main correction in this version:
- Calls APPS.EGO_ITEM_PUB.PROCESS_ITEM instead of EGO_ITEM_PUB.PROCESS_ITEM.
- Calls APPS.FND_GLOBAL, APPS.MO_GLOBAL, and APPS.FND_MSG_PUB with owner qualification.
- Removes direct references to EGO_ITEM_PUB.G_MISS_CHAR, EGO_ITEM_PUB.G_TTYPE_CREATE, and EGO_ITEM_PUB.G_TTYPE_UPDATE.
- Removes dependency on ERROR_HANDLER.ERROR_TBL_TYPE.
- Uses local constants for standard EBS API values: CREATE, UPDATE, CHR(0), S, E, U, T, F.

Compile order:
1. Confirm the staging tables exist.
2. Confirm PKG_LOG exists and has SP_INSERT_MESSAGE.
3. Confirm the schema has execute access to APPS.EGO_ITEM_PUB, APPS.FND_GLOBAL, APPS.MO_GLOBAL, and APPS.FND_MSG_PUB.
4. Run xinv_item_api_pkg_apps_owner_with_log_all.sql.

Important:
If the package still fails on APPS.EGO_ITEM_PUB.PROCESS_ITEM, run this in the target environment to confirm the exact local API signature:

SELECT line, text
  FROM all_source
 WHERE owner = 'APPS'
   AND name = 'EGO_ITEM_PUB'
   AND type = 'PACKAGE'
   AND UPPER(text) LIKE '%PROCEDURE PROCESS_ITEM%'
 ORDER BY line;
