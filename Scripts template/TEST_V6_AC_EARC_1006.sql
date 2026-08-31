-- =====================================================================
-- JCALZADILLA - 27.08.2026 - START CHANGE
-- Purpose:
-- Execute one complete end-to-end Template test for:
--
--   Item Type    : Adhesive Coating (AC)
--   Division     : ARcare
--   Business Unit: Electronics
--   Target Org   : GRI / 58
--   Target       : ELECTRONICS ARCARE COATING (EAC)
--
-- Test Item:
--   ITEM_REQUEST_ID = 6
--   ITEM_NUMBER     = MH-94904-1006
--
-- Baseline:
--   Request 5 / MH-94904-1005 is used only as the known-good Adhesive
--   Coating application-data baseline. The new Request receives its own
--   Request Organization, Category, Attribute, Document, BOM, and BOM
--   Component rows.
--
-- Rules:
--   - This is the ONLY script for this test.
--   - The script performs preflight checks before creating anything.
--   - The Target Template is resolved from Oracle EBS by Template Name.
--   - The ELECTRONICS Business Unit Category is resolved from actual
--     Oracle EBS Category assignments for Category Set 4.
--   - The package itself creates the Item in Oracle EBS.
--   - No manual EBS Item Attribute update is performed by this script.
--   - The final result set is the table to export for test evidence.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- STEP 1
-- Build Request 6 in OPS from the known-good Adhesive Coating baseline.
-- =====================================================================

DECLARE

    c_source_request_id
        CONSTANT NUMBER := 5;

    c_new_request_id
        CONSTANT NUMBER := 6;

    c_new_request_number
        CONSTANT VARCHAR2(100) :=
            'TEST-AC-EARC-MH-94904-1006-GRI-001';

    c_new_item_number
        CONSTANT VARCHAR2(100) :=
            'MH-94904-1006';

    c_target_template_name
        CONSTANT VARCHAR2(100) :=
            'ELECTRONICS ARCARE COATING';

    c_master_business_category_set_id
        CONSTANT NUMBER := 4;

    c_master_business_unit
        CONSTANT VARCHAR2(100) :=
            'ELECTRONICS';

    l_count
        NUMBER;

    l_target_template_id
        NUMBER;

    l_business_category_id
        NUMBER;

    l_business_category_value
        VARCHAR2(240);

