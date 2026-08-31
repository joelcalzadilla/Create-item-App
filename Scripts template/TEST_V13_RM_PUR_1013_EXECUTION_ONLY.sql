-- =====================================================================
-- JCALZADILLA - 31.08.2026 - START CHANGE
-- VERSION:
--   V13-RM-PUR-20260831-01
--
-- Purpose:
-- Stage and execute the second RAW_MATERIAL_ITEM test using the
-- ADRE_CREATE_INV_ITEM V7 package body.
--
-- Revision 01:
--   - Run against ADRE_CREATE_INV_ITEM V7.
--   - Validate the live Purchasing reference Lead Time in both
--     FULL_LEAD_TIME and ATTRIBUTE15. R-13140-97 has 98 in both fields.
--   - Validate the V7 business rule for new Raw Material Items:
--       LEAD_TIME_DAYS -> ATTRIBUTE15 + FULL_LEAD_TIME.
--   - Use the confirmed Purchasing reference profile and retain the guarded execution flow.
--
-- Test:
--   ITEM_REQUEST_ID = 13
--   ITEM_NUMBER     = MH-94904-1013
--   Item Type       = RAW_MATERIAL_ITEM
--   Expense Item    = N
--   Reference Item  = R-13140-97
--   Expected Rule   = Expense Item = N -> PURCHASING GR
--
-- Confirmed test profile:
--   Primary UOM     = FT
--   Item Status     = ENGINEER
--   Engineering     = Y
--   HIMS            = 000
--   Price per UOM   = 4.10
--   Lead Time Days  = 98
--
-- Rules:
--   - This is the execution script for V13 only.
--   - Post-execution verification is intentionally kept in a separate script.
--   - This script is rerunnable.
--   - If Request 13 already exists exactly, staging is preserved.
--   - If Request 13 is already PROCESSED, package execution is skipped.
--   - TARGET EBS_TEMPLATE_ID is NOT supplied by this test.
--   - ADRE_CREATE_INV_ITEM must resolve the TARGET Template Rule.
--   - No EBS Organization ID is hard-coded.
--   - No EBS Template ID is hard-coded.
--   - No EBS Category Set ID is hard-coded.
--   - No EBS Category ID is hard-coded.
--   - No EBS Inventory Item ID is hard-coded.
--   - Raw Material Categories are copied dynamically from the confirmed
--     Oracle EBS reference Item R-13140-97 according to Category control
--     level: MASTER/ITEM -> MASTER, ORGANIZATION -> TARGET.
--   - No direct Oracle EBS Item Attribute update is performed here.
--   - V7 mappings under test:
--       ENGINEERING_ITEM_FLAG -> ENG_ITEM_FLAG
--       HIMS                  -> ATTRIBUTE14
--       PRICE_PER_UOM         -> LIST_PRICE_PER_UNIT
--       LEAD_TIME_DAYS        -> ATTRIBUTE15 + FULL_LEAD_TIME
--   - EXPENSE_ITEM_FLAG remains a Template Rule input only.
--
-- Execution/verification separation:
--   This file stages and executes Request 13 / MH-94904-1013 only.
--   Verification is maintained separately in VERIFY_V13_RM_PUR_1013_MH-94904-1013.sql.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- STEP 1
-- Preflight and stage Request 13 only when it does not already exist.
-- =====================================================================

