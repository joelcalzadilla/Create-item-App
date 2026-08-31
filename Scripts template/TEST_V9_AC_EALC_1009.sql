-- =====================================================================
-- JCALZADILLA - 28.08.2026 - START CHANGE
-- VERSION:
--   V9-AC-EALC-20260828-01
--
-- Purpose:
-- Execute and verify the complete V9 test for:
--
--   Item Type     : Adhesive Coating (AC)
--   Division      : ARclad
--   Business Unit : Electronics
--
-- Test:
--   ITEM_REQUEST_ID = 9
--   ITEM_NUMBER     = MH-94904-1009
--
-- Rules:
--   - This is the ONLY script for V9.
--   - This script is rerunnable.
--   - If Request 9 already exists, staging is skipped without error.
--   - If Request 9 is already PROCESSED, package execution is skipped.
--   - TARGET EBS_TEMPLATE_ID is NOT supplied by this test.
--   - ADRE_CREATE_INV_ITEM resolves the TARGET Template Rule.
--   - No EBS Organization ID is hard-coded.
--   - No EBS Template ID is hard-coded.
--   - No EBS Category Set ID is hard-coded.
--   - No EBS Category ID is hard-coded.
--   - No direct Oracle EBS Item Attribute update is performed here.
--   - The final SELECT is the exportable V9 evidence table.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- STEP 1
-- Stage Request 9 only when the exact test Request does not already exist.
-- =====================================================================

DECLARE

    c_source_request_id
        CONSTANT NUMBER := 7;

    c_new_request_id
        CONSTANT NUMBER := 9;

    c_new_request_number
        CONSTANT VARCHAR2(100) :=
            'TEST-AC-EALC-MH-94904-1009-GRI-001';

    c_new_item_number
        CONSTANT VARCHAR2(100) :=
            'MH-94904-1009';

    c_source_division
        CONSTANT VARCHAR2(100) :=
            'ARCARE';

    c_target_division
        CONSTANT VARCHAR2(100) :=
            'ARCLAD';

    c_source_business_unit
        CONSTANT VARCHAR2(100) :=
            'ENGINEERED TAPE';

    c_target_business_unit
        CONSTANT VARCHAR2(100) :=
            'ELECTRONICS';

    l_exact_request_count
        NUMBER;

    l_conflict_count
        NUMBER;

    l_count
        NUMBER;

    l_division_category_set_id
        NUMBER;

    l_division_category_id
        NUMBER;

    l_division_category_value
        VARCHAR2(240);

    l_business_category_set_id
        NUMBER;

    l_business_category_id
        NUMBER;

    l_business_category_value
        VARCHAR2(240);

    l_rule_count
        NUMBER;

    l_rule_id
        NUMBER;

    l_rule_template_name
        VARCHAR2(240);

