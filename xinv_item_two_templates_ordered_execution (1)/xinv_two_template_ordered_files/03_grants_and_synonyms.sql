/* ============================================================
   Grants required before compiling APPS.XINV_ITEM_API_PKG
   Run this section as OPS or DBA.
   ============================================================ */

GRANT SELECT, INSERT, UPDATE, DELETE ON ops.xinv_item_creation_stg TO apps;
GRANT SELECT ON ops.xinv_item_types TO apps;
GRANT EXECUTE ON ops.pkg_log TO apps;

/* ============================================================
   Optional synonyms. The package uses OPS-qualified names, so synonyms are not
   required for this package, but they are useful for manual testing from APPS.
   Run as APPS or DBA if desired.
   ============================================================ */

CREATE OR REPLACE SYNONYM apps.xinv_item_creation_stg FOR ops.xinv_item_creation_stg;
CREATE OR REPLACE SYNONYM apps.xinv_item_types FOR ops.xinv_item_types;
CREATE OR REPLACE SYNONYM apps.pkg_log FOR ops.pkg_log;

/* ============================================================
   Grant package execution back to OPS/APEX parsing schema after compile.
   Run as APPS or DBA after APPS.XINV_ITEM_API_PKG compiles.
   ============================================================ */

GRANT EXECUTE ON apps.xinv_item_api_pkg TO ops;
CREATE OR REPLACE SYNONYM ops.xinv_item_api_pkg FOR apps.xinv_item_api_pkg;
