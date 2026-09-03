-- =====================================================================
-- Adhesives Research
-- Oracle EBS Inventory Item Creation
-- DEV Configuration -> Portable Production Seed DML Generator
--
-- Date: 2026-09-03
-- Author: JCALZADILLA
--
-- IMPORTANT:
--   Run this GENERATOR in the current DEV environment with Run Script (F5).
--   It does NOT modify data. It prints portable production INSERT statements.
--
-- Deployment principles:
--   * Do not export local surrogate IDs as dependencies.
--   * Resolve cross-table relationships by stable business codes.
--   * Generated INSERTs are re-runnable through WHERE NOT EXISTS.
--   * Development request/test data is not exported.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET VERIFY OFF

DECLARE
    FUNCTION f_q
    (
        p_value IN VARCHAR2
    )
    RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN 'NULL';
        END IF;

        RETURN '''' || REPLACE(p_value, '''', '''''') || '''';
    END f_q;

    FUNCTION f_n
    (
        p_value IN NUMBER
    )
    RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN 'NULL';
        END IF;

        RETURN TO_CHAR
               (
                   p_value,
                   'TM9',
                   'NLS_NUMERIC_CHARACTERS=''.,'''
               );
    END f_n;

    PROCEDURE p
    (
        p_text IN VARCHAR2
    )
    IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_text);
    END p;

BEGIN
    p('-- =====================================================================');
    p('-- BEGIN GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_SECTION');
    p('-- =====================================================================');
    p('');

    FOR r IN
    (
        SELECT
            section_code,
            section_name,
            section_type,
            organization_scope,
            active_flag,
            display_sequence
        FROM ops.adre_inv_item_section
        ORDER BY
            NVL(display_sequence, 999999),
            section_code
    )
    LOOP
        p('INSERT INTO ops.adre_inv_item_section');
        p('(section_code, section_name, section_type, organization_scope, active_flag,');
        p(' display_sequence, created_by, creation_date, last_updated_by,');
        p(' last_update_date, last_update_login)');
        p('SELECT ' ||
          f_q(r.section_code) || ', ' ||
          f_q(r.section_name) || ', ' ||
          f_q(r.section_type) || ', ' ||
          f_q(r.organization_scope) || ', ' ||
          f_q(r.active_flag) || ',');
        p('       ' || f_n(r.display_sequence) ||
          ', ''DEPLOYMENT'', SYSDATE, ''DEPLOYMENT'', SYSDATE, NULL');
        p('FROM dual');
        p('WHERE NOT EXISTS');
        p('(');
        p('    SELECT 1');
        p('    FROM ops.adre_inv_item_section s');
        p('    WHERE UPPER(TRIM(s.section_code)) = UPPER(TRIM(' ||
          f_q(r.section_code) || '))');
        p(');');
        p('');
    END LOOP;

    p('COMMIT;');
    p('');
    p('-- Validation');
    p('SELECT COUNT(*) AS section_count FROM ops.adre_inv_item_section;');
    p('');
    p('-- =====================================================================');
    p('-- END GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_SECTION');
    p('-- =====================================================================');
END;
/