BEGIN

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        'TEST V9 / AC-EALC / MH-94904-1009 - STAGING CHECK'
    );

    DBMS_OUTPUT.PUT_LINE
    (
        '============================================================'
    );


    SELECT COUNT(*)
    INTO l_exact_request_count
    FROM ops.adre_inv_item_request
    WHERE item_request_id = c_new_request_id
      AND UPPER(TRIM(item_number)) =
          UPPER(TRIM(c_new_item_number));


    IF l_exact_request_count = 1 THEN

        DBMS_OUTPUT.PUT_LINE
        (
            'Request 9 / MH-94904-1009 already exists in OPS.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'Staging skipped. Existing V9 data is preserved.'
        );

    ELSE

        -- =============================================================
        -- Prevent reuse of Request ID or Item Number by another Request.
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
                -20601,
                'Request ID 9 or Item MH-94904-1009 is already used by a different OPS Request.'
            );

        END IF;


        -- =============================================================
        -- Source Request must exist.
        -- =============================================================

        SELECT COUNT(*)
        INTO l_count
        FROM ops.adre_inv_item_request
        WHERE item_request_id = c_source_request_id;


        IF l_count <> 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20602,
                'Source Request 7 was not found.'
            );

        END IF;


        -- =============================================================
        -- Verify that exactly one active TARGET Template Rule is ready
        -- for the V9 business inputs.
        --
        -- The Rule and Template are validated here only as configuration.
        -- TARGET EBS_TEMPLATE_ID remains NULL in staging so the main
        -- ADRE_CREATE_INV_ITEM package must resolve and persist it.
        -- =============================================================

        SELECT
            COUNT(*),
            MIN(tr.item_template_rule_id),
            MIN(t.template_name)
        INTO
            l_rule_count,
            l_rule_id,
            l_rule_template_name
        FROM ops.adre_inv_item_template_rule tr

        JOIN apps.mtl_item_templates_vl t
          ON t.template_id = tr.ebs_template_id

        WHERE tr.item_type_id =
              (
                  SELECT r.item_type_id
                  FROM ops.adre_inv_item_request r
                  WHERE r.item_request_id =
                        c_source_request_id
              )

          AND tr.ebs_organization_id =
              (
                  SELECT ro.ebs_organization_id
                  FROM ops.adre_inv_item_request_org ro
                  WHERE ro.item_request_id =
                        c_source_request_id
                    AND ro.organization_role =
                        'TARGET'
              )

          AND UPPER(TRIM(tr.division_value)) =
              UPPER(TRIM(c_target_division))

          AND UPPER(TRIM(tr.business_unit_value)) =
              UPPER(TRIM(c_target_business_unit))

          AND tr.rule_status = 'READY'
          AND tr.active_flag = 'Y'

          AND
              (
                  tr.effective_start_date IS NULL
                  OR tr.effective_start_date <= TRUNC(SYSDATE)
              )

          AND
              (
                  tr.effective_end_date IS NULL
                  OR tr.effective_end_date >= TRUNC(SYSDATE)
              );


        IF l_rule_count <> 1
           OR l_rule_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20603,
                'Expected exactly one active TARGET Template Rule for AC / ARclad / Electronics.'
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
        -- New Item must not already exist in Oracle EBS when the OPS
        -- Request does not exist.
        -- =============================================================

        SELECT COUNT(*)
        INTO l_count
        FROM apps.mtl_system_items_kfv
        WHERE UPPER(TRIM(concatenated_segments)) =
              UPPER(TRIM(c_new_item_number));


        IF l_count > 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20612,
                'Item MH-94904-1009 already exists in Oracle EBS without Request 9 in OPS.'
            );

        END IF;


        -- =============================================================
        -- Resolve the Division Category Set from the successful source
        -- Request. No Category Set ID is hard-coded.
        -- =============================================================

        SELECT
            COUNT(DISTINCT cat.ebs_category_set_id),
            MIN(cat.ebs_category_set_id)
        INTO
            l_count,
            l_division_category_set_id
        FROM ops.adre_inv_item_category cat
        JOIN ops.adre_inv_item_request_org ro
          ON ro.request_org_id = cat.request_org_id
        WHERE ro.item_request_id = c_source_request_id
          AND UPPER(TRIM(cat.category_value)) =
              UPPER(TRIM(c_source_division));

        IF l_count <> 1
           OR l_division_category_set_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20604,
                'The source Division Category Set could not be resolved uniquely.'
            );

        END IF;


        -- =============================================================
        -- Resolve ARCLAD dynamically from Oracle EBS using the same
        -- Category Set as the source Division.
        -- No Category ID is hard-coded.
        -- =============================================================

        SELECT
            COUNT(DISTINCT mic.category_id),
            MIN(mic.category_id),
            MIN(mck.concatenated_segments)
        INTO
            l_count,
            l_division_category_id,
            l_division_category_value
        FROM apps.mtl_item_categories mic
        JOIN apps.mtl_categories_kfv mck
          ON mck.category_id = mic.category_id
        WHERE mic.category_set_id =
              l_division_category_set_id
          AND UPPER(TRIM(mck.concatenated_segments)) =
              UPPER(TRIM(c_target_division));

        IF l_count <> 1
           OR l_division_category_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20605,
                'The ARCLAD Division Category could not be resolved uniquely from Oracle EBS.'
            );

        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Division resolved from Oracle EBS: ' ||
            l_division_category_value
        );


        -- =============================================================
        -- Resolve the Business Unit Category Set from the successful
        -- source Request. No Category Set ID is hard-coded.
        -- =============================================================

        SELECT
            COUNT(DISTINCT cat.ebs_category_set_id),
            MIN(cat.ebs_category_set_id)
        INTO
            l_count,
            l_business_category_set_id
        FROM ops.adre_inv_item_category cat
        JOIN ops.adre_inv_item_request_org ro
          ON ro.request_org_id = cat.request_org_id
        WHERE ro.item_request_id = c_source_request_id
          AND UPPER(TRIM(cat.category_value)) =
              UPPER(TRIM(c_source_business_unit));


        IF l_count <> 1
           OR l_business_category_set_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20606,
                'The source Business Unit Category Set could not be resolved uniquely.'
            );

        END IF;


        -- =============================================================
        -- Resolve ELECTRONICS dynamically from Oracle EBS using the same
        -- Category Set as the source Business Unit.
        -- No Category ID is hard-coded.
        -- =============================================================

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
              l_business_category_set_id
          AND UPPER(TRIM(mck.concatenated_segments)) =
              UPPER(TRIM(c_target_business_unit));


        IF l_count <> 1
           OR l_business_category_id IS NULL
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20607,
                'The ELECTRONICS Business Unit Category could not be resolved uniquely from Oracle EBS.'
            );

        END IF;


        DBMS_OUTPUT.PUT_LINE
        (
            'Business Unit resolved from Oracle EBS: ' ||
            l_business_category_value
        );


        -- =============================================================
        -- Clone Request header.
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
            item_type_id,
            base_part_number,
            c_new_item_number,
            part_status,
            'Adhesive Coating - ARclad / Electronics test',
            'Adhesive Coating - ARclad / Electronics test',
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
            'JCALZADILLA',
            SYSDATE,
            last_update_login
        FROM ops.adre_inv_item_request
        WHERE item_request_id = c_source_request_id;


        IF SQL%ROWCOUNT <> 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20606,
                'Request header could not be cloned from Request 7.'
            );

        END IF;


        -- =============================================================
        -- Clone MASTER / TARGET Request Organizations.
        --
        -- MASTER keeps the baseline application configuration.
        -- TARGET EBS_TEMPLATE_ID is deliberately NULL.
        -- The main package must resolve the Template Rule.
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
                WHEN organization_role = 'TARGET'
                THEN NULL
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
                -20607,
                'Expected 2 Request Organization rows.'
            );

        END IF;


        SELECT COUNT(*)
        INTO l_count
        FROM ops.adre_inv_item_request_org
        WHERE item_request_id = c_new_request_id
          AND organization_role = 'TARGET'
          AND ebs_template_id IS NOT NULL;


        IF l_count <> 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20608,
                'TARGET EBS_TEMPLATE_ID must be NULL before package execution.'
            );

        END IF;


        -- =============================================================
        -- Clone Category assignments.
        -- =============================================================

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
            'JCALZADILLA',
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
                -20609,
                'Expected 4 Category rows.'
            );

        END IF;


        -- =============================================================
        -- Change the functional Division input:
        -- ARCARE -> ARCLAD.
        -- =============================================================

        UPDATE ops.adre_inv_item_category cat
        SET
            cat.ebs_category_id    = l_division_category_id,
            cat.category_value     = l_division_category_value,
            cat.assignment_status  = 'READY',
            cat.api_return_status  = NULL,
            cat.api_message_count  = NULL,
            cat.api_message_text   = NULL,
            cat.api_processed_date = NULL,
            cat.last_updated_by    = 'JCALZADILLA',
            cat.last_update_date   = SYSDATE
        WHERE cat.request_org_id =
              (
                  SELECT ro.request_org_id
                  FROM ops.adre_inv_item_request_org ro
                  WHERE ro.item_request_id   = c_new_request_id
                    AND ro.organization_role = 'MASTER'
              )
          AND cat.ebs_category_set_id =
              l_division_category_set_id;

        IF SQL%ROWCOUNT <> 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20612,
                'Expected exactly 1 Division Category row to update.'
            );

        END IF;


        -- =============================================================
        -- Change the functional Business Unit input:
        -- ENGINEERED TAPE -> ELECTRONICS.
        -- =============================================================

        UPDATE ops.adre_inv_item_category cat
        SET
            cat.ebs_category_id    = l_business_category_id,
            cat.category_value     = l_business_category_value,
            cat.assignment_status  = 'READY',
            cat.api_return_status  = NULL,
            cat.api_message_count  = NULL,
            cat.api_message_text   = NULL,
            cat.api_processed_date = NULL,
            cat.last_updated_by    = 'JCALZADILLA',
            cat.last_update_date   = SYSDATE
        WHERE cat.request_org_id =
              (
                  SELECT ro.request_org_id
                  FROM ops.adre_inv_item_request_org ro
                  WHERE ro.item_request_id   = c_new_request_id
                    AND ro.organization_role = 'MASTER'
              )
          AND cat.ebs_category_set_id =
              l_business_category_set_id;


        IF SQL%ROWCOUNT <> 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20613,
                'Expected exactly 1 Business Unit Category row to update.'
            );

        END IF;


        -- =============================================================
        -- Clone Attribute values.
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
            'JCALZADILLA',
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
                -20611,
                'Expected 10 Attribute Value rows.'
            );

        END IF;


        -- =============================================================
        -- Clone Documents.
        -- =============================================================

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
            'JCALZADILLA',
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


        -- =============================================================
        -- Clone BOM header.
        -- =============================================================

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
            'JCALZADILLA',
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


        -- =============================================================
        -- Clone BOM Components.
        -- =============================================================

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
            'JCALZADILLA',
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
            'Request 9 staged successfully.'
        );

        DBMS_OUTPUT.PUT_LINE
        (
            'TARGET EBS_TEMPLATE_ID is NULL before package execution.'
        );

    END IF;


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
-- Execute ADRE_CREATE_INV_ITEM only when Request 7 is not PROCESSED.
-- =====================================================================

