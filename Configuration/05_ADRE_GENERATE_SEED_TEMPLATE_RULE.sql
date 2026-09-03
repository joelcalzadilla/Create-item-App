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
--   OPS.ADRE_INV_ITEM_TYPE must already contain the referenced ITEM_TYPE_CODE.
--   Oracle EBS organizations/templates must exist in the destination.
--
-- Environment portability:
--   EBS_ORGANIZATION_ID is resolved by ORGANIZATION_CODE.
--   EBS_TEMPLATE_ID     is resolved by TEMPLATE_NAME.
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

    FUNCTION f_d
    (
        p_value IN DATE
    )
    RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN 'NULL';
        END IF;

        RETURN
            'TO_DATE(''' ||
            TO_CHAR(p_value, 'YYYY-MM-DD HH24:MI:SS') ||
            ''',''YYYY-MM-DD HH24:MI:SS'')';
    END f_d;

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
    p('-- BEGIN GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_TEMPLATE_RULE');
    p('-- EBS_ORGANIZATION_ID resolved by ORGANIZATION_CODE.');
    p('-- EBS_TEMPLATE_ID resolved by TEMPLATE_NAME.');
    p('-- =====================================================================');
    p('');

    FOR r IN
    (
        SELECT
            it.item_type_code,
            ood.organization_code,
            tr.division_value,
            tr.business_unit_value,
            tr.expense_item_flag,
            t.template_name,
            tr.rule_status,
            tr.rule_notes,
            tr.rule_priority,
            tr.active_flag,
            tr.effective_start_date,
            tr.effective_end_date
        FROM ops.adre_inv_item_template_rule tr
        JOIN ops.adre_inv_item_type it
          ON it.item_type_id = tr.item_type_id
        LEFT JOIN apps.org_organization_definitions ood
          ON ood.organization_id = tr.ebs_organization_id
        LEFT JOIN apps.mtl_item_templates_vl t
          ON t.template_id = tr.ebs_template_id
        ORDER BY
            it.item_type_code,
            NVL(tr.rule_priority, 999999),
            tr.division_value,
            tr.business_unit_value,
            tr.expense_item_flag
    )
    LOOP
        p('INSERT INTO ops.adre_inv_item_template_rule');
        p('(item_type_id, ebs_organization_id, division_value, business_unit_value,');
        p(' expense_item_flag, ebs_template_id, rule_status, rule_notes, rule_priority,');
        p(' active_flag, effective_start_date, effective_end_date,');
        p(' created_by, creation_date, last_updated_by, last_update_date, last_update_login)');
        p('SELECT');
        p('       (SELECT t.item_type_id');
        p('          FROM ops.adre_inv_item_type t');
        p('         WHERE UPPER(TRIM(t.item_type_code)) = UPPER(TRIM(' ||
          f_q(r.item_type_code) || '))),');

        IF r.organization_code IS NULL THEN
            p('       NULL,');
        ELSE
            p('       (SELECT o.organization_id');
            p('          FROM apps.org_organization_definitions o');
            p('         WHERE UPPER(TRIM(o.organization_code)) = UPPER(TRIM(' ||
              f_q(r.organization_code) || '))),');
        END IF;

        p('       ' || f_q(r.division_value) || ',');
        p('       ' || f_q(r.business_unit_value) || ',');
        p('       ' || f_q(r.expense_item_flag) || ',');

        IF r.template_name IS NULL THEN
            p('       NULL,');
        ELSE
            p('       (SELECT MIN(t.template_id)');
            p('          FROM apps.mtl_item_templates_vl t');
            p('         WHERE UPPER(TRIM(t.template_name)) = UPPER(TRIM(' ||
              f_q(r.template_name) || '))),');
        END IF;

        p('       ' || f_q(r.rule_status) || ',');
        p('       ' || f_q(r.rule_notes) || ',');
        p('       ' || f_n(r.rule_priority) || ',');
        p('       ' || f_q(r.active_flag) || ',');
        p('       ' || f_d(r.effective_start_date) || ',');
        p('       ' || f_d(r.effective_end_date) || ',');
        p('       ''DEPLOYMENT'', SYSDATE, ''DEPLOYMENT'', SYSDATE, NULL');
        p('FROM dual');
        p('WHERE NOT EXISTS');
        p('(');
        p('    SELECT 1');
        p('    FROM ops.adre_inv_item_template_rule tr');
        p('    JOIN ops.adre_inv_item_type it');
        p('      ON it.item_type_id = tr.item_type_id');
        p('    LEFT JOIN apps.org_organization_definitions o');
        p('      ON o.organization_id = tr.ebs_organization_id');
        p('    LEFT JOIN apps.mtl_item_templates_vl mt');
        p('      ON mt.template_id = tr.ebs_template_id');
        p('    WHERE UPPER(TRIM(it.item_type_code)) = UPPER(TRIM(' ||
          f_q(r.item_type_code) || '))');

        IF r.organization_code IS NULL THEN
            p('      AND tr.ebs_organization_id IS NULL');
        ELSE
            p('      AND UPPER(TRIM(o.organization_code)) = UPPER(TRIM(' ||
              f_q(r.organization_code) || '))');
        END IF;

        IF r.division_value IS NULL THEN
            p('      AND tr.division_value IS NULL');
        ELSE
            p('      AND UPPER(TRIM(tr.division_value)) = UPPER(TRIM(' ||
              f_q(r.division_value) || '))');
        END IF;

        IF r.business_unit_value IS NULL THEN
            p('      AND tr.business_unit_value IS NULL');
        ELSE
            p('      AND UPPER(TRIM(tr.business_unit_value)) = UPPER(TRIM(' ||
              f_q(r.business_unit_value) || '))');
        END IF;

        IF r.expense_item_flag IS NULL THEN
            p('      AND tr.expense_item_flag IS NULL');
        ELSE
            p('      AND UPPER(TRIM(tr.expense_item_flag)) = UPPER(TRIM(' ||
              f_q(r.expense_item_flag) || '))');
        END IF;

        IF r.template_name IS NULL THEN
            p('      AND tr.ebs_template_id IS NULL');
        ELSE
            p('      AND UPPER(TRIM(mt.template_name)) = UPPER(TRIM(' ||
              f_q(r.template_name) || '))');
        END IF;

        p(');');
        p('');
    END LOOP;

    p('COMMIT;');
    p('');
    p('-- Validation');
    p('SELECT COUNT(*) AS template_rule_count FROM ops.adre_inv_item_template_rule;');
    p('');
    p('-- =====================================================================');
    p('-- END GENERATED PRODUCTION SEED: OPS.ADRE_INV_ITEM_TEMPLATE_RULE');
    p('-- =====================================================================');
END;
/
