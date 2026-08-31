/* ============================================================
   AR Global - Optional cleanup
   Purpose:
   - Drop the old temporary package APPS.XINV_ITEM_ORG_ASSIGN_PKG.
   - The new flow uses APPS.XINV_ITEM_API_PKG only.

   Run as APPS or DBA.
   This script is optional.
   ============================================================ */

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE apps.xinv_item_org_assign_pkg';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

PROMPT Optional cleanup completed.
