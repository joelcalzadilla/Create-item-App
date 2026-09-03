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

-- Dependencies:
--   OPS.ADRE_INV_ITEM_TYPE and OPS.ADRE_INV_ITEM_ATTRIBUTE must already
--   contain the referenced business keys.
--   ITEM_TYPE_ID and ITEM_ATTRIBUTE_ID are resolved dynamically.
-- =====================================================================

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
    p('-- BEGIN GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_TYPE_ATTR');
    p('-- ITEM_TYPE_ID and ITEM_ATTRIBUTE_ID are resolved dynamically.');
    p('-- =====================================================================');
    p('');

    FOR r IN
    (
        SELECT
            it.item_type_code,
            a.attribute_code,
            ta.organization_scope,
            ta.required_flag,
            ta.default_value,
            ta.active_flag,
            ta.display_sequence
        FROM ops.adre_inv_item_type_attr ta
        JOIN ops.adre_inv_item_type it
          ON it.item_type_id = ta.item_type_id
        JOIN ops.adre_inv_item_attribute a
          ON a.item_attribute_id = ta.item_attribute_id
        ORDER BY
            it.item_type_code,
            NVL(ta.display_sequence, 999999),
            a.attribute_code
    )
    LOOP
        p('INSERT INTO ops.adre_inv_item_type_attr');
        p('(item_type_id, item_attribute_id, organization_scope, required_flag,');
        p(' default_value, active_flag, display_sequence,');
        p(' created_by, creation_date, last_updated_by, last_update_date, last_update_login)');
        p('SELECT');
        p('       (SELECT t.item_type_id');
        p('          FROM ops.adre_inv_item_type t');
        p('         WHERE UPPER(TRIM(t.item_type_code)) = UPPER(TRIM(' ||
          f_q(r.item_type_code) || '))),');
        p('       (SELECT a.item_attribute_id');
        p('          FROM ops.adre_inv_item_attribute a');
        p('         WHERE UPPER(TRIM(a.attribute_code)) = UPPER(TRIM(' ||
          f_q(r.attribute_code) || '))),');
        p('       ' || f_q(r.organization_scope) || ',');
        p('       ' || f_q(r.required_flag) || ',');
        p('       ' || f_q(r.default_value) || ',');
        p('       ' || f_q(r.active_flag) || ',');
        p('       ' || f_n(r.display_sequence) || ',');
        p('       ''DEPLOYMENT'', SYSDATE, ''DEPLOYMENT'', SYSDATE, NULL');
        p('FROM dual');
        p('WHERE NOT EXISTS');
        p('(');
        p('    SELECT 1');
        p('    FROM ops.adre_inv_item_type_attr ta');
        p('    JOIN ops.adre_inv_item_type t');
        p('      ON t.item_type_id = ta.item_type_id');
        p('    JOIN ops.adre_inv_item_attribute a');
        p('      ON a.item_attribute_id = ta.item_attribute_id');
        p('    WHERE UPPER(TRIM(t.item_type_code)) = UPPER(TRIM(' ||
          f_q(r.item_type_code) || '))');
        p('      AND UPPER(TRIM(a.attribute_code)) = UPPER(TRIM(' ||
          f_q(r.attribute_code) || '))');
        p(');');
        p('');
    END LOOP;

    p('COMMIT;');
    p('');
    p('-- Validation');
    p('SELECT COUNT(*) AS item_type_attr_count FROM ops.adre_inv_item_type_attr;');
    p('');
    p('-- =====================================================================');
    p('-- END GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_TYPE_ATTR');
    p('-- =====================================================================');
END;
/
