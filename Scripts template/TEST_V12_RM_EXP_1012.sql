-- =====================================================================
-- JCALZADILLA - 31.08.2026 - START CHANGE
-- VERSION:
--   V12-RM-EXP-20260831-01
--
-- Purpose:
-- Execute and verify the first RAW_MATERIAL_ITEM test using the
-- ADRE_CREATE_INV_ITEM V6 package body.
--
-- Test:
--   ITEM_REQUEST_ID = 12
--   ITEM_NUMBER     = MH-94904-1012
--   Item Type       = RAW_MATERIAL_ITEM
--   Expense Item    = Y
--   Reference Item  = LS-12298-0
--   Expected Rule   = Expense Item = Y -> EXPENSE GR
--
-- Confirmed test profile:
--   Primary UOM     = G
--   Item Status     = Lab Sample
--   Engineering     = Y
--   HIMS            = 000
--   Price per UOM   = 0.001
--   Lead Time Days  = 2
--
-- Rules:
--   - This is the ONLY script for V12.
--   - This script is rerunnable.
--   - If Request 12 already exists exactly, staging is preserved.
--   - If Request 12 is already PROCESSED, package execution is skipped.
--   - TARGET EBS_TEMPLATE_ID is NOT supplied by this test.
--   - ADRE_CREATE_INV_ITEM must resolve the TARGET Template Rule.
--   - No EBS Organization ID is hard-coded.
--   - No EBS Template ID is hard-coded.
--   - No EBS Category Set ID is hard-coded.
--   - No EBS Category ID is hard-coded.
--   - No EBS Inventory Item ID is hard-coded.
--   - Raw Material Categories are copied dynamically from the confirmed
--     Oracle EBS reference Item LS-12298-0 according to Category control
--     level: MASTER/ITEM -> MASTER, ORGANIZATION -> TARGET.
--   - No direct Oracle EBS Item Attribute update is performed here.
--   - V6 mappings under test:
--       ENGINEERING_ITEM_FLAG -> ENG_ITEM_FLAG
--       HIMS                  -> ATTRIBUTE14
--       PRICE_PER_UOM         -> LIST_PRICE_PER_UNIT
--       LEAD_TIME_DAYS        -> ATTRIBUTE15
--   - EXPENSE_ITEM_FLAG remains a Template Rule input only.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- STEP 1
-- Preflight and stage Request 12 only when it does not already exist.
-- =====================================================================

DECLARE

    c_source_request_id
        CONSTANT NUMBER := 11;

    c_new_request_id
        CONSTANT NUMBER := 12;

    c_new_request_number
        CONSTANT VARCHAR2(100) :=
            'TEST-RM-EXP-MH-94904-1012-GRI-001';

    c_new_item_number
        CONSTANT VARCHAR2(100) :=
            'MH-94904-1012';

    c_reference_item_number
        CONSTANT VARCHAR2(100) :=
            'LS-12298-0';

    c_item_type_code
        CONSTANT VARCHAR2(100) :=
            'RAW_MATERIAL_ITEM';

    c_expected_target_template
        CONSTANT VARCHAR2(240) :=
            'EXPENSE GR';

    c_expected_primary_uom
        CONSTANT VARCHAR2(30) :=
            'G';

    c_expected_item_status
        CONSTANT VARCHAR2(80) :=
            'Lab Sample';

    c_engineering_item_flag
        CONSTANT VARCHAR2(1) :=
            'Y';

    c_hims
        CONSTANT VARCHAR2(30) :=
            '000';

    c_expense_item_flag
        CONSTANT VARCHAR2(1) :=
            'Y';

    c_price_per_uom
        CONSTANT NUMBER :=
            0.001;

    c_lead_time_days
        CONSTANT NUMBER :=
            2;

    l_exact_request_count
        NUMBER;

    l_conflict_count
        NUMBER;

    l_count
        NUMBER;

    l_package_valid_count
        NUMBER;

    l_item_type_id
        NUMBER;

    l_master_org_id
        NUMBER;

    l_target_org_id
        NUMBER;

    l_master_template_id
        NUMBER;

    l_master_template_name
        VARCHAR2(240);

    l_master_request_org_id
        NUMBER;

    l_target_request_org_id
        NUMBER;

    l_reference_item_id
        NUMBER;

    l_reference_primary_uom
        VARCHAR2(30);

    l_reference_item_status
        VARCHAR2(80);

    l_reference_item_type
        VARCHAR2(80);

    l_reference_price
        NUMBER;

    l_reference_hims
        VARCHAR2(4000);

    l_reference_lead_time
        VARCHAR2(4000);

    l_rule_count
        NUMBER;

    l_rule_id
        NUMBER;

    l_rule_template_name
        VARCHAR2(240);

    l_rule_template_id
        NUMBER;

    l_reference_category_count
        NUMBER;

    l_inserted_category_count
        NUMBER;

    l_inserted_attribute_count
        NUMBER;

    l_distinct_attribute_count
        NUMBER;

    l_missing_required_count
        NUMBER;