DECLARE

    c_source_request_id
        CONSTANT NUMBER := 12;

    c_new_request_id
        CONSTANT NUMBER := 13;

    c_new_request_number
        CONSTANT VARCHAR2(100) :=
            'TEST-RM-PUR-MH-94904-1013-GRI-001';

    c_new_item_number
        CONSTANT VARCHAR2(100) :=
            'MH-94904-1013';

    c_reference_item_number
        CONSTANT VARCHAR2(100) :=
            'R-13140-97';

    c_item_type_code
        CONSTANT VARCHAR2(100) :=
            'RAW_MATERIAL_ITEM';

    c_expected_target_template
        CONSTANT VARCHAR2(240) :=
            'PURCHASING GR';

    c_expected_primary_uom
        CONSTANT VARCHAR2(30) :=
            'FT';

    c_expected_item_status
        CONSTANT VARCHAR2(80) :=
            'ENGINEER';

    c_engineering_item_flag
        CONSTANT VARCHAR2(1) :=
            'Y';

    c_hims
        CONSTANT VARCHAR2(30) :=
            '000';

    c_expense_item_flag
        CONSTANT VARCHAR2(1) :=
            'N';

    c_price_per_uom
        CONSTANT NUMBER :=
            4.10;

    c_lead_time_days
        CONSTANT NUMBER :=
            98;

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

    l_reference_eng_item_flag
        VARCHAR2(1);

    l_reference_planner_code
        VARCHAR2(30);

    l_reference_price
        NUMBER;

    l_reference_hims
        VARCHAR2(4000);

    l_reference_lead_time_flex
        VARCHAR2(4000);

    l_reference_full_lead_time
        NUMBER;

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
        'TEST V13 / RM-PUR / MH-94904-1013 - PREFLIGHT/STAGING'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );


    -- =============================================================
    -- V7 package body must be VALID before any staging is created.
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
    -- Preserve an already-staged exact V13 Request.
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
            'Request 13 / MH-94904-1013 already exists in OPS.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Staging skipped. Existing V13 data is preserved.'
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
                'Request ID 13 or Item MH-94904-1013 is already used by a different OPS Request.'
            );

        END IF;


        -- =============================================================
        -- The proven Request 12 is used only as the structural header
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
                'Source Request 12 was not found.'
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
        -- the proven Request 12. No technical ID is hard-coded.
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
                'MASTER/TARGET Organization or MASTER Template could not be resolved from Request 12.'
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
                'Expected Request 12 Organization structure MAS MASTER / GRI TARGET.'
            );

        END IF;


        -- =============================================================
        -- Verify exactly one active Expense=N Raw Material Rule.
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
                'Expected exactly one active RAW_MATERIAL_ITEM Expense=N Rule resolving PURCHASING GR.'
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
                'Item MH-94904-1013 already exists in Oracle EBS without Request 13 in OPS.'
            );

        END IF;


        -- =============================================================
        -- Resolve and validate the confirmed Purchasing reference profile.
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
                'Reference Item R-13140-97 could not be resolved uniquely in TARGET Organization.'
            );

        END IF;


        SELECT
            msi.primary_uom_code,
            msi.inventory_item_status_code,
            msi.item_type,
            msi.eng_item_flag,
            msi.planner_code,
            msi.list_price_per_unit,
            msi.attribute14,
            msi.attribute15,
            msi.full_lead_time
        INTO
            l_reference_primary_uom,
            l_reference_item_status,
            l_reference_item_type,
            l_reference_eng_item_flag,
            l_reference_planner_code,
            l_reference_price,
            l_reference_hims,
            l_reference_lead_time_flex,
            l_reference_full_lead_time
        FROM apps.mtl_system_items_b msi
        WHERE msi.inventory_item_id = l_reference_item_id
          AND msi.organization_id   = l_target_org_id;


        IF UPPER(TRIM(l_reference_primary_uom)) <>
           UPPER(TRIM(c_expected_primary_uom))
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20709,
                'Purchasing reference Primary UOM changed. Expected FT; actual=' ||
                NVL(l_reference_primary_uom, 'NULL')
            );
        END IF;


        IF UPPER(TRIM(l_reference_item_status)) <>
           UPPER(TRIM(c_expected_item_status))
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20710,
                'Purchasing reference Item Status changed. Expected ENGINEER; actual=' ||
                NVL(l_reference_item_status, 'NULL')
            );
        END IF;

        IF UPPER(TRIM(NVL(l_reference_item_type, '#NULL#'))) <> 'P' THEN
            RAISE_APPLICATION_ERROR
            (
                -20721,
                'Purchasing reference EBS ITEM_TYPE changed. Expected P; actual=' ||
                NVL(l_reference_item_type, 'NULL')
            );
        END IF;

        IF UPPER(TRIM(NVL(l_reference_eng_item_flag, '#NULL#'))) <> 'Y' THEN
            RAISE_APPLICATION_ERROR
            (
                -20722,
                'Purchasing reference ENG_ITEM_FLAG changed. Expected Y; actual=' ||
                NVL(l_reference_eng_item_flag, 'NULL')
            );
        END IF;

        IF TRIM(NVL(l_reference_planner_code, '#NULL#')) <> '17' THEN
            RAISE_APPLICATION_ERROR
            (
                -20723,
                'Purchasing reference PLANNER_CODE changed. Expected 17; actual=' ||
                NVL(l_reference_planner_code, 'NULL')
            );
        END IF;

        SELECT COUNT(*)
        INTO l_count
        FROM apps.mtl_planners
        WHERE organization_id = l_target_org_id
          AND planner_code = l_reference_planner_code
          AND (disable_date IS NULL OR disable_date > SYSDATE);

        IF l_count <> 1 THEN
            RAISE_APPLICATION_ERROR
            (
                -20724,
                'Purchasing reference Planner 17 is not active in the TARGET Organization.'
            );
        END IF;


        IF ABS(NVL(l_reference_price, -999999) - c_price_per_uom) > 0.0000001 THEN
            RAISE_APPLICATION_ERROR
            (
                -20711,
                'Purchasing reference Price changed. Expected 4.10; actual=' ||
                NVL(TO_CHAR(l_reference_price), 'NULL')
            );
        END IF;


        IF NVL(TRIM(l_reference_hims), '#NULL#') <> c_hims THEN
            RAISE_APPLICATION_ERROR
            (
                -20712,
                'Purchasing reference HIMS changed. Expected ' ||
                c_hims ||
                '; actual=' ||
                NVL(l_reference_hims, 'NULL')
            );
        END IF;


        IF ABS(NVL(l_reference_full_lead_time, -999999) - c_lead_time_days) > 0.0000001
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20713,
                'Purchasing reference FULL_LEAD_TIME changed. Expected 98; actual=' ||
                NVL(TO_CHAR(l_reference_full_lead_time), 'NULL')
            );
        END IF;

        IF NVL(TRIM(l_reference_lead_time_flex), '#NULL#') <>
           TO_CHAR(c_lead_time_days, 'TM9')
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20725,
                'Purchasing reference ATTRIBUTE15/LEADTIME changed. Expected 98; actual=' ||
                NVL(l_reference_lead_time_flex, 'NULL')
            );
        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Purchasing reference validated: ' ||
            c_reference_item_number ||
            ', UOM=' || l_reference_primary_uom ||
            ', STATUS=' || l_reference_item_status ||
            ', ITEM_TYPE=' || NVL(l_reference_item_type, 'NULL') ||
            ', ENG_ITEM_FLAG=' || NVL(l_reference_eng_item_flag, 'NULL') ||
            ', PLANNER=' || NVL(l_reference_planner_code, 'NULL') ||
            ', PRICE=' || TO_CHAR(l_reference_price) ||
            ', HIMS=' || l_reference_hims ||
            ', ATTRIBUTE15=' || NVL(l_reference_lead_time_flex, 'NULL') ||
            ', FULL_LEAD_TIME=' || NVL(TO_CHAR(l_reference_full_lead_time), 'NULL')
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Purchasing reference validates ATTRIBUTE15 and FULL_LEAD_TIME. ' ||
            'V7 must reproduce LEAD_TIME_DAYS in both destinations.'
        );


        -- =============================================================
        -- Clone Request header structure from Request 12, but replace all
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
            'Raw Material - PURCHASING GR validation test based on R-13140-97',
            'Raw Material - PURCHASING GR validation test based on R-13140-97',
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
                'Request 13 header could not be created from the Request 12 structure.'
            );

        END IF;


        -- =============================================================
        -- Create MASTER/TARGET Request Organizations from Request 12.
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
        -- Build Categories dynamically from R-13140-97 in GRI.
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
                'Raw Material Category staging count does not match the Purchasing reference Item.'
            );

        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Category rows staged from Purchasing reference=' ||
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
                'Current RAW_MATERIAL_ITEM configuration contains required Attributes not supplied by V13. MISSING_COUNT=' ||
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
            'Request 13 staged successfully.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'TARGET EBS_TEMPLATE_ID is NULL before package execution.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Expected package resolution: Expense Item N -> ' ||
            c_expected_target_template
        );

    END IF;