DECLARE

    c_item_request_id
        CONSTANT NUMBER := 9;

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
            'Request 9 is already PROCESSED.'
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
            'TEST V9 / AC-EALC / MH-94904-1009 - PACKAGE START'
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
                'ADRE_CREATE_INV_ITEM returned a non-success status for Request 9.'
            );

        END IF;

    END IF;

END;
/


-- =====================================================================
-- =====================================================================
-- STEP 3
-- APEX / Oracle EBS Item summary.
--
-- IMPORTANT:
-- The SELECT is intentionally stored on one physical line so APEX SQL
-- Scripts cannot concatenate SQL tokens while processing uploaded files.
-- =====================================================================

SELECT r.item_request_id, r.request_number, r.item_number, r.request_status, r.api_return_status AS request_api_status, ro.organization_role, ro.ebs_organization_id, ood.organization_code, ro.ebs_template_id, t.template_name, ro.ebs_inventory_item_id, ro.assignment_status, ro.api_return_status AS org_api_status, kfv.concatenated_segments AS ebs_item_number, msi.mrp_planning_code, msi.outside_operation_flag, msi.dimension_uom_code, msi.unit_width, msi.unit_length, msi.planner_code, msi.planning_make_buy_code, msi.item_type, msi.bom_enabled_flag, msi.eng_item_flag, msi.inventory_item_status_code FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl t ON t.template_id = ro.ebs_template_id LEFT JOIN apps.mtl_system_items_b msi ON msi.inventory_item_id = ro.ebs_inventory_item_id AND msi.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_system_items_kfv kfv ON kfv.inventory_item_id = msi.inventory_item_id AND kfv.organization_id = msi.organization_id WHERE r.item_request_id = 9 ORDER BY CASE ro.organization_role WHEN 'MASTER' THEN 1 WHEN 'TARGET' THEN 2 ELSE 3 END;