BEGIN

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        'TEST V12 / RM-EXP / MH-94904-1012 - PREFLIGHT/STAGING'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );


    -- =============================================================
    -- V6 package body must be VALID before any staging is created.
    -- =============================================================

    SELECT COUNT(*)
    INTO l_package_valid_count
    FROM all_objects
    WHERE owner       = 'APPS'
      AND object_name = 'ADRE_CREATE_INV_ITEM'
      AND object_type = 'PACKAGE BODY'
      AND status      = 'VALID';


    IF l_package_valid_count <> 1 THEN

        RAISE_APPLICATION_ERROR
        (
            -20700,
            'APPS.ADRE_CREATE_INV_ITEM PACKAGE BODY is not VALID.'
        );

    END IF;


    -- =============================================================
    -- Preserve an already-staged exact V12 Request.
    -- =============================================================

    SELECT COUNT(*)
    INTO l_exact_request_count
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_new_request_id
      AND UPPER(TRIM(item_number)) =
          UPPER(TRIM(c_new_item_number));


    IF l_exact_request_count = 1 THEN

        DBMS_OUTPUT.PUT_LINE
        (
            'Request 12 / MH-94904-1012 already exists in OPS.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Staging skipped. Existing V12 data is preserved.'
        );

    ELSE

        -- =============================================================
        -- Prevent Request ID / Item Number collision.
        -- =============================================================

        SELECT COUNT(*)
        INTO l_conflict_count
        FROM ops.adre_inv_item_request
        WHERE item_request_id = c_new_request_id
           OR UPPER(TRIM(item_number)) =
              UPPER(TRIM(c_new_item_number));


        IF l_conflict_count > 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20701,
                'Request ID 12 or Item MH-94904-1012 is already used by a different OPS Request.'
            );

        END IF;


        -- =============================================================
        -- The proven Request 11 is used only as the structural header
        -- source. Raw Material Item Type, profile, Categories and
        -- Attributes are rebuilt explicitly below.
        -- =============================================================

        SELECT COUNT(*)
        INTO l_count
        FROM ops.adre_inv_item_request
        WHERE item_request_id = c_source_request_id;


        IF l_count <> 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20702,
                'Source Request 11 was not found.'
            );

        END IF;


        -- =============================================================
        -- Resolve RAW_MATERIAL_ITEM dynamically.
        -- =============================================================

        SELECT
            COUNT(*),
            MIN(item_type_id)
        INTO
            l_count,
            l_item_type_id
        FROM ops.adre_inv_item_type
        WHERE UPPER(TRIM(item_type_code)) =
              UPPER(TRIM(c_item_type_code));


        IF l_count <> 1
           OR l_item_type_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20703,
                'RAW_MATERIAL_ITEM could not be resolved uniquely.'
            );

        END IF;


        -- =============================================================
        -- Resolve MASTER/TARGET Organizations and MASTER Template from
        -- the proven Request 11. No technical ID is hard-coded.
        -- =============================================================

        SELECT
            MAX(CASE WHEN ro.organization_role = 'MASTER' THEN ro.ebs_organization_id END),
            MAX(CASE WHEN ro.organization_role = 'TARGET' THEN ro.ebs_organization_id END),
            MAX(CASE WHEN ro.organization_role = 'MASTER' THEN ro.ebs_template_id END)
        INTO
            l_master_org_id,
            l_target_org_id,
            l_master_template_id
        FROM ops.adre_inv_item_request_org ro
        WHERE ro.item_request_id = c_source_request_id;


        IF l_master_org_id IS NULL
           OR l_target_org_id IS NULL
           OR l_master_template_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20704,
                'MASTER/TARGET Organization or MASTER Template could not be resolved from Request 11.'
            );

        END IF;


        SELECT template_name
        INTO l_master_template_name
        FROM apps.mtl_item_templates_vl
        WHERE template_id = l_master_template_id;


        SELECT COUNT(*)
        INTO l_count
        FROM apps.org_organization_definitions
        WHERE (organization_id = l_master_org_id AND organization_code = 'MAS')
           OR (organization_id = l_target_org_id AND organization_code = 'GRI');


        IF l_count <> 2 THEN

            RAISE_APPLICATION_ERROR
            (
                -20705,
                'Expected Request 11 Organization structure MAS MASTER / GRI TARGET.'
            );

        END IF;


        -- =============================================================
        -- Verify exactly one active Expense=Y Raw Material Rule.
        -- Division / Business Unit are intentionally not Template Rule
        -- criteria for the confirmed Raw Material rules.
        -- TARGET EBS_TEMPLATE_ID will remain NULL in staging.
        -- =============================================================

        SELECT
            COUNT(*),
            MIN(tr.item_template_rule_id),
            MIN(tr.ebs_template_id),
            MIN(t.template_name)
        INTO
            l_rule_count,
            l_rule_id,
            l_rule_template_id,
            l_rule_template_name
        FROM ops.adre_inv_item_template_rule tr
        JOIN apps.mtl_item_templates_vl t
          ON t.template_id = tr.ebs_template_id
        WHERE tr.item_type_id = l_item_type_id
          AND tr.ebs_organization_id = l_target_org_id
          AND UPPER(TRIM(tr.expense_item_flag)) =
              UPPER(TRIM(c_expense_item_flag))
          AND tr.division_value IS NULL
          AND tr.business_unit_value IS NULL
          AND tr.rule_status = 'READY'
          AND tr.active_flag = 'Y'
          AND (tr.effective_start_date IS NULL OR tr.effective_start_date <= TRUNC(SYSDATE))
          AND (tr.effective_end_date   IS NULL OR tr.effective_end_date   >= TRUNC(SYSDATE));


        IF l_rule_count <> 1
           OR l_rule_id IS NULL
           OR UPPER(TRIM(l_rule_template_name)) <>
              UPPER(TRIM(c_expected_target_template))
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20706,
                'Expected exactly one active RAW_MATERIAL_ITEM Expense=Y Rule resolving EXPENSE GR.'
            );

        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'TARGET Template Rule configuration found: RULE_ID=' ||
            TO_CHAR(l_rule_id) ||
            ', TEMPLATE=' ||
            l_rule_template_name
        );


        -- =============================================================
        -- New Item must not already exist in Oracle EBS.
        -- =============================================================

        SELECT COUNT(*)
        INTO l_count
        FROM apps.mtl_system_items_kfv
        WHERE UPPER(TRIM(concatenated_segments)) =
              UPPER(TRIM(c_new_item_number));


        IF l_count > 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20707,
                'Item MH-94904-1012 already exists in Oracle EBS without Request 12 in OPS.'
            );

        END IF;


        -- =============================================================
        -- Resolve and validate the confirmed Expense reference profile.
        -- No Inventory Item ID is hard-coded.
        -- =============================================================

        SELECT
            COUNT(*),
            MIN(kfv.inventory_item_id)
        INTO
            l_count,
            l_reference_item_id
        FROM apps.mtl_system_items_kfv kfv
        WHERE kfv.organization_id = l_target_org_id
          AND UPPER(TRIM(kfv.concatenated_segments)) =
              UPPER(TRIM(c_reference_item_number));


        IF l_count <> 1
           OR l_reference_item_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20708,
                'Reference Item LS-12298-0 could not be resolved uniquely in TARGET Organization.'
            );

        END IF;


        SELECT
            msi.primary_uom_code,
            msi.inventory_item_status_code,
            msi.item_type,
            msi.list_price_per_unit,
            msi.attribute14,
            msi.attribute15
        INTO
            l_reference_primary_uom,
            l_reference_item_status,
            l_reference_item_type,
            l_reference_price,
            l_reference_hims,
            l_reference_lead_time
        FROM apps.mtl_system_items_b msi
        WHERE msi.inventory_item_id = l_reference_item_id
          AND msi.organization_id   = l_target_org_id;


        IF UPPER(TRIM(l_reference_primary_uom)) <>
           UPPER(TRIM(c_expected_primary_uom))
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20709,
                'Expense reference Primary UOM changed. Expected G; actual=' ||
                NVL(l_reference_primary_uom, 'NULL')
            );
        END IF;


        IF UPPER(TRIM(l_reference_item_status)) <>
           UPPER(TRIM(c_expected_item_status))
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20710,
                'Expense reference Item Status changed. Expected Lab Sample; actual=' ||
                NVL(l_reference_item_status, 'NULL')
            );
        END IF;


        IF ABS(NVL(l_reference_price, -999999) - c_price_per_uom) > 0.0000001 THEN
            RAISE_APPLICATION_ERROR
            (
                -20711,
                'Expense reference Price changed. Expected 0.001; actual=' ||
                NVL(TO_CHAR(l_reference_price), 'NULL')
            );
        END IF;


        IF NVL(TRIM(l_reference_hims), '#NULL#') <> c_hims THEN
            RAISE_APPLICATION_ERROR
            (
                -20712,
                'Expense reference HIMS changed. Expected 000; actual=' ||
                NVL(l_reference_hims, 'NULL')
            );
        END IF;


        IF NVL(TRIM(l_reference_lead_time), '#NULL#') <>
           TO_CHAR(c_lead_time_days, 'TM9')
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20713,
                'Expense reference Lead Time changed. Expected 2; actual=' ||
                NVL(l_reference_lead_time, 'NULL')
            );
        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Expense reference validated: ' ||
            c_reference_item_number ||
            ', UOM=' || l_reference_primary_uom ||
            ', STATUS=' || l_reference_item_status ||
            ', ITEM_TYPE=' || NVL(l_reference_item_type, 'NULL') ||
            ', PRICE=' || TO_CHAR(l_reference_price) ||
            ', HIMS=' || l_reference_hims ||
            ', LEAD_TIME=' || l_reference_lead_time
        );


        -- =============================================================
        -- Clone Request header structure from Request 11, but replace all
        -- Raw Material-specific business values.
        -- =============================================================

        INSERT INTO ops.adre_inv_item_request
        (
            item_request_id,
            request_number,
            request_status,
            item_type_id,
            base_part_number,
            item_number,
            part_status,
            item_description,
            long_description,
            primary_uom_code,
            item_status_code,
            initiator,
            requested_creation_date,
            forecast_flag,
            ebs_submit_date,
            api_return_status,
            api_message_count,
            api_message_text,
            api_processed_date,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            last_update_login
        )
        SELECT
            c_new_request_id,
            c_new_request_number,
            'READY',
            l_item_type_id,
            base_part_number,
            c_new_item_number,
            part_status,
            'Raw Material - EXPENSE GR validation test based on LS-12298-0',
            'Raw Material - EXPENSE GR validation test based on LS-12298-0',
            l_reference_primary_uom,
            l_reference_item_status,
            initiator,
            SYSDATE,
            forecast_flag,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            created_by,
            SYSDATE,
            'JCALZADILLA',
            SYSDATE,
            last_update_login
        FROM ops.adre_inv_item_request
        WHERE item_request_id = c_source_request_id;


        IF SQL%ROWCOUNT <> 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20714,
                'Request 12 header could not be created from the Request 11 structure.'
            );

        END IF;


        -- =============================================================
        -- Create MASTER/TARGET Request Organizations from Request 11.
        -- TARGET Template is deliberately NULL.
        -- =============================================================

        INSERT INTO ops.adre_inv_item_request_org
        (
            item_request_id,
            ebs_organization_id,
            organization_role,
            ebs_template_id,
            assignment_status,
            ebs_inventory_item_id,
            api_return_status,
            api_message_count,
            api_message_text,
            api_processed_date,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            last_update_login
        )
        SELECT
            c_new_request_id,
            ebs_organization_id,
            organization_role,
            CASE
                WHEN organization_role = 'TARGET' THEN NULL
                ELSE ebs_template_id
            END,
            'READY',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            created_by,
            SYSDATE,
            'JCALZADILLA',
            SYSDATE,
            last_update_login
        FROM ops.adre_inv_item_request_org
        WHERE item_request_id = c_source_request_id;


        IF SQL%ROWCOUNT <> 2 THEN

            RAISE_APPLICATION_ERROR
            (
                -20715,
                'Expected exactly 2 Request Organization rows.'
            );

        END IF;


        SELECT request_org_id
        INTO l_master_request_org_id
        FROM ops.adre_inv_item_request_org
        WHERE item_request_id = c_new_request_id
          AND organization_role = 'MASTER';


        SELECT request_org_id
        INTO l_target_request_org_id
        FROM ops.adre_inv_item_request_org
        WHERE item_request_id = c_new_request_id
          AND organization_role = 'TARGET';


        SELECT COUNT(*)
        INTO l_count
        FROM ops.adre_inv_item_request_org
        WHERE item_request_id = c_new_request_id
          AND organization_role = 'TARGET'
          AND ebs_template_id IS NOT NULL;


        IF l_count <> 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20716,
                'TARGET EBS_TEMPLATE_ID must be NULL before package execution.'
            );

        END IF;


        -- =============================================================
        -- Build Categories dynamically from LS-12298-0 in GRI.
        --
        -- Control Level 1 (MASTER/ITEM) -> new MASTER request_org_id
        -- Control Level 2 (ORGANIZATION) -> new TARGET request_org_id
        -- =============================================================

        SELECT COUNT(*)
        INTO l_reference_category_count
        FROM
        (
            SELECT DISTINCT
                mic.category_set_id,
                mic.category_id,
                csb.control_level
            FROM apps.mtl_item_categories mic
            JOIN apps.mtl_category_sets_b csb
              ON csb.category_set_id = mic.category_set_id
            WHERE mic.inventory_item_id = l_reference_item_id
              AND mic.organization_id   = l_target_org_id
              AND csb.control_level IN (1, 2)
        );


        INSERT INTO ops.adre_inv_item_category
        (
            request_org_id,
            ebs_category_set_id,
            ebs_category_id,
            category_value,
            assignment_status,
            api_return_status,
            api_message_count,
            api_message_text,
            api_processed_date,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            last_update_login
        )
        SELECT DISTINCT
            CASE csb.control_level
                WHEN 1 THEN l_master_request_org_id
                WHEN 2 THEN l_target_request_org_id
            END,
            mic.category_set_id,
            mic.category_id,
            mck.concatenated_segments,
            'READY',
            NULL,
            NULL,
            NULL,
            NULL,
            'JCALZADILLA',
            SYSDATE,
            'JCALZADILLA',
            SYSDATE,
            NULL
        FROM apps.mtl_item_categories mic
        JOIN apps.mtl_category_sets_b csb
          ON csb.category_set_id = mic.category_set_id
        JOIN apps.mtl_categories_kfv mck
          ON mck.category_id = mic.category_id
        WHERE mic.inventory_item_id = l_reference_item_id
          AND mic.organization_id   = l_target_org_id
          AND csb.control_level IN (1, 2);


        l_inserted_category_count := SQL%ROWCOUNT;


        IF l_inserted_category_count <> l_reference_category_count
           OR l_inserted_category_count = 0
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20717,
                'Raw Material Category staging count does not match the Expense reference Item.'
            );

        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Category rows staged from Expense reference=' ||
            TO_CHAR(l_inserted_category_count)
        );


        -- =============================================================
        -- Stage only the five confirmed RAW_MATERIAL_ITEM Attributes.
        -- Organization placement comes from ADRE_INV_ITEM_TYPE_ATTR.
        -- =============================================================

        INSERT INTO ops.adre_inv_item_attr_value
        (
            request_org_id,
            item_attribute_id,
            attribute_char_value,
            attribute_number_value,
            attribute_date_value,
            value_uom_code,
            value_status,
            api_return_status,
            api_message_count,
            api_message_text,
            api_processed_date,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            last_update_login
        )
        SELECT
            ro.request_org_id,
            a.item_attribute_id,
            CASE a.attribute_code
                WHEN 'ENGINEERING_ITEM_FLAG' THEN c_engineering_item_flag
                WHEN 'HIMS'                  THEN c_hims
                WHEN 'EXPENSE_ITEM_FLAG'     THEN c_expense_item_flag
                ELSE NULL
            END,
            CASE a.attribute_code
                WHEN 'PRICE_PER_UOM'  THEN c_price_per_uom
                WHEN 'LEAD_TIME_DAYS' THEN c_lead_time_days
                ELSE NULL
            END,
            NULL,
            NULL,
            'READY',
            NULL,
            NULL,
            NULL,
            NULL,
            'JCALZADILLA',
            SYSDATE,
            'JCALZADILLA',
            SYSDATE,
            NULL
        FROM ops.adre_inv_item_type_attr ta
        JOIN ops.adre_inv_item_attribute a
          ON a.item_attribute_id = ta.item_attribute_id
        JOIN ops.adre_inv_item_request_org ro
          ON ro.item_request_id = c_new_request_id
         AND
         (
                ta.organization_scope = ro.organization_role
             OR ta.organization_scope = 'BOTH'
         )
        WHERE ta.item_type_id = l_item_type_id
          AND ta.active_flag = 'Y'
          AND a.attribute_code IN
              (
                  'ENGINEERING_ITEM_FLAG',
                  'HIMS',
                  'EXPENSE_ITEM_FLAG',
                  'PRICE_PER_UOM',
                  'LEAD_TIME_DAYS'
              );


        l_inserted_attribute_count := SQL%ROWCOUNT;


        SELECT COUNT(DISTINCT a.attribute_code)
        INTO l_distinct_attribute_count
        FROM ops.adre_inv_item_attr_value av
        JOIN ops.adre_inv_item_request_org ro
          ON ro.request_org_id = av.request_org_id
        JOIN ops.adre_inv_item_attribute a
          ON a.item_attribute_id = av.item_attribute_id
        WHERE ro.item_request_id = c_new_request_id
          AND a.attribute_code IN
              (
                  'ENGINEERING_ITEM_FLAG',
                  'HIMS',
                  'EXPENSE_ITEM_FLAG',
                  'PRICE_PER_UOM',
                  'LEAD_TIME_DAYS'
              );


        IF l_distinct_attribute_count <> 5 THEN

            RAISE_APPLICATION_ERROR
            (
                -20718,
                'Expected all 5 confirmed Raw Material Attributes to be staged. DISTINCT_COUNT=' ||
                TO_CHAR(l_distinct_attribute_count)
            );

        END IF;


        -- =============================================================
        -- Fail before EBS processing if the current Raw Material
        -- configuration contains any required active Attribute without a
        -- READY value for its configured Organization scope.
        -- =============================================================

        SELECT COUNT(*)
        INTO l_missing_required_count
        FROM ops.adre_inv_item_type_attr ta
        JOIN ops.adre_inv_item_attribute a
          ON a.item_attribute_id = ta.item_attribute_id
        JOIN ops.adre_inv_item_request_org ro
          ON ro.item_request_id = c_new_request_id
         AND
         (
                ta.organization_scope = ro.organization_role
             OR ta.organization_scope = 'BOTH'
         )
        LEFT JOIN ops.adre_inv_item_attr_value av
          ON av.request_org_id    = ro.request_org_id
         AND av.item_attribute_id = ta.item_attribute_id
        WHERE ta.item_type_id = l_item_type_id
          AND ta.active_flag = 'Y'
          AND ta.required_flag = 'Y'
          AND
          (
                 av.item_attr_value_id IS NULL
              OR NVL(av.value_status, 'DRAFT') <> 'READY'
              OR
                 (
                     av.attribute_char_value    IS NULL
                 AND av.attribute_number_value IS NULL
                 AND av.attribute_date_value   IS NULL
                 )
          );


        IF l_missing_required_count > 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20719,
                'Current RAW_MATERIAL_ITEM configuration contains required Attributes not supplied by V12. MISSING_COUNT=' ||
                TO_CHAR(l_missing_required_count)
            );

        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Raw Material Attribute rows staged=' ||
            TO_CHAR(l_inserted_attribute_count) ||
            '; distinct confirmed Attributes=5.'
        );


        COMMIT;


        DBMS_OUTPUT.PUT_LINE
        (
            'Request 12 staged successfully.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'TARGET EBS_TEMPLATE_ID is NULL before package execution.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Expected package resolution: Expense Item Y -> ' ||
            c_expected_target_template
        );

    END IF;


