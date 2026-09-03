-- =====================================================================
-- Adhesives Research
-- Oracle EBS Inventory Item Creation
-- Production Cross-Schema Grants
--
-- Date: 2026-09-03
-- Author: JCALZADILLA
--
-- Purpose:
--   Apply all direct cross-schema object privileges required by the
--   current production architecture:
--
--     * OPS owns the ADRE_INV_ITEM_* application data model.
--     * APPS owns APPS.ADRE_CREATE_INV_ITEM.
--     * Oracle APEX uses OPS as its parsing schema.
--
-- Execution:
--   Run this complete file as a DBA account (or another account allowed
--   to grant privileges on both OPS and APPS objects).
--
-- Security principle:
--   Grant only the privileges required by the current application/package.
--   Stored PL/SQL in APPS must receive required OPS object privileges
--   directly; privileges inherited only through roles are not sufficient
--   for compilation/execution of definer-rights stored PL/SQL.
--
-- Notes:
--   * No grants are required from APPS to APPS-owned EBS APIs/packages
--     such as EGO_ITEM_PUB, INV_ITEM_CATEGORY_PUB, FND_GLOBAL,
--     FND_MSG_PUB, FND_API, or MO_GLOBAL.
--   * No synonyms are required by the current main package because it
--     references OPS objects with explicit OPS qualification.
--   * OPS.ADRE_INV_ITEM_TYPE, OPS.ADRE_INV_ITEM_SECTION,
--     OPS.ADRE_INV_ITEM_DOCUMENT, and OPS.ADRE_INV_ITEM_BOM_COMP do not
--     currently require cross-schema grants to APPS because the current
--     APPS.ADRE_CREATE_INV_ITEM implementation does not directly use them.
--     APEX can access them directly because OPS is the parsing schema.
-- =====================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT Adhesives Research - Production Grants
PROMPT ================================================================


-- =====================================================================
-- SECTION 1 - OPS objects required by APPS.ADRE_CREATE_INV_ITEM
-- =====================================================================

PROMPT Granting OPS application object privileges to APPS...

GRANT SELECT, UPDATE
ON ops.adre_inv_item_request
TO apps;

GRANT SELECT, UPDATE
ON ops.adre_inv_item_request_org
TO apps;

GRANT SELECT, UPDATE
ON ops.adre_inv_item_category
TO apps;

GRANT SELECT, UPDATE
ON ops.adre_inv_item_attr_value
TO apps;

GRANT SELECT
ON ops.adre_inv_item_attribute
TO apps;

GRANT SELECT
ON ops.adre_inv_item_type_attr
TO apps;

GRANT SELECT
ON ops.adre_inv_item_template_rule
TO apps;

GRANT SELECT
ON ops.adre_inv_item_bom
TO apps;

GRANT INSERT
ON ops.adre_inv_item_api_log
TO apps;


-- =====================================================================
-- SECTION 2 - Existing application logging package
--
-- The current APPS.ADRE_CREATE_INV_ITEM implementation still calls
-- OPS.PKG_LOG for diagnostic logging. Keep this privilege while that
-- dependency remains in the production package.
-- =====================================================================

PROMPT Granting OPS.PKG_LOG execution privilege to APPS...

GRANT EXECUTE
ON ops.pkg_log
TO apps;


-- =====================================================================
-- SECTION 3 - Allow the APEX parsing schema to call the integration
-- package.
--
-- OPS is the current APEX parsing schema.
-- =====================================================================

PROMPT Granting APPS.ADRE_CREATE_INV_ITEM execution privilege to OPS...

GRANT EXECUTE
ON apps.adre_create_inv_item
TO ops;


-- =====================================================================
-- SECTION 4 - Post-grant verification
--
-- This section requires access to DBA_TAB_PRIVS.
-- It shows the privileges that belong to this production grant set.
-- =====================================================================

PROMPT ================================================================
PROMPT Granted privileges
PROMPT ================================================================

SELECT
    owner,
    table_name AS object_name,
    grantee,
    privilege,
    grantable
FROM dba_tab_privs
WHERE
       (
           owner = 'OPS'
           AND grantee = 'APPS'
           AND table_name IN
           (
               'ADRE_INV_ITEM_REQUEST',
               'ADRE_INV_ITEM_REQUEST_ORG',
               'ADRE_INV_ITEM_CATEGORY',
               'ADRE_INV_ITEM_ATTR_VALUE',
               'ADRE_INV_ITEM_ATTRIBUTE',
               'ADRE_INV_ITEM_TYPE_ATTR',
               'ADRE_INV_ITEM_TEMPLATE_RULE',
               'ADRE_INV_ITEM_BOM',
               'ADRE_INV_ITEM_API_LOG',
               'PKG_LOG'
           )
       )
    OR
       (
           owner = 'APPS'
           AND grantee = 'OPS'
           AND table_name = 'ADRE_CREATE_INV_ITEM'
       )
ORDER BY
    owner,
    table_name,
    grantee,
    privilege;


-- =====================================================================
-- SECTION 5 - Missing privilege check
--
-- EXPECTED RESULT:
--   NO ROWS
--
-- Any row returned by this query identifies a privilege that is still
-- missing from the environment.
-- =====================================================================

PROMPT ================================================================
PROMPT Missing required privileges - EXPECTED RESULT: NO ROWS
PROMPT ================================================================

WITH expected_grants AS
(
    SELECT 'OPS' AS owner,
           'ADRE_INV_ITEM_REQUEST' AS object_name,
           'APPS' AS grantee,
           'SELECT' AS privilege
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_REQUEST', 'APPS', 'UPDATE'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_REQUEST_ORG', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_REQUEST_ORG', 'APPS', 'UPDATE'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_CATEGORY', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_CATEGORY', 'APPS', 'UPDATE'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_ATTR_VALUE', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_ATTR_VALUE', 'APPS', 'UPDATE'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_ATTRIBUTE', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_TYPE_ATTR', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_TEMPLATE_RULE', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_BOM', 'APPS', 'SELECT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'ADRE_INV_ITEM_API_LOG', 'APPS', 'INSERT'
    FROM dual

    UNION ALL
    SELECT 'OPS', 'PKG_LOG', 'APPS', 'EXECUTE'
    FROM dual

    UNION ALL
    SELECT 'APPS', 'ADRE_CREATE_INV_ITEM', 'OPS', 'EXECUTE'
    FROM dual
)
SELECT
    e.owner,
    e.object_name,
    e.grantee,
    e.privilege
FROM expected_grants e
WHERE NOT EXISTS
(
    SELECT 1
    FROM dba_tab_privs p
    WHERE p.owner      = e.owner
      AND p.table_name = e.object_name
      AND p.grantee    = e.grantee
      AND p.privilege  = e.privilege
)
ORDER BY
    e.owner,
    e.object_name,
    e.grantee,
    e.privilege;


PROMPT ================================================================
PROMPT Production grants script completed.
PROMPT Review the missing privilege query above. It must return NO ROWS.
PROMPT ================================================================

-- =====================================================================
-- END OF FILE
-- =====================================================================