-- =====================================================================
-- STEP 4
-- API execution evidence.
--
-- IMPORTANT:
-- The SELECT is intentionally stored on one physical line.
-- =====================================================================

SELECT item_api_log_id, execution_id, request_org_id, process_name, api_name, process_status, api_return_status, api_message_count, message_text FROM ops.adre_inv_item_api_log WHERE item_request_id = 9 ORDER BY item_api_log_id;


-- =====================================================================
-- STEP 5
-- FINAL EXPORT TABLE.
--
-- VERSION:
--   V9-AC-EALC-20260828-01
--
-- IMPORTANT:
-- The compound SELECT is intentionally stored on one physical line.
-- This corrects the ORA-00923 errors seen when APEX SQL Scripts removed
-- line-feed characters and joined tokens such as:
--
--   INVENTORY_ITEM_STATUS_CODE + FROM
--   MESSAGE_TEXT + FROM
--   NOTES + FROM
--
-- Expected result:
--   2 ITEM_ORGANIZATION rows
--   1 TEMPLATE_RULE row
--  10 APEX_ATTRIBUTE rows
--   4 CATEGORY rows
--   7 API_LOG rows
--  -----------------------
--  24 total rows
-- =====================================================================

SELECT 'ITEM_ORGANIZATION' AS validation_group, ro.organization_role AS organization_role, ood.organization_code AS organization_code, r.item_number AS item_number, 'ORGANIZATION_PROCESSING' AS validation_name, ro.assignment_status || ' / ' || NVL(ro.api_return_status, 'NULL') AS source_value, NVL(kfv.concatenated_segments, 'NOT FOUND') || ' / ' || NVL(t.template_name, 'NO TEMPLATE') AS ebs_value, CASE WHEN ro.assignment_status = 'PROCESSED' AND ro.api_return_status = 'S' AND UPPER(TRIM(kfv.concatenated_segments)) = UPPER(TRIM(r.item_number)) THEN 'PASS' ELSE 'DIFFERENT' END AS validation_status, 'APEX Organization processing versus Oracle EBS Item existence and persisted Template.' AS notes FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl t ON t.template_id = ro.ebs_template_id LEFT JOIN apps.mtl_system_items_kfv kfv ON kfv.inventory_item_id = ro.ebs_inventory_item_id AND kfv.organization_id = ro.ebs_organization_id WHERE r.item_request_id = 9 UNION ALL SELECT 'TEMPLATE_RULE', ro.organization_role, ood.organization_code, r.item_number, 'RESOLVE_TARGET_TEMPLATE', tr.division_value || ' / ' || tr.business_unit_value || ' -> ' || expected_template.template_name, NVL(actual_template.template_name, 'NOT RESOLVED'), CASE WHEN lg.process_status = 'SUCCESS' AND lg.api_return_status = 'S' AND ro.ebs_template_id = tr.ebs_template_id THEN 'PASS' ELSE 'DIFFERENT' END, 'Template Rule selected by ADRE_CREATE_INV_ITEM versus the Template persisted on the TARGET Request Organization.' FROM ops.adre_inv_item_api_log lg JOIN ops.adre_inv_item_request r ON r.item_request_id = lg.item_request_id JOIN ops.adre_inv_item_request_org ro ON ro.request_org_id = lg.request_org_id JOIN ops.adre_inv_item_template_rule tr ON tr.item_template_rule_id = lg.entity_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_templates_vl expected_template ON expected_template.template_id = tr.ebs_template_id LEFT JOIN apps.mtl_item_templates_vl actual_template ON actual_template.template_id = ro.ebs_template_id WHERE lg.item_request_id = 9 AND lg.process_name = 'RESOLVE_TARGET_TEMPLATE' UNION ALL SELECT 'APEX_ATTRIBUTE', ro.organization_role, ood.organization_code, r.item_number, a.attribute_code, CASE WHEN av.attribute_char_value IS NOT NULL THEN av.attribute_char_value WHEN av.attribute_number_value IS NOT NULL THEN TO_CHAR(av.attribute_number_value) || CASE WHEN av.value_uom_code IS NOT NULL THEN ' ' || av.value_uom_code END WHEN av.attribute_date_value IS NOT NULL THEN TO_CHAR(av.attribute_date_value, 'YYYY-MM-DD') END, CASE a.attribute_code WHEN 'PLANNING_METHOD' THEN TO_CHAR(master_msi.mrp_planning_code) || ' / ' || NVL ( mrp_ta.report_user_value, 'NO TEMPLATE MAPPING' ) WHEN 'OUTSIDE_PROCESSING' THEN target_msi.outside_operation_flag WHEN 'WIDTH' THEN TO_CHAR(target_msi.unit_width) || ' ' || target_msi.dimension_uom_code WHEN 'TARGET_LENGTH' THEN TO_CHAR(target_msi.unit_length) || ' ' || target_msi.dimension_uom_code ELSE 'NOT SENT BY PACKAGE' END, CASE a.attribute_code WHEN 'PLANNING_METHOD' THEN CASE WHEN mrp_ta.attribute_value IS NOT NULL AND TO_CHAR(master_msi.mrp_planning_code) = TRIM(mrp_ta.attribute_value) AND ( mrp_ta.report_user_value IS NULL OR UPPER(TRIM(av.attribute_char_value)) = UPPER(TRIM(mrp_ta.report_user_value)) ) THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'OUTSIDE_PROCESSING' THEN CASE WHEN UPPER(TRIM(av.attribute_char_value)) = UPPER(TRIM(target_msi.outside_operation_flag)) THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'WIDTH' THEN CASE WHEN CASE UPPER(TRIM(av.value_uom_code)) WHEN 'IN' THEN av.attribute_number_value WHEN 'FT' THEN av.attribute_number_value * 12 END = target_msi.unit_width AND target_msi.dimension_uom_code = 'IN' THEN 'MATCH' ELSE 'DIFFERENT' END WHEN 'TARGET_LENGTH' THEN CASE WHEN CASE UPPER(TRIM(av.value_uom_code)) WHEN 'IN' THEN av.attribute_number_value WHEN 'FT' THEN av.attribute_number_value * 12 END = target_msi.unit_length AND target_msi.dimension_uom_code = 'IN' THEN 'MATCH' ELSE 'DIFFERENT' END ELSE 'NOT MAPPED' END, CASE WHEN a.attribute_code IN ( 'PLANNING_METHOD', 'OUTSIDE_PROCESSING', 'WIDTH', 'TARGET_LENGTH' ) THEN 'Application Attribute versus final Oracle EBS Item value.' ELSE 'Validated in the application but no confirmed direct Oracle EBS mapping is currently implemented.' END FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id JOIN ops.adre_inv_item_attr_value av ON av.request_org_id = ro.request_org_id JOIN ops.adre_inv_item_attribute a ON a.item_attribute_id = av.item_attribute_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id JOIN ops.adre_inv_item_request_org master_ro ON master_ro.item_request_id = r.item_request_id AND master_ro.organization_role = 'MASTER' JOIN apps.mtl_system_items_b master_msi ON master_msi.inventory_item_id = master_ro.ebs_inventory_item_id AND master_msi.organization_id = master_ro.ebs_organization_id JOIN ops.adre_inv_item_request_org target_ro ON target_ro.item_request_id = r.item_request_id AND target_ro.organization_role = 'TARGET' JOIN apps.mtl_system_items_b target_msi ON target_msi.inventory_item_id = target_ro.ebs_inventory_item_id AND target_msi.organization_id = target_ro.ebs_organization_id LEFT JOIN apps.mtl_item_templ_attributes mrp_ta ON mrp_ta.template_id = target_ro.ebs_template_id AND mrp_ta.attribute_name = 'MTL_SYSTEM_ITEMS.MRP_PLANNING_CODE' AND mrp_ta.enabled_flag = 'Y' AND TRIM(mrp_ta.attribute_value) = TO_CHAR(master_msi.mrp_planning_code) WHERE r.item_request_id = 9 UNION ALL SELECT 'CATEGORY', ro.organization_role, ood.organization_code, r.item_number, 'CATEGORY_SET_' || TO_CHAR(cat.ebs_category_set_id), cat.category_value, NVL(mck.concatenated_segments, 'NOT ASSIGNED'), CASE WHEN mic.category_id = cat.ebs_category_id AND cat.assignment_status = 'PROCESSED' AND cat.api_return_status = 'S' THEN 'MATCH' ELSE 'DIFFERENT' END, 'APEX Category assignment versus final Oracle EBS Category assignment.' FROM ops.adre_inv_item_request r JOIN ops.adre_inv_item_request_org ro ON ro.item_request_id = r.item_request_id JOIN ops.adre_inv_item_category cat ON cat.request_org_id = ro.request_org_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id LEFT JOIN apps.mtl_item_categories mic ON mic.inventory_item_id = ro.ebs_inventory_item_id AND mic.organization_id = ro.ebs_organization_id AND mic.category_set_id = cat.ebs_category_set_id AND mic.category_id = cat.ebs_category_id LEFT JOIN apps.mtl_categories_kfv mck ON mck.category_id = mic.category_id WHERE r.item_request_id = 9 UNION ALL SELECT 'API_LOG', NVL(ro.organization_role, 'REQUEST'), ood.organization_code, r.item_number, lg.process_name, NVL(lg.api_name, 'INTERNAL'), lg.process_status || ' / ' || NVL(lg.api_return_status, 'NULL'), CASE WHEN lg.process_status = 'SUCCESS' AND lg.api_return_status = 'S' THEN 'PASS' ELSE 'DIFFERENT' END, DBMS_LOB.SUBSTR ( lg.message_text, 1000, 1 ) FROM ops.adre_inv_item_api_log lg JOIN ops.adre_inv_item_request r ON r.item_request_id = lg.item_request_id LEFT JOIN ops.adre_inv_item_request_org ro ON ro.request_org_id = lg.request_org_id LEFT JOIN apps.org_organization_definitions ood ON ood.organization_id = ro.ebs_organization_id WHERE lg.item_request_id = 9 ORDER BY 1, 2, 5;

-- =====================================================================
-- JCALZADILLA - 28.08.2026 - END CHANGE
-- =====================================================================
