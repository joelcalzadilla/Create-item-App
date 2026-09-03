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

-- Dependency:
--   OPS.ADRE_INV_ITEM_SECTION must already contain the referenced SECTION_CODE.
--   ITEM_SECTION_ID is resolved dynamically in the destination environment.
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
    p('-- BEGIN GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_ATTRIBUTE');
    p('-- ITEM_SECTION_ID is resolved by SECTION_CODE.');
    p('-- =====================================================================');
    p('');

    FOR r IN
    (
        SELECT
            s.section_code,
            a.attribute_code,
            a.attribute_name,
            a.attribute_data_type,
            a.description,
            a.default_value,
            a.unit_of_measure,
            a.required_flag,
            a.active_flag,
            a.display_sequence,
            a.ebs_attribute_name,
            a.ebs_attribute_group
        FROM ops.adre_inv_item_attribute a
        LEFT JOIN ops.adre_inv_item_section s
          ON s.item_section_id = a.item_section_id
        ORDER BY
            NVL(a.display_sequence, 999999),
            a.attribute_code
    )
    LOOP
        p('INSERT INTO ops.adre_inv_item_attribute');
        p('(item_section_id, attribute_code, attribute_name, attribute_data_type,');
        p(' description, default_value, unit_of_measure, required_flag, active_flag,');
        p(' display_sequence, ebs_attribute_name, ebs_attribute_group,');
        p(' created_by, creation_date, last_updated_by, last_update_date, last_update_login)');
        p('SELECT');

        IF r.section_code IS NULL THEN
            p('       NULL,');
        ELSE
            p('       (SELECT s.item_section_id');
            p('          FROM ops.adre_inv_item_section s');
            p('         WHERE UPPER(TRIM(s.section_code)) = UPPER(TRIM(' ||
              f_q(r.section_code) || '))),');
        END IF;

        p('       ' || f_q(r.attribute_code) || ',');
        p('       ' || f_q(r.attribute_name) || ',');
        p('       ' || f_q(r.attribute_data_type) || ',');
        p('       ' || f_q(r.description) || ',');
        p('       ' || f_q(r.default_value) || ',');
        p('       ' || f_q(r.unit_of_measure) || ',');
        p('       ' || f_q(r.required_flag) || ',');
        p('       ' || f_q(r.active_flag) || ',');
        p('       ' || f_n(r.display_sequence) || ',');
        p('       ' || f_q(r.ebs_attribute_name) || ',');
        p('       ' || f_q(r.ebs_attribute_group) || ',');
        p('       ''DEPLOYMENT'', SYSDATE, ''DEPLOYMENT'', SYSDATE, NULL');
        p('FROM dual');
        p('WHERE NOT EXISTS');
        p('(');
        p('    SELECT 1');
        p('    FROM ops.adre_inv_item_attribute a');
        p('    WHERE UPPER(TRIM(a.attribute_code)) = UPPER(TRIM(' ||
          f_q(r.attribute_code) || '))');
        p(');');
        p('');
    END LOOP;

    p('COMMIT;');
    p('');
    p('-- Validation');
    p('SELECT COUNT(*) AS attribute_count FROM ops.adre_inv_item_attribute;');
    p('');
    p('-- =====================================================================');
    p('-- END GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_ATTRIBUTE');
    p('-- =====================================================================');
END;
/