EXCEPTION
    WHEN OTHERS THEN

        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE
        (
            'V13 STAGING/PREFLIGHT ERROR=' ||
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
-- Execute ADRE_CREATE_INV_ITEM V7 unless Request 13 is PROCESSED.
-- =====================================================================

DECLARE

    c_item_request_id
        CONSTANT NUMBER := 13;

    l_request_count
        NUMBER;

    l_request_status
        VARCHAR2(30);

    l_return_status
        VARCHAR2(1);

    l_message
        CLOB;

BEGIN

    SELECT
        COUNT(*),
        MAX(request_status)
    INTO
        l_request_count,
        l_request_status
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_item_request_id;


    IF l_request_count = 0 THEN

        DBMS_OUTPUT.PUT_LINE
        (
            'Request 13 does not exist because preflight/staging did not complete.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Main package execution skipped. Resolve the Step 1 error and rerun V13.'
        );

    ELSIF l_request_status = 'PROCESSED' THEN

        DBMS_OUTPUT.PUT_LINE
        (
            'Request 13 is already PROCESSED.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Main package execution skipped. Run the separate verification script when needed.'
        );

    ELSE

        DBMS_OUTPUT.PUT_LINE
        (
            '============================================================'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'TEST V13 / RM-PUR / MH-94904-1013 - PACKAGE START'
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
                'ADRE_CREATE_INV_ITEM returned a non-success status for Request 13.'
            );

        END IF;

    END IF;

END;
/