EXCEPTION
    WHEN OTHERS THEN

        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE
        (
            'V12 STAGING/PREFLIGHT ERROR=' ||
            SQLERRM
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'BACKTRACE=' ||
            DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
        );

        RAISE;

END;
/


-- =====================================================================
-- STEP 2
-- Execute ADRE_CREATE_INV_ITEM V6 unless Request 12 is PROCESSED.
-- =====================================================================

DECLARE

    c_item_request_id
        CONSTANT NUMBER := 12;

    l_request_status
        VARCHAR2(30);

    l_return_status
        VARCHAR2(1);

    l_message
        CLOB;

BEGIN

    SELECT request_status
    INTO l_request_status
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_item_request_id;


    IF l_request_status = 'PROCESSED' THEN

        DBMS_OUTPUT.PUT_LINE
        (
            'Request 12 is already PROCESSED.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Main package execution skipped. Verification will continue.'
        );

    ELSE

        DBMS_OUTPUT.PUT_LINE
        (
            '============================================================'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'TEST V12 / RM-EXP / MH-94904-1012 - PACKAGE START'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            '============================================================'
        );


        apps.adre_create_inv_item.pcd_process_request
        (
            p_item_request_id    => c_item_request_id,
            p_validate_only_flag => 'N',
            p_user_id            => NULL,
            p_resp_id            => NULL,
            p_resp_appl_id       => NULL,
            p_commit_flag        => 'Y',
            x_return_status      => l_return_status,
            x_message            => l_message
        );


        DBMS_OUTPUT.PUT_LINE
        (
            'RETURN_STATUS=' ||
            NVL(l_return_status, 'NULL')
        );

        DBMS_OUTPUT.PUT_LINE
        (
            '------------------------------------------------------------'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            DBMS_LOB.SUBSTR
            (
                l_message,
                32000,
                1
            )
        );

        DBMS_OUTPUT.PUT_LINE
        (
            '------------------------------------------------------------'
        );


        IF NVL(l_return_status, 'E') <> 'S' THEN

            RAISE_APPLICATION_ERROR
            (
                -20720,
                'ADRE_CREATE_INV_ITEM returned a non-success status for Request 12.'
            );

        END IF;

    END IF;

