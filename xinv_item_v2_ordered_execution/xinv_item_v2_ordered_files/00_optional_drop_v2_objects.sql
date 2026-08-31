/* ============================================================
   AR Global - Optional Drop V2 Objects
   Purpose:
   - Drop only the V2 custom objects created by this package.
   - This does not drop the original non-V2 package or tables.

   Recommended use:
   - Run the APPS section as APPS or DBA.
   - Run the OPS section as OPS or DBA.
   ============================================================ */

PROMPT ============================================================
PROMPT APPS section - dropping V2 package
PROMPT ============================================================

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE apps.xinv_item_api_pkg_v2';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

PROMPT ============================================================
PROMPT OPS section - dropping V2 synonyms, triggers, and tables
PROMPT ============================================================

BEGIN
    EXECUTE IMMEDIATE 'DROP SYNONYM ops.xinv_item_api_pkg_v2';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -1434 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER ops.xinv_item_creation_stg_v2_biu';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4080 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER ops.xinv_item_types_v2_biu';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4080 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ops.xinv_item_creation_stg_v2 CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ops.xinv_item_types_v2 CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN
            RAISE;
        END IF;
END;
/

PROMPT V2 drop script completed.