BEGIN

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        'TEST V6 / AC-EARC / MH-94904-1006 - STAGING START'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );


    -- =================================================================
    -- Preflight: the source Request must exist.
    -- =================================================================

    SELECT COUNT(*)
    INTO l_count
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_source_request_id;


    IF l_count <> 1 THEN

        RAISE_APPLICATION_ERROR
        (
            -20601,
            'Source Request 5 was not found.'
        );

    END IF;


    -- =================================================================
    -- Preflight: the new Request / Item must not already exist in OPS.
    -- =================================================================

    SELECT COUNT(*)
    INTO l_count
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_new_request_id
       OR UPPER(TRIM(item_number)) =
          UPPER(TRIM(c_new_item_number));


    IF l_count > 0 THEN

        RAISE_APPLICATION_ERROR
        (
            -20602,
            'Request 6 or Item MH-94904-1006 already exists in OPS.'
        );

    END IF;


    -- =================================================================
    -- Preflight: the Item must not already exist in Oracle EBS.
    -- =================================================================

    SELECT COUNT(*)
    INTO l_count
    FROM apps.mtl_system_items_kfv
    WHERE UPPER(TRIM(concatenated_segments)) =
          UPPER(TRIM(c_new_item_number));


    IF l_count > 0 THEN

        RAISE_APPLICATION_ERROR
        (
            -20603,
            'Item MH-94904-1006 already exists in Oracle EBS.'
        );

    END IF;


    -- =================================================================
    -- Resolve the Target Template directly from Oracle EBS.
    -- =================================================================

    SELECT
        COUNT(*),
        MIN(template_id)
    INTO
        l_count,
        l_target_template_id
    FROM apps.mtl_item_templates_vl
    WHERE UPPER(TRIM(template_name)) =
          UPPER(TRIM(c_target_template_name));


    IF l_count <> 1 OR l_target_template_id IS NULL THEN

        RAISE_APPLICATION_ERROR
        (
            -20604,
            'ELECTRONICS ARCARE COATING Template could not be resolved uniquely in Oracle EBS.'
        );

    END IF;


    DBMS_OUTPUT.PUT_LINE
    (
        'TARGET_TEMPLATE=' ||
        c_target_template_name ||
        ' / ' ||
        TO_CHAR(l_target_template_id)
    );


    -- =================================================================
    -- Resolve the ELECTRONICS Business Unit Category from actual Oracle
    -- EBS assignments for Category Set 4.
    --
    -- This avoids hard-coding the Category ID in the test script.
    -- =================================================================

    SELECT
        COUNT(DISTINCT mic.category_id),
        MIN(mic.category_id),
        MIN(mck.concatenated_segments)
    INTO
        l_count,
        l_business_category_id,
        l_business_category_value
    FROM apps.mtl_item_categories mic
    JOIN apps.mtl_categories_kfv mck
      ON mck.category_id = mic.category_id
    WHERE mic.category_set_id =
          c_master_business_category_set_id
      AND UPPER(TRIM(mck.concatenated_segments)) =
          UPPER(TRIM(c_master_business_unit));


    IF l_count <> 1 OR l_business_category_id IS NULL THEN

        RAISE_APPLICATION_ERROR
        (
            -20605,
            'ELECTRONICS Category could not be resolved uniquely for Category Set 4.'
        );

    END IF;


    DBMS_OUTPUT.PUT_LINE
    (
        'MASTER_BUSINESS_UNIT=' ||
        l_business_category_value ||
        ' / CATEGORY_ID=' ||
        TO_CHAR(l_business_category_id)
    );


    -- =================================================================
    -- Clone the Request header.
    -- =================================================================

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
        item_type_id,
        base_part_number,
        c_new_item_number,
        part_status,
        'Adhesive Coating - Electronics ARcare Coating Template test',
        long_description,
        primary_uom_code,
        item_status_code,
        initiator,
        requested_creation_date,
        forecast_flag,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        created_by,
        SYSDATE,
        last_updated_by,
        SYSDATE,
        last_update_login
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_source_request_id;


    IF SQL%ROWCOUNT <> 1 THEN

        RAISE_APPLICATION_ERROR
        (
            -20606,
            'Request header could not be cloned from Request 5.'
        );

    END IF;


    -- =================================================================
    -- Clone MASTER and TARGET Request Organizations.
    --
    -- MASTER keeps the known-good GLOBAL ITEM Template.
    -- TARGET receives ELECTRONICS ARCARE COATING.
    -- =================================================================

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
            WHEN organization_role = 'TARGET'
            THEN l_target_template_id
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
        last_updated_by,
        SYSDATE,
        last_update_login
    FROM ops.adre_inv_item_request_org
    WHERE item_request_id = c_source_request_id;


    IF SQL%ROWCOUNT <> 2 THEN

        RAISE_APPLICATION_ERROR
        (
            -20607,
            'Expected 2 Request Organization rows for Request 6.'
        );

    END IF;


    -- =================================================================
    -- Clone Category assignments.
    -- =================================================================

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
    SELECT
        new_ro.request_org_id,
        cat.ebs_category_set_id,
        cat.ebs_category_id,
        cat.category_value,
        'READY',
        NULL,
        NULL,
        NULL,
        NULL,
        cat.created_by,
        SYSDATE,
        cat.last_updated_by,
        SYSDATE,
        cat.last_update_login
    FROM ops.adre_inv_item_category cat
    JOIN ops.adre_inv_item_request_org old_ro
      ON old_ro.request_org_id = cat.request_org_id
    JOIN ops.adre_inv_item_request_org new_ro
      ON new_ro.item_request_id     = c_new_request_id
     AND new_ro.organization_role   = old_ro.organization_role
     AND new_ro.ebs_organization_id = old_ro.ebs_organization_id
    WHERE old_ro.item_request_id = c_source_request_id;


    IF SQL%ROWCOUNT <> 4 THEN

        RAISE_APPLICATION_ERROR
        (
            -20608,
            'Expected 4 Category rows for Request 6.'
        );

    END IF;


    -- =================================================================
    -- Replace the MASTER Business Unit Category:
    --   MEDICAL -> ELECTRONICS
    --
    -- ARCARE, DEVELOPMENTAL PRODUCTS-, and WIP remain the same baseline
    -- values for this Adhesive Coating test.
    -- =================================================================

    UPDATE ops.adre_inv_item_category cat
    SET
        cat.ebs_category_id  = l_business_category_id,
        cat.category_value   = l_business_category_value,
        cat.assignment_status = 'READY',
        cat.api_return_status = NULL,
        cat.api_message_count = NULL,
        cat.api_message_text  = NULL,
        cat.api_processed_date = NULL,
        cat.last_updated_by   = 'JCALZADILLA',
        cat.last_update_date  = SYSDATE
    WHERE cat.request_org_id =
          (
              SELECT ro.request_org_id
              FROM ops.adre_inv_item_request_org ro
              WHERE ro.item_request_id   = c_new_request_id
                AND ro.organization_role = 'MASTER'
          )
      AND cat.ebs_category_set_id =
          c_master_business_category_set_id;


    IF SQL%ROWCOUNT <> 1 THEN

        RAISE_APPLICATION_ERROR
        (
            -20609,
            'Expected exactly 1 MASTER Business Unit Category row to update.'
        );

    END IF;


    -- =================================================================
    -- Clone Attribute values.
    --
    -- These are the same controlled Adhesive Coating application values
    -- used in the successful Request 5 baseline.
    -- =================================================================

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
        new_ro.request_org_id,
        av.item_attribute_id,
        av.attribute_char_value,
        av.attribute_number_value,
        av.attribute_date_value,
        av.value_uom_code,
        'READY',
        NULL,
        NULL,
        NULL,
        NULL,
        av.created_by,
        SYSDATE,
        av.last_updated_by,
        SYSDATE,
        av.last_update_login
    FROM ops.adre_inv_item_attr_value av
    JOIN ops.adre_inv_item_request_org old_ro
      ON old_ro.request_org_id = av.request_org_id
    JOIN ops.adre_inv_item_request_org new_ro
      ON new_ro.item_request_id     = c_new_request_id
     AND new_ro.organization_role   = old_ro.organization_role
     AND new_ro.ebs_organization_id = old_ro.ebs_organization_id
    WHERE old_ro.item_request_id = c_source_request_id;


    IF SQL%ROWCOUNT <> 10 THEN

        RAISE_APPLICATION_ERROR
        (
            -20610,
            'Expected 10 Attribute Value rows for Request 6.'
        );

    END IF;


    -- =================================================================
    -- Clone Documents.
    -- =================================================================

    INSERT INTO ops.adre_inv_item_document
    (
        request_org_id,
        document_type,
        document_title,
        document_description,
        file_name,
        mime_type,
        file_charset,
        file_blob,
        document_status,
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
        new_ro.request_org_id,
        d.document_type,
        d.document_title,
        d.document_description,
        d.file_name,
        d.mime_type,
        d.file_charset,
        d.file_blob,
        'DRAFT',
        NULL,
        NULL,
        NULL,
        NULL,
        d.created_by,
        SYSDATE,
        d.last_updated_by,
        SYSDATE,
        d.last_update_login
    FROM ops.adre_inv_item_document d
    JOIN ops.adre_inv_item_request_org old_ro
      ON old_ro.request_org_id = d.request_org_id
    JOIN ops.adre_inv_item_request_org new_ro
      ON new_ro.item_request_id     = c_new_request_id
     AND new_ro.organization_role   = old_ro.organization_role
     AND new_ro.ebs_organization_id = old_ro.ebs_organization_id
    WHERE old_ro.item_request_id = c_source_request_id;


    -- =================================================================
    -- Clone BOM headers.
    -- =================================================================

    INSERT INTO ops.adre_inv_item_bom
    (
        request_org_id,
        alternate_bom_designator,
        bom_description,
        effectivity_date,
        ebs_bill_sequence_id,
        bom_status,
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
        new_ro.request_org_id,
        bom.alternate_bom_designator,
        bom.bom_description,
        bom.effectivity_date,
        NULL,
        'DRAFT',
        NULL,
        NULL,
        NULL,
        NULL,
        bom.created_by,
        SYSDATE,
        bom.last_updated_by,
        SYSDATE,
        bom.last_update_login
    FROM ops.adre_inv_item_bom bom
    JOIN ops.adre_inv_item_request_org old_ro
      ON old_ro.request_org_id = bom.request_org_id
    JOIN ops.adre_inv_item_request_org new_ro
      ON new_ro.item_request_id     = c_new_request_id
     AND new_ro.organization_role   = old_ro.organization_role
     AND new_ro.ebs_organization_id = old_ro.ebs_organization_id
    WHERE old_ro.item_request_id = c_source_request_id;


    -- =================================================================
    -- Clone BOM Components.
    -- =================================================================

    INSERT INTO ops.adre_inv_item_bom_comp
    (
        item_bom_id,
        component_item_number,
        ebs_component_item_id,
        component_quantity,
        component_uom_code,
        operation_sequence,
        item_sequence,
        effectivity_date,
        disable_date,
        supply_type,
        component_status,
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
        new_bom.item_bom_id,
        comp.component_item_number,
        NULL,
        comp.component_quantity,
        comp.component_uom_code,
        comp.operation_sequence,
        comp.item_sequence,
        comp.effectivity_date,
        comp.disable_date,
        comp.supply_type,
        'DRAFT',
        NULL,
        NULL,
        NULL,
        NULL,
        comp.created_by,
        SYSDATE,
        comp.last_updated_by,
        SYSDATE,
        comp.last_update_login
    FROM ops.adre_inv_item_bom_comp comp
    JOIN ops.adre_inv_item_bom old_bom
      ON old_bom.item_bom_id = comp.item_bom_id
    JOIN ops.adre_inv_item_request_org old_ro
      ON old_ro.request_org_id = old_bom.request_org_id
    JOIN ops.adre_inv_item_request_org new_ro
      ON new_ro.item_request_id     = c_new_request_id
     AND new_ro.organization_role   = old_ro.organization_role
     AND new_ro.ebs_organization_id = old_ro.ebs_organization_id
    JOIN ops.adre_inv_item_bom new_bom
      ON new_bom.request_org_id = new_ro.request_org_id
     AND
        (
             new_bom.alternate_bom_designator =
                 old_bom.alternate_bom_designator
          OR
             (
                 new_bom.alternate_bom_designator IS NULL
                 AND old_bom.alternate_bom_designator IS NULL
             )
        )
    WHERE old_ro.item_request_id = c_source_request_id;


    COMMIT;


    DBMS_OUTPUT.PUT_LINE
    (
        'Request 6 / MH-94904-1006 created successfully in OPS.'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        'Staging committed. Oracle EBS Item does not exist yet.'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );

EXCEPTION
    WHEN OTHERS THEN

        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE
        (
            'STAGING ERROR=' ||
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
-- Execute ADRE_CREATE_INV_ITEM.
--
-- The package must perform:
--   - MASTER Item creation.
--   - MASTER Attribute application.
--   - TARGET Organization assignment.
--   - ELECTRONICS ARCARE COATING Target Template application.
--   - TARGET Attribute application.
--   - Category processing.
-- =====================================================================

DECLARE

    c_item_request_id
        CONSTANT NUMBER := 6;

    l_return_status
        VARCHAR2(1);

    l_message
        CLOB;

BEGIN

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        'TEST V6 / AC-EARC / MH-94904-1006 - PACKAGE START'
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
            -20620,
            'ADRE_CREATE_INV_ITEM returned a non-success status for Request 6.'
        );

    END IF;


    DBMS_OUTPUT.PUT_LINE
    (
        'TEST V6 / AC-EARC COMPLETED SUCCESSFULLY.'
    );

END;
/


-- =====================================================================
-- STEP 3
-- APEX / EBS Item summary.
-- =====================================================================

SELECT
    r.item_request_id,
    r.request_number,
    r.item_number,
    r.request_status,
    r.api_return_status AS request_api_status,

    ro.organization_role,
    ro.ebs_organization_id,
    ood.organization_code,

    ro.ebs_template_id,
    t.template_name,

    ro.ebs_inventory_item_id,
    ro.assignment_status,
    ro.api_return_status AS org_api_status,

    kfv.concatenated_segments AS ebs_item_number,

    msi.mrp_planning_code,
    msi.outside_operation_flag,
    msi.dimension_uom_code,
    msi.unit_width,
    msi.unit_length,
    msi.planner_code,
    msi.planning_make_buy_code,
    msi.item_type,
    msi.bom_enabled_flag,
    msi.eng_item_flag,
    msi.inventory_item_status_code

FROM ops.adre_inv_item_request r

JOIN ops.adre_inv_item_request_org ro
  ON ro.item_request_id = r.item_request_id

LEFT JOIN apps.org_organization_definitions ood
  ON ood.organization_id = ro.ebs_organization_id

LEFT JOIN apps.mtl_item_templates_vl t
  ON t.template_id = ro.ebs_template_id

LEFT JOIN apps.mtl_system_items_b msi
  ON msi.inventory_item_id = ro.ebs_inventory_item_id
 AND msi.organization_id   = ro.ebs_organization_id

LEFT JOIN apps.mtl_system_items_kfv kfv
  ON kfv.inventory_item_id = msi.inventory_item_id
 AND kfv.organization_id   = msi.organization_id

WHERE r.item_request_id = 6

ORDER BY
    CASE ro.organization_role
        WHEN 'MASTER' THEN 1
        WHEN 'TARGET' THEN 2
        ELSE 3
    END
;


-- =====================================================================
-- STEP 4
-- Confirm package/API processing log.
-- =====================================================================

SELECT
    item_api_log_id,
    execution_id,
    request_org_id,
    process_name,
    api_name,
    process_status,
    api_return_status,
    api_message_count,
    message_text

FROM ops.adre_inv_item_api_log

WHERE item_request_id = 6

ORDER BY item_api_log_id
;


-- =====================================================================
-- STEP 5 - FINAL EXPORT TABLE
--
-- IMPORTANT:
-- Download/export this final result set after the test.
--
-- It contains:
--   - APEX / EBS Organization processing.
--   - The 4 package-supported application Attribute comparisons.
--   - Category comparisons.
--   - Every enabled MASTER and TARGET Template Attribute compared with
--     the final Oracle EBS Item value.
--
-- VALIDATION_STATUS:
--   MATCH / PASS       = expected result.
--   DIFFERENT          = investigate before closing the test.
--   COLUMN NOT FOUND   = investigate template metadata mapping.
-- =====================================================================


-- =====================================================================
-- 5A. Organization checks.
-- =====================================================================

SELECT
    'ITEM_ORGANIZATION' AS validation_group,

    ro.organization_role,
    ood.organization_code,

    r.item_number,
    ro.ebs_inventory_item_id AS inventory_item_id,

    ro.ebs_template_id AS template_id,
    t.template_name,

    'ORGANIZATION_PROCESSING' AS validation_name,

    ro.assignment_status ||
    ' / ' ||
    NVL(ro.api_return_status, 'NULL') AS source_value,

    NVL(kfv.concatenated_segments, 'NOT FOUND') AS ebs_value,

    CASE
        WHEN ro.assignment_status = 'PROCESSED'
         AND ro.api_return_status = 'S'
         AND UPPER(TRIM(kfv.concatenated_segments)) =
             UPPER(TRIM(r.item_number))
        THEN 'PASS'
        ELSE 'DIFFERENT'
    END AS validation_status,

    'APEX Organization status versus Oracle EBS Item existence.' AS notes

FROM ops.adre_inv_item_request r

JOIN ops.adre_inv_item_request_org ro
  ON ro.item_request_id = r.item_request_id

LEFT JOIN apps.org_organization_definitions ood
  ON ood.organization_id = ro.ebs_organization_id

LEFT JOIN apps.mtl_item_templates_vl t
  ON t.template_id = ro.ebs_template_id

LEFT JOIN apps.mtl_system_items_kfv kfv
  ON kfv.inventory_item_id = ro.ebs_inventory_item_id
 AND kfv.organization_id   = ro.ebs_organization_id

WHERE r.item_request_id = 6


UNION ALL


-- =====================================================================
-- 5B. Package-supported application Attribute checks.
-- =====================================================================

SELECT
    'APEX_ATTRIBUTE' AS validation_group,

    ro.organization_role,
    ood.organization_code,

    r.item_number,
    master_ro.ebs_inventory_item_id AS inventory_item_id,

    ro.ebs_template_id AS template_id,
    t.template_name,

    a.attribute_code AS validation_name,

    CASE
        WHEN av.attribute_char_value IS NOT NULL
        THEN av.attribute_char_value
        ELSE
            TO_CHAR(av.attribute_number_value) ||
            CASE
                WHEN av.value_uom_code IS NOT NULL
                THEN ' ' || av.value_uom_code
            END
    END AS source_value,

    CASE a.attribute_code
        WHEN 'PLANNING_METHOD'
        THEN
            CASE master_msi.mrp_planning_code
                WHEN 3 THEN 'MRP Planning'
                ELSE TO_CHAR(master_msi.mrp_planning_code)
            END

        WHEN 'OUTSIDE_PROCESSING'
        THEN target_msi.outside_operation_flag

        WHEN 'WIDTH'
        THEN
            TO_CHAR(target_msi.unit_width) ||
            ' ' ||
            target_msi.dimension_uom_code

        WHEN 'TARGET_LENGTH'
        THEN
            TO_CHAR(target_msi.unit_length) ||
            ' ' ||
            target_msi.dimension_uom_code
    END AS ebs_value,

    CASE a.attribute_code
        WHEN 'PLANNING_METHOD'
        THEN
            CASE
                WHEN UPPER(TRIM(av.attribute_char_value)) = 'MRP PLANNING'
                 AND master_msi.mrp_planning_code = 3
                THEN 'MATCH'
                ELSE 'DIFFERENT'
            END

        WHEN 'OUTSIDE_PROCESSING'
        THEN
            CASE
                WHEN UPPER(TRIM(av.attribute_char_value)) =
                     UPPER(TRIM(target_msi.outside_operation_flag))
                THEN 'MATCH'
                ELSE 'DIFFERENT'
            END

        WHEN 'WIDTH'
        THEN
            CASE
                WHEN
                    CASE UPPER(TRIM(av.value_uom_code))
                        WHEN 'IN' THEN av.attribute_number_value
                        WHEN 'FT' THEN av.attribute_number_value * 12
                    END = target_msi.unit_width
                 AND target_msi.dimension_uom_code = 'IN'
                THEN 'MATCH'
                ELSE 'DIFFERENT'
            END

        WHEN 'TARGET_LENGTH'
        THEN
            CASE
                WHEN
                    CASE UPPER(TRIM(av.value_uom_code))
                        WHEN 'IN' THEN av.attribute_number_value
                        WHEN 'FT' THEN av.attribute_number_value * 12
                    END = target_msi.unit_length
                 AND target_msi.dimension_uom_code = 'IN'
                THEN 'MATCH'
                ELSE 'DIFFERENT'
            END
    END AS validation_status,

    'Application Attribute versus final Oracle EBS Item value.' AS notes

FROM ops.adre_inv_item_request r

JOIN ops.adre_inv_item_request_org ro
  ON ro.item_request_id = r.item_request_id

JOIN ops.adre_inv_item_attr_value av
  ON av.request_org_id = ro.request_org_id

JOIN ops.adre_inv_item_attribute a
  ON a.item_attribute_id = av.item_attribute_id

LEFT JOIN apps.org_organization_definitions ood
  ON ood.organization_id = ro.ebs_organization_id

LEFT JOIN apps.mtl_item_templates_vl t
  ON t.template_id = ro.ebs_template_id

JOIN ops.adre_inv_item_request_org master_ro
  ON master_ro.item_request_id   = r.item_request_id
 AND master_ro.organization_role = 'MASTER'

JOIN apps.mtl_system_items_b master_msi
  ON master_msi.inventory_item_id = master_ro.ebs_inventory_item_id
 AND master_msi.organization_id   = master_ro.ebs_organization_id

JOIN ops.adre_inv_item_request_org target_ro
  ON target_ro.item_request_id   = r.item_request_id
 AND target_ro.organization_role = 'TARGET'

JOIN apps.mtl_system_items_b target_msi
  ON target_msi.inventory_item_id = target_ro.ebs_inventory_item_id
 AND target_msi.organization_id   = target_ro.ebs_organization_id

WHERE r.item_request_id = 6
  AND a.attribute_code IN
      (
          'PLANNING_METHOD',
          'OUTSIDE_PROCESSING',
          'WIDTH',
          'TARGET_LENGTH'
      )


UNION ALL


-- =====================================================================
-- 5C. Category checks.
-- =====================================================================

SELECT
    'CATEGORY' AS validation_group,

    ro.organization_role,
    ood.organization_code,

    r.item_number,
    ro.ebs_inventory_item_id AS inventory_item_id,

    ro.ebs_template_id AS template_id,
    t.template_name,

    'CATEGORY_SET_' ||
    TO_CHAR(cat.ebs_category_set_id) AS validation_name,

    cat.category_value AS source_value,

    NVL(mck.concatenated_segments, 'NOT ASSIGNED') AS ebs_value,

    CASE
        WHEN mic.category_id = cat.ebs_category_id
        THEN 'MATCH'
        ELSE 'DIFFERENT'
    END AS validation_status,

    'APEX Category assignment versus Oracle EBS Category assignment.' AS notes

FROM ops.adre_inv_item_request r

JOIN ops.adre_inv_item_request_org ro
  ON ro.item_request_id = r.item_request_id

JOIN ops.adre_inv_item_category cat
  ON cat.request_org_id = ro.request_org_id

LEFT JOIN apps.org_organization_definitions ood
  ON ood.organization_id = ro.ebs_organization_id

LEFT JOIN apps.mtl_item_templates_vl t
  ON t.template_id = ro.ebs_template_id

LEFT JOIN apps.mtl_item_categories mic
  ON mic.inventory_item_id = ro.ebs_inventory_item_id
 AND mic.organization_id   = ro.ebs_organization_id
 AND mic.category_set_id   = cat.ebs_category_set_id
 AND mic.category_id       = cat.ebs_category_id

LEFT JOIN apps.mtl_categories_kfv mck
  ON mck.category_id = mic.category_id

WHERE r.item_request_id = 6


UNION ALL


-- =====================================================================
-- 5D. Complete Template Attribute checks.
--
-- MASTER Template Attributes are evaluated in the MASTER Organization.
--
-- TARGET Template:
--   CONTROL_LEVEL = 1 -> MASTER Organization.
--   CONTROL_LEVEL = 2 -> TARGET Organization.
-- =====================================================================

SELECT
    'TEMPLATE_ATTRIBUTE' AS validation_group,

    template_result.template_role AS organization_role,
    template_result.effective_source AS organization_code,

    template_result.item_number,
    template_result.inventory_item_id,

    template_result.template_id,
    template_result.template_name,

    template_result.attribute_name AS validation_name,

    template_result.template_attribute_value AS source_value,

    template_result.actual_item_value AS ebs_value,

    CASE
        WHEN template_result.verified_item_column IS NULL
        THEN 'COLUMN NOT FOUND'

        WHEN NVL(TRIM(template_result.actual_item_value), '#NULL#') =
             NVL(TRIM(template_result.template_attribute_value), '#NULL#')
        THEN 'MATCH'

        ELSE 'DIFFERENT'
    END AS validation_status,

    CASE
        WHEN template_result.verified_item_column IS NULL
        THEN
            'Template Attribute could not be mapped to MTL_SYSTEM_ITEMS_B.'

        WHEN NVL(TRIM(template_result.actual_item_value), '#NULL#') =
             NVL(TRIM(template_result.template_attribute_value), '#NULL#')
        THEN
            NVL
            (
                template_result.template_value_description,
                'Template value matches final Oracle EBS Item value.'
            )

        ELSE
            'Template=' ||
            NVL(template_result.template_attribute_value, 'NULL') ||
            '; Item=' ||
            NVL(template_result.actual_item_value, 'NULL')
    END AS notes

FROM
(
    SELECT
        resolved_data.*,

        CASE resolved_data.effective_org_id
            WHEN 59 THEN 'MAS'
            WHEN 58 THEN 'GRI'
            ELSE TO_CHAR(resolved_data.effective_org_id)
        END AS effective_source,

        CASE
            WHEN resolved_data.verified_item_column IS NOT NULL
            THEN
                XMLCAST
                (
                    XMLQUERY
                    (
                        '/ROWSET/ROW/ACTUAL_VALUE/text()'
                        PASSING
                            DBMS_XMLGEN.GETXMLTYPE
                            (
                                'SELECT TO_CHAR(msi.' ||
                                resolved_data.verified_item_column ||
                                ') AS actual_value ' ||
                                'FROM apps.mtl_system_items_b msi ' ||
                                'WHERE msi.inventory_item_id = ' ||
                                TO_CHAR(resolved_data.inventory_item_id) ||
                                ' AND msi.organization_id = ' ||
                                TO_CHAR(resolved_data.effective_org_id)
                            )
                        RETURNING CONTENT
                    )
                    AS VARCHAR2(4000)
                )
        END AS actual_item_value

    FROM
    (
        SELECT
            template_data.*,
            item_cols.column_name AS verified_item_column

        FROM
        (
            SELECT
                r.item_number,

                master_ro.ebs_inventory_item_id AS inventory_item_id,

                template_ro.organization_role AS template_role,

                t.template_id,
                t.template_name,

                ta.attribute_name,

                REGEXP_SUBSTR
                (
                    ta.attribute_name,
                    '[^.]+$'
                ) AS target_item_column,

                ta.attribute_value AS template_attribute_value,
                ta.report_user_value AS template_value_description,

                ia.control_level,

                CASE
                    WHEN template_ro.organization_role = 'MASTER'
                    THEN master_ro.ebs_organization_id

                    WHEN template_ro.organization_role = 'TARGET'
                     AND ia.control_level = 1
                    THEN master_ro.ebs_organization_id

                    ELSE template_ro.ebs_organization_id
                END AS effective_org_id

            FROM ops.adre_inv_item_request r

            JOIN ops.adre_inv_item_request_org master_ro
              ON master_ro.item_request_id   = r.item_request_id
             AND master_ro.organization_role = 'MASTER'

            JOIN ops.adre_inv_item_request_org template_ro
              ON template_ro.item_request_id = r.item_request_id

            JOIN apps.mtl_item_templates_vl t
              ON t.template_id = template_ro.ebs_template_id

            JOIN apps.mtl_item_templ_attributes ta
              ON ta.template_id = t.template_id
             AND ta.enabled_flag = 'Y'

            LEFT JOIN apps.mtl_item_attributes ia
              ON ia.attribute_name = ta.attribute_name

            WHERE r.item_request_id = 6

        ) template_data

        LEFT JOIN
        (
            SELECT DISTINCT
                column_name
            FROM all_tab_columns
            WHERE owner = 'INV'
              AND table_name IN
                  (
                      'MTL_SYSTEM_ITEMS_B',
                      'MTL_SYSTEM_ITEMS_B#'
                  )
        ) item_cols
          ON item_cols.column_name =
             template_data.target_item_column

    ) resolved_data

) template_result


ORDER BY
    validation_group,
    organization_role,
    validation_name
;

-- =====================================================================
-- JCALZADILLA - 27.08.2026 - END CHANGE
-- =====================================================================