END;
/


-- =====================================================================
-- STEP 3
-- APEX / Oracle EBS Item summary.
-- The SELECT is intentionally on one physical line for APEX SQL Scripts.
-- =====================================================================

SELECT r.item_request_id, r.request_number, r.item_number, r.request_status, r.api_return_status AS request_api_status, ro.organization_role, ro.ebs_organization_id, ood.organization_code, ro.ebs_template_id, t.template_name, ro.ebs_inventory_item_id, ro.assignment_status, ro.api_return_status AS org_api_status, kfv.concatenated_segments AS ebs_item_number, msi.primary_uom_code, msi.inventory_item_status_code, msi.item_type, msi.eng_item_flag, msi.attribute14 AS hims_attribute14, msi.list_price_per_unit, msi.attribute15 AS lead_time_attribute15, msi.planner_code, msi.inventory_asset_flag, msi.inventory_item_flag, msi.costing_enabled_flag FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl t ON t.template_id = ro.ebs_template_id LEFT JOIN apps.mtl_system_items_b msi ON msi.inventory_item_id = ro.ebs_inventory_item_id AND msi.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_system_items_kfv kfv ON kfv.inventory_item_id = msi.inventory_item_id AND kfv.organization_id = msi.organization_id WHERE r.item_request_id = 12 ORDER BY CASE ro.organization_role WHEN 'MASTER' THEN 1 WHEN 'TARGET' THEN 2 ELSE 3 END;


