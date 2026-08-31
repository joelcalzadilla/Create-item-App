/* ============================================================
   Grants required before compiling APPS.XINV_ITEM_API_PKG_V2
   Run this section as OPS or DBA.
   ============================================================ */

GRANT SELECT, INSERT, UPDATE, DELETE ON ops.xinv_item_creation_stg_v2 TO apps;
GRANT EXECUTE ON ops.pkg_log TO apps;


/* ============================================================
   Grant V2 package execution back to OPS/APEX parsing schema after compile.
   Run as APPS or DBA after APPS.XINV_ITEM_API_PKG_V2 compiles.
   ============================================================ */

GRANT EXECUTE ON apps.xinv_item_api_pkg_v2_v2 TO ops;