-- =====================================================================
-- STEP 4
-- API execution evidence.
-- The SELECT is intentionally on one physical line.
-- =====================================================================

SELECT item_api_log_id, execution_id, request_org_id, process_name, api_name, entity_type, entity_id, process_status, api_return_status, api_message_count, message_text FROM ops.adre_inv_item_api_log WHERE item_request_id = 12 ORDER BY item_api_log_id;


-- =====================================================================
-- STEP 5
-- Consolidated V12 validation output.
-- The compound SELECT is intentionally stored on one physical line.
-- =====================================================================

SELECT 'ITEM_ORGANIZATION' AS validation_group, ro.organization_role AS organization_role, ood.organization_code AS organization_code, r.item_number AS item_number, 'ORGANIZATION_PROCESSING' AS validation_name, ro.assignment_status || ' / ' || NVL(ro.api_return_status, 'NULL') AS source_value, NVL(kfv.concatenated_segments, 'NOT FOUND') || ' / ' || NVL(t.template_name, 'NO TEMPLATE') AS ebs_value, CASE WHEN ro.assignment_status = 'PROCESSED' AND ro.api_return_status = 'S' AND UPPER(TRIM(kfv.concatenated_segments)) = UPPER(TRIM(r.item_number)) THEN 'PASS' ELSE 'DIFFERENT' END AS validation_status, 'APEX Organization processing versus Oracle EBS Item existence and persisted Template.' AS notes FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl t ON t.template_id = ro.ebs_template_id LEFT JOIN apps.mtl_system_items_kfv kfv ON kfv.inventory_item_id = ro.ebs_inventory_item_id AND kfv.organization_id = ro.ebs_organization_id WHERE r.item_request_id = 12 UNION ALL SELECT 'TEMPLATE_RULE', ro.organization_role, ood.organization_code, r.item_number, 'RESOLVE_TARGET_TEMPLATE', 'EXPENSE_ITEM_FLAG=' || NVL(tr.expense_item_flag, 'NULL') || ' -> ' || expected_template.template_name, NVL(actual_template.template_name, 'NOT RESOLVED'), CASE WHEN lg.process_status = 'SUCCESS' AND lg.api_return_status = 'S' AND ro.ebs_template_id = tr.ebs_template_id AND UPPER(TRIM(tr.expense_item_flag)) = 'Y' AND UPPER(TRIM(expected_template.template_name)) = 'EXPENSE GR' THEN 'PASS' ELSE 'DIFFERENT' END, 'Raw Material Expense Rule selected by ADRE_CREATE_INV_ITEM versus Template persisted on TARGET.' FROM ops.adre_inv_item_api_log lg JOIN ops.adre_inv_item_request r ON r.item_request_id = lg.item_request_id JOIN ops.adre_inv_item_request_org ro ON ro.request_org_id = lg.request_org_id JOIN ops.adre_inv_item_template_rule tr ON tr.item_template_rule_id = lg.entity_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl expected_template ON expected_template.template_id = tr.ebs_template_id LEFT JOIN apps.mtl_item_templates_vl actual_template ON actual_template.template_id = ro.ebs_template_id WHERE lg.item_request_id = 12 AND lg.process_name = 'RESOLVE_TARGET_TEMPLATE' AND lg.item_api_log_id = (SELECT MAX(lg2.item_api_log_id) FROM ops.adre_inv_item_api_log lg2 WHERE lg2.item_request_id = 12 AND lg2.process_name = 'RESOLVE_TARGET_TEMPLATE') UNION ALL SELECT 'RAW_MATERIAL_ATTRIBUTE', ro.organization_role, ood.organization_code, r.item_number, a.attribute_code, CASE WHEN av.attribute_char_value IS NOT NULL THEN av.attribute_char_value WHEN av.attribute_number_value IS NOT NULL THEN TO_CHAR(av.attribute_number_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') WHEN av.attribute_date_value IS NOT NULL THEN TO_CHAR(av.attribute_date_value, 'YYYY-MM-DD') END, CASE a.attribute_code WHEN 'ENGINEERING_ITEM_FLAG' THEN master_msi.eng_item_flag WHEN 'HIMS' THEN master_msi.attribute14 WHEN 'EXPENSE_ITEM_FLAG' THEN NVL(rule_tr.expense_item_flag, 'NO RULE') WHEN 'PRICE_PER_UOM' THEN TO_CHAR(target_msi.list_price_per_unit, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') WHEN 'LEAD_TIME_DAYS' THEN target_msi.attribute15 ELSE 'NOT MAPPED' END, CASE a.attribute_code WHEN 'ENGINEERING_ITEM_FLAG' THEN CASE WHEN UPPER(TRIM(av.attribute_char_value)) = UPPER(TRIM(master_msi.eng_item_flag)) THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'HIMS' THEN CASE WHEN TRIM(av.attribute_char_value) = TRIM(master_msi.attribute14) THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'EXPENSE_ITEM_FLAG' THEN CASE WHEN UPPER(TRIM(av.attribute_char_value)) = UPPER(TRIM(rule_tr.expense_item_flag)) AND UPPER(TRIM(actual_template.template_name)) = 'EXPENSE GR' THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'PRICE_PER_UOM' THEN CASE WHEN ABS(NVL(av.attribute_number_value, -999999) - NVL(target_msi.list_price_per_unit, -888888)) < 0.0000001 THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'LEAD_TIME_DAYS' THEN CASE WHEN TO_CHAR(av.attribute_number_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') = TRIM(target_msi.attribute15) THEN 'MATCH' ELSE 'DIFFERENT' END ELSE 'NOT MAPPED' END, CASE a.attribute_code WHEN 'ENGINEERING_ITEM_FLAG' THEN 'V6 explicit ENGINEERING_ITEM_FLAG -> MASTER ENG_ITEM_FLAG.' WHEN 'HIMS' THEN 'V6 HIMS -> MASTER ATTRIBUTE14.' WHEN 'EXPENSE_ITEM_FLAG' THEN 'Template Rule input only; expected Rule Expense=Y -> EXPENSE GR.' WHEN 'PRICE_PER_UOM' THEN 'V6 PRICE_PER_UOM -> TARGET LIST_PRICE_PER_UNIT.' WHEN 'LEAD_TIME_DAYS' THEN 'V6 LEAD_TIME_DAYS -> TARGET ATTRIBUTE15.' ELSE 'No V12 mapping.' END FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id JOIN ops.adre_inv_item_attr_value av ON av.request_org_id = ro.request_org_id JOIN ops.adre_inv_item_attribute a ON a.item_attribute_id = av.item_attribute_id JOIN ops.adre_inv_item_request_org master_ro ON master_ro.item_request_id = r.item_request_id AND master_ro.organization_role = 'MASTER' JOIN apps.mtl_system_items_b master_msi ON master_msi.inventory_item_id = master_ro.ebs_inventory_item_id AND master_msi.organization_id = master_ro.ebs_organization_id JOIN ops.adre_inv_item_request_org target_ro ON target_ro.item_request_id = r.item_request_id AND target_ro.organization_role = 'TARGET' JOIN apps.mtl_system_items_b target_msi ON target_msi.inventory_item_id = target_ro.ebs_inventory_item_id AND target_msi.organization_id = target_ro.ebs_organization_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl actual_template ON actual_template.template_id = target_ro.ebs_template_id LEFT JOIN ops.adre_inv_item_api_log rule_lg ON rule_lg.item_request_id = r.item_request_id AND rule_lg.process_name = 'RESOLVE_TARGET_TEMPLATE' AND rule_lg.process_status = 'SUCCESS' AND rule_lg.item_api_log_id = (SELECT MAX(lg3.item_api_log_id) FROM ops.adre_inv_item_api_log lg3 WHERE lg3.item_request_id = r.item_request_id AND lg3.process_name = 'RESOLVE_TARGET_TEMPLATE' AND lg3.process_status = 'SUCCESS') LEFT JOIN ops.adre_inv_item_template_rule rule_tr ON rule_tr.item_template_rule_id = rule_lg.entity_id WHERE r.item_request_id = 12 AND a.attribute_code IN ('ENGINEERING_ITEM_FLAG','HIMS','EXPENSE_ITEM_FLAG','PRICE_PER_UOM','LEAD_TIME_DAYS') UNION ALL SELECT 'REFERENCE_PROFILE', target_ro.organization_role, target_ood.organization_code, r.item_number, 'PRIMARY_UOM', ref_msi.primary_uom_code, target_msi.primary_uom_code, CASE WHEN UPPER(TRIM(ref_msi.primary_uom_code)) = UPPER(TRIM(target_msi.primary_uom_code)) THEN 'MATCH' ELSE 'DIFFERENT' END, 'V12 uses the confirmed LS-12298-0 Expense Raw Material profile.' FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org target_ro ON target_ro.item_request_id = r.item_request_id AND target_ro.organization_role = 'TARGET' JOIN apps.org_organization_definitions target_ood ON target_ood.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_b target_msi ON target_msi.inventory_item_id = target_ro.ebs_inventory_item_id AND target_msi.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_kfv ref_kfv ON UPPER(TRIM(ref_kfv.concatenated_segments)) = 'LS-12298-0' AND ref_kfv.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_b ref_msi ON ref_msi.inventory_item_id = ref_kfv.inventory_item_id AND ref_msi.organization_id = ref_kfv.organization_id WHERE r.item_request_id = 12 UNION ALL SELECT 'REFERENCE_PROFILE', target_ro.organization_role, target_ood.organization_code, r.item_number, 'ITEM_STATUS', ref_msi.inventory_item_status_code, target_msi.inventory_item_status_code, CASE WHEN UPPER(TRIM(ref_msi.inventory_item_status_code)) = UPPER(TRIM(target_msi.inventory_item_status_code)) THEN 'MATCH' ELSE 'DIFFERENT' END, 'V12 uses the confirmed LS-12298-0 Expense Raw Material profile.' FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org target_ro ON target_ro.item_request_id = r.item_request_id AND target_ro.organization_role = 'TARGET' JOIN apps.org_organization_definitions target_ood ON target_ood.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_b target_msi ON target_msi.inventory_item_id = target_ro.ebs_inventory_item_id AND target_msi.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_kfv ref_kfv ON UPPER(TRIM(ref_kfv.concatenated_segments)) = 'LS-12298-0' AND ref_kfv.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_b ref_msi ON ref_msi.inventory_item_id = ref_kfv.inventory_item_id AND ref_msi.organization_id = ref_kfv.organization_id WHERE r.item_request_id = 12 UNION ALL SELECT 'REFERENCE_PROFILE', target_ro.organization_role, target_ood.organization_code, r.item_number, 'EBS_ITEM_TYPE', NVL(ref_msi.item_type, 'NULL'), NVL(target_msi.item_type, 'NULL'), CASE WHEN NVL(UPPER(TRIM(ref_msi.item_type)), '#NULL#') = NVL(UPPER(TRIM(target_msi.item_type)), '#NULL#') THEN 'MATCH' ELSE 'DIFFERENT' END, 'Target Item Type compared with the selected Expense reference Item.' FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org target_ro ON target_ro.item_request_id = r.item_request_id AND target_ro.organization_role = 'TARGET' JOIN apps.org_organization_definitions target_ood ON target_ood.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_b target_msi ON target_msi.inventory_item_id = target_ro.ebs_inventory_item_id AND target_msi.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_kfv ref_kfv ON UPPER(TRIM(ref_kfv.concatenated_segments)) = 'LS-12298-0' AND ref_kfv.organization_id = target_ro.ebs_organization_id JOIN apps.mtl_system_items_b ref_msi ON ref_msi.inventory_item_id = ref_kfv.inventory_item_id AND ref_msi.organization_id = ref_kfv.organization_id WHERE r.item_request_id = 12 UNION ALL SELECT 'CATEGORY', ro.organization_role, ood.organization_code, r.item_number, 'CATEGORY_SET_' || TO_CHAR(cat.ebs_category_set_id), cat.category_value, NVL(mck.concatenated_segments, 'NOT ASSIGNED'), CASE WHEN mic.category_id = cat.ebs_category_id AND cat.assignment_status = 'PROCESSED' AND cat.api_return_status = 'S' THEN 'MATCH' ELSE 'DIFFERENT' END, 'APEX Category assignment versus final Oracle EBS Category assignment.' FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id JOIN ops.adre_inv_item_category cat ON cat.request_org_id = ro.request_org_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_categories mic ON mic.inventory_item_id = ro.ebs_inventory_item_id AND mic.organization_id = ro.ebs_organization_id AND mic.category_set_id = cat.ebs_category_set_id AND mic.category_id = cat.ebs_category_id LEFT JOIN apps.mtl_categories_kfv mck ON mck.category_id = mic.category_id WHERE r.item_request_id = 12 UNION ALL SELECT 'API_LOG', NVL(ro.organization_role, 'REQUEST'), ood.organization_code, r.item_number, lg.process_name, NVL(lg.api_name, 'INTERNAL'), lg.process_status || ' / ' || NVL(lg.api_return_status, 'NULL'), CASE WHEN lg.process_status = 'SUCCESS' AND lg.api_return_status = 'S' THEN 'PASS' ELSE 'DIFFERENT' END, DBMS_LOB.SUBSTR(lg.message_text, 1000, 1) FROM ops.adre_inv_item_api_log lg JOIN ops.adre_inv_item_request r ON r.item_request_id = lg.item_request_id LEFT JOIN ops.adre_inv_item_request_org ro ON ro.request_org_id = lg.request_org_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id WHERE lg.item_request_id = 12 ORDER BY 1, 2, 5;


-- =====================================================================
-- STEP 6
-- Template enabled-attribute count. This is informational only.
-- Do NOT assume EXPENSE GR has the 38 enabled Attributes observed in the
-- Adhesive Coating templates.
-- =====================================================================

SELECT t.template_name, COUNT(*) AS enabled_template_attribute_count FROM ops.adre_inv_item_request_org ro JOIN apps.mtl_item_templates_vl t ON t.template_id = ro.ebs_template_id JOIN apps.mtl_item_templ_attributes ta ON ta.template_id = ro.ebs_template_id AND ta.enabled_flag = 'Y' WHERE ro.item_request_id = 12 AND ro.organization_role = 'TARGET' GROUP BY t.template_name;

-- =====================================================================
-- JCALZADILLA - 31.08.2026 - END CHANGE
-- =====================================================================
