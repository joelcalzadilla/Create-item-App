-- =====================================================================
-- JCALZADILLA - 25.08.2026 - START CHANGE
-- Purpose:
-- Create the ADRE_CREATE_INV_ITEM package body for the final
-- Adhesives Research, Inc. Inventory Item Creation data model.
--
-- This package replaces the previous staging-table implementation.
-- It does not use:
--
--   OPS.ADRE_ITEM_CREATION_STG
--   OPS.ADRE_ITEM_CATEGORY_STG
--   OPS.ADRE_CAT_SETS
--
-- The package reads the final request model directly and uses existing
-- Oracle EBS identifiers stored in the application tables.
--
-- Revision included in this version:
--   - MASTER and TARGET EBS Template IDs may differ.
--   - MASTER template is used by PROCESS_ITEM CREATE.
--   - TARGET Item is first assigned with ASSIGN_ITEM_TO_ORG.
--   - TARGET EBS Template is then applied with PROCESS_ITEM UPDATE.
--   - BOM_ENABLED_FLAG is derived from the request BOM data.
--   - ENG_ITEM_FLAG is derived from ENGINEERING_STATUS.
--   - Oracle EBS API errors preserve RETURN_STATUS, MSG_COUNT and
--     available FND message text in the application tables and API log.
--
-- JCALZADILLA - 26.08.2026:
--   - TARGET Template processing uses PROCESS_ITEM overload 2.
--   - MASTER-controlled MRP_PLANNING_CODE is preserved for TARGET Items.
--   - PROCESS_ITEM X_MSG_DATA is captured.
--   - ERROR_HANDLER messages are captured for Item API validation errors.
--
-- JCALZADILLA - 27.08.2026:
--   - Confirmed application Attribute mappings are now sent to Oracle EBS.
--   - PLANNING_METHOD is applied to the MASTER as MRP_PLANNING_CODE.
--   - OUTSIDE_PROCESSING is applied to TARGET Organizations as
--     OUTSIDE_OPERATION_FLAG.
--   - WIDTH and TARGET_LENGTH are normalized to inches and applied as
--     UNIT_WIDTH / UNIT_LENGTH with DIMENSION_UOM_CODE = IN.
--   - MASTER Attributes are applied before TARGET Template processing.
--   - TARGET Template processing uses the actual Oracle EBS Item segments.
--   - Remaining unconfirmed application Attributes continue to be validated
--     locally but are not transmitted to Oracle EBS.
--
-- JCALZADILLA - 27.08.2026:
--   - TARGET Template selection is resolved by the main package through
--     OPS.ADRE_INV_ITEM_TEMPLATE_RULE.
--   - Template Rule matching uses Item Type, TARGET Organization, request
--     Category values for Division / Business Unit, and EXPENSE_ITEM_FLAG
--     when the rule requires it.
--   - The resolved TARGET EBS_TEMPLATE_ID is written back to
--     ADRE_INV_ITEM_REQUEST_ORG for auditability.
--   - TARGET Template IDs no longer need to be supplied by test scripts.
--   - PLANNING_METHOD no longer hard-codes an Oracle EBS planning code.
--     The code is resolved from the selected TARGET Template metadata.
--
-- JCALZADILLA - 31.08.2026 - V6:
--   - Added explicit RAW_MATERIAL_ITEM Attribute support.
--   - ENGINEERING_ITEM_FLAG now controls EBS ENG_ITEM_FLAG when supplied.
--     ENGINEERING_STATUS remains the backward-compatible fallback.
--   - HIMS is applied to MASTER Items through ATTRIBUTE14.
--   - PRICE_PER_UOM is applied to TARGET Items through LIST_PRICE_PER_UNIT.
--   - LEAD_TIME_DAYS is applied to TARGET Items through ATTRIBUTE15.
--   - EXPENSE_ITEM_FLAG remains a Template Rule input only and is not
--     written directly to an Oracle EBS Item Attribute.
--
-- JCALZADILLA - 31.08.2026 - V7:
--   - RAW_MATERIAL_ITEM LEAD_TIME_DAYS is now applied to both the
--     LEADTIME flexfield (ATTRIBUTE15) and the standard FULL_LEAD_TIME
--     Item Attribute, per the confirmed Raw Material functional rule.
--   - Existing V6 behavior and mappings remain unchanged.
-- =====================================================================

CREATE OR REPLACE PACKAGE BODY apps.adre_create_inv_item AS

    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Constants.
    -- =================================================================

    c_application_code         CONSTANT VARCHAR2(30) := 'XINV';

    c_return_success           CONSTANT VARCHAR2(1)  := 'S';
    c_return_error             CONSTANT VARCHAR2(1)  := 'E';
    c_return_unexpected        CONSTANT VARCHAR2(1)  := 'U';

    c_api_true                 CONSTANT VARCHAR2(1)  := 'T';
    c_api_false                CONSTANT VARCHAR2(1)  := 'F';

    c_request_ready            CONSTANT VARCHAR2(30) := 'READY';
    c_request_processing       CONSTANT VARCHAR2(30) := 'PROCESSING';
    c_request_processed        CONSTANT VARCHAR2(30) := 'PROCESSED';
    c_request_error            CONSTANT VARCHAR2(30) := 'ERROR';

    c_assignment_ready         CONSTANT VARCHAR2(30) := 'READY';
    c_assignment_processing    CONSTANT VARCHAR2(30) := 'PROCESSING';
    c_assignment_processed     CONSTANT VARCHAR2(30) := 'PROCESSED';
    c_assignment_error         CONSTANT VARCHAR2(30) := 'ERROR';
    c_assignment_skipped       CONSTANT VARCHAR2(30) := 'SKIPPED';

    c_category_control_item    CONSTANT NUMBER := 1;
    c_category_control_org     CONSTANT NUMBER := 2;

    c_missing_char             CONSTANT VARCHAR2(1) := CHR(0);

    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Existing EBS security context values already proven by the
    -- previous integration package.
    -- =================================================================

    g_user_name                VARCHAR2(100) := 'CWILLS';
    g_application_name         VARCHAR2(100) := 'Inventory';
    g_responsibility_key       VARCHAR2(100) := 'INVENTORY';

    g_user_id                  NUMBER := NULL;
    g_resp_id                  NUMBER := NULL;
    g_application_id           NUMBER := NULL;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Append one line to a temporary CLOB.
    -- =================================================================

    PROCEDURE pcd_append_text
    (
        io_clob IN OUT NOCOPY CLOB,
        p_text  IN            VARCHAR2
    )
    IS
    BEGIN

        IF io_clob IS NULL THEN
            DBMS_LOB.CREATETEMPORARY
            (
                io_clob,
                TRUE
            );
        END IF;

        DBMS_LOB.APPEND
        (
            io_clob,
            TO_CLOB
            (
                NVL(p_text, '') || CHR(10)
            )
        );

    END pcd_append_text;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Return the APEX user when available.
    -- =================================================================

    FUNCTION f_get_session_user
    RETURN VARCHAR2
    IS
    BEGIN

        RETURN NVL
               (
                   SYS_CONTEXT
                   (
                       'APEX$SESSION',
                       'APP_USER'
                   ),
                   USER
               );

    END f_get_session_user;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Preserve the proven legacy OPS.PKG_LOG diagnostic logging.
    -- Logging failures do not stop Item creation.
    -- =================================================================

    PROCEDURE pcd_write_log
    (
        p_business_process IN VARCHAR2,
        p_message          IN VARCHAR2
    )
    IS
    BEGIN

        EXECUTE IMMEDIATE
            'BEGIN ops.pkg_log.sp_insert_message(' ||
            'p_co_aplication => :1, ' ||
            'p_tx_business_process => :2, ' ||
            'p_tx_message => :3); END;'
        USING
            c_application_code,
            SUBSTR(p_business_process, 1, 240),
            SUBSTR(p_message, 1, 3900);

    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END pcd_write_log;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Write one structured integration record to the final application
    -- API log table.
    -- =================================================================

    PROCEDURE pcd_insert_api_log
    (
        p_execution_id       IN VARCHAR2,
        p_item_request_id    IN NUMBER,
        p_request_org_id     IN NUMBER,
        p_process_name       IN VARCHAR2,
        p_api_name           IN VARCHAR2,
        p_entity_type        IN VARCHAR2,
        p_entity_id          IN NUMBER,
        p_log_level          IN VARCHAR2,
        p_process_status     IN VARCHAR2,
        p_api_return_status  IN VARCHAR2,
        p_api_message_count  IN NUMBER,
        p_message_text       IN CLOB
    )
    IS
    BEGIN

        INSERT INTO ops.adre_inv_item_api_log
        (
            execution_id,
            item_request_id,
            request_org_id,
            process_name,
            api_name,
            entity_type,
            entity_id,
            log_level,
            process_status,
            api_return_status,
            api_message_count,
            message_text,
            execution_start_date,
            execution_end_date,
            elapsed_milliseconds
        )
        VALUES
        (
            p_execution_id,
            p_item_request_id,
            p_request_org_id,
            p_process_name,
            p_api_name,
            p_entity_type,
            p_entity_id,
            p_log_level,
            p_process_status,
            p_api_return_status,
            NVL(p_api_message_count, 0),
            p_message_text,
            SYSDATE,
            SYSDATE,
            NULL
        );

    END pcd_insert_api_log;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Resolve configured EBS user / responsibility context.
    -- =================================================================

    PROCEDURE set_env
    IS
    BEGIN

        BEGIN
            SELECT
                user_id
            INTO
                g_user_id
            FROM apps.fnd_user
            WHERE user_name = g_user_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                g_user_id := NULL;
        END;


        BEGIN
            SELECT
                application_id
            INTO
                g_application_id
            FROM apps.fnd_application_vl
            WHERE application_name = g_application_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                g_application_id := NULL;
        END;


        BEGIN
            SELECT
                responsibility_id
            INTO
                g_resp_id
            FROM apps.fnd_responsibility_vl
            WHERE responsibility_key = g_responsibility_key;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                g_resp_id := NULL;
        END;

    END set_env;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Initialize Oracle EBS application context.
    -- =================================================================

    PROCEDURE pcd_initialize_ebs_context
    (
        p_user_id      IN NUMBER,
        p_resp_id      IN NUMBER,
        p_resp_appl_id IN NUMBER
    )
    IS
    BEGIN

        IF p_user_id IS NULL
           OR p_resp_id IS NULL
           OR p_resp_appl_id IS NULL
        THEN
            RAISE_APPLICATION_ERROR
            (
                -20101,
                'Oracle EBS application context is incomplete.'
            );
        END IF;


        apps.fnd_global.apps_initialize
        (
            user_id      => p_user_id,
            resp_id      => p_resp_id,
            resp_appl_id => p_resp_appl_id
        );


        BEGIN
            apps.mo_global.init
            (
                'INV'
            );
        EXCEPTION
            WHEN OTHERS THEN
                pcd_write_log
                (
                    'PCD_INITIALIZE_EBS_CONTEXT',
                    'MO_GLOBAL.INIT returned: ' || SQLERRM
                );
        END;

    END pcd_initialize_ebs_context;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Return Oracle EBS API messages.
    -- =================================================================

    FUNCTION f_get_api_messages
    (
        p_msg_count IN NUMBER,
        p_msg_data  IN VARCHAR2 DEFAULT NULL
    )
    RETURN CLOB
    IS

        l_message_text
            CLOB;

        l_fnd_message
            VARCHAR2(4000);

        l_msg_index_out
            NUMBER;

        l_stack_count
            NUMBER;

        l_stack_data
            VARCHAR2(4000);

    BEGIN

        DBMS_LOB.CREATETEMPORARY
        (
            l_message_text,
            TRUE
        );


        IF p_msg_data IS NOT NULL THEN
            pcd_append_text
            (
                l_message_text,
                'API message data: ' || p_msg_data
            );
        END IF;


        BEGIN

            apps.fnd_msg_pub.count_and_get
            (
                p_encoded => apps.fnd_api.g_false,
                p_count   => l_stack_count,
                p_data    => l_stack_data
            );


            IF l_stack_data IS NOT NULL THEN
                pcd_append_text
                (
                    l_message_text,
                    'FND stack data: ' || l_stack_data
                );
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                pcd_append_text
                (
                    l_message_text,
                    'Could not call FND_MSG_PUB.COUNT_AND_GET: ' ||
                    SQLERRM
                );
        END;


        IF NVL(p_msg_count, 0) > 0 THEN

            FOR i IN 1 .. p_msg_count
            LOOP

                BEGIN

                    apps.fnd_msg_pub.get
                    (
                        p_msg_index     => i,
                        p_encoded       => apps.fnd_api.g_false,
                        p_data          => l_fnd_message,
                        p_msg_index_out => l_msg_index_out
                    );


                    IF l_fnd_message IS NOT NULL THEN
                        pcd_append_text
                        (
                            l_message_text,
                            'FND message ' || i || ': ' ||
                            l_fnd_message
                        );
                    END IF;

                EXCEPTION
                    WHEN OTHERS THEN
                        pcd_append_text
                        (
                            l_message_text,
                            'Could not read FND message ' || i || ': ' ||
                            SQLERRM
                        );
                END;

            END LOOP;

        END IF;


        IF DBMS_LOB.GETLENGTH(l_message_text) = 0 THEN
            pcd_append_text
            (
                l_message_text,
                'No detailed Oracle EBS API message was returned.'
            );
        END IF;


        RETURN l_message_text;

    END f_get_api_messages;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Return CHR(0) for an optional character parameter that is NULL.
    -- =================================================================

    FUNCTION f_optional_char
    (
        p_value IN VARCHAR2
    )
    RETURN VARCHAR2
    IS
    BEGIN

        RETURN NVL
               (
                   p_value,
                   c_missing_char
               );

    END f_optional_char;


    -- =================================================================
    -- JCALZADILLA - 27.08.2026 - START CHANGE
    -- Purpose:
    -- Normalize confirmed dimensional application Attribute values to
    -- inches before sending them to Oracle EBS Item dimensions.
    --
    -- The mappings proven by Test V4.2 currently support IN and FT.
    -- Additional UOM conversions must be explicitly validated before they
    -- are added here.
    -- =================================================================

    FUNCTION f_dimension_to_inches
    (
        p_value IN NUMBER,
        p_uom   IN VARCHAR2
    )
    RETURN NUMBER
    IS
    BEGIN

        IF p_value IS NULL THEN
            RETURN NULL;
        END IF;


        IF UPPER(TRIM(p_uom)) = 'IN' THEN

            RETURN p_value;

        ELSIF UPPER(TRIM(p_uom)) = 'FT' THEN

            RETURN p_value * 12;

        ELSE

            RAISE_APPLICATION_ERROR
            (
                -20130,
                'Unsupported dimensional UOM. UOM=' ||
                NVL(p_uom, 'NULL')
            );

        END IF;

    END f_dimension_to_inches;

    -- =================================================================
    -- JCALZADILLA - 27.08.2026 - END CHANGE
    -- =================================================================


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Resolve an Oracle EBS Organization Code from Organization ID.
    -- =================================================================

    FUNCTION f_get_org_code
    (
        p_organization_id IN NUMBER
    )
    RETURN VARCHAR2
    IS

        l_organization_code
            VARCHAR2(30);

    BEGIN

        SELECT
            organization_code
        INTO
            l_organization_code
        FROM apps.mtl_parameters
        WHERE organization_id = p_organization_id;


        RETURN l_organization_code;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR
            (
                -20102,
                'Oracle EBS Inventory Organization was not found. ' ||
                'ORGANIZATION_ID=' || p_organization_id
            );
    END f_get_org_code;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Check whether an Item exists in one Oracle EBS organization.
    -- =================================================================

    FUNCTION f_item_exists
    (
        p_item_number        IN  VARCHAR2,
        p_organization_id    IN  NUMBER,
        x_inventory_item_id  OUT NUMBER,
        x_item_status_code   OUT VARCHAR2
    )
    RETURN BOOLEAN
    IS
    BEGIN

        SELECT
            msik.inventory_item_id,
            msi.inventory_item_status_code
        INTO
            x_inventory_item_id,
            x_item_status_code
        FROM apps.mtl_system_items_kfv msik
        JOIN apps.mtl_system_items_b msi
          ON msi.inventory_item_id = msik.inventory_item_id
         AND msi.organization_id   = msik.organization_id
        WHERE UPPER(TRIM(msik.concatenated_segments)) =
              UPPER(TRIM(p_item_number))
          AND msik.organization_id = p_organization_id
          AND ROWNUM = 1;


        RETURN TRUE;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            x_inventory_item_id := NULL;
            x_item_status_code  := NULL;
            RETURN FALSE;
    END f_item_exists;


    -- =================================================================
    -- JCALZADILLA - 27.08.2026 - START CHANGE
    -- Purpose:
    -- Resolve one TARGET EBS Item Template from application configuration.
    --
    -- No Oracle EBS Organization ID, Template ID, Category Set ID, or
    -- Category ID is hard-coded by this resolver.
    --
    -- Rule matching:
    --   - Item Type must match the Request Item Type.
    --   - EBS Organization must match the TARGET Request Organization.
    --   - DIVISION_VALUE, when configured, must exist among the Request
    --     Category values.
    --   - BUSINESS_UNIT_VALUE, when configured, must exist among the
    --     Request Category values.
    --   - EXPENSE_ITEM_FLAG, when configured, must match the Request
    --     EXPENSE_ITEM_FLAG application Attribute.
    --   - Rule must be READY, active, and effective today.
    --
    -- The lowest RULE_PRIORITY wins. More than one matching rule at the
    -- same winning priority is rejected as ambiguous configuration.
    -- =================================================================

    PROCEDURE pcd_resolve_target_template_rule
    (
        p_item_request_id          IN  NUMBER,
        p_item_type_id             IN  NUMBER,
        p_target_organization_id   IN  NUMBER,
        x_item_template_rule_id    OUT NUMBER,
        x_ebs_template_id          OUT NUMBER,
        x_template_name            OUT VARCHAR2,
        x_rule_priority            OUT NUMBER
    )
    IS

        l_priority_match_count
            NUMBER;

    BEGIN

        SELECT
            q.item_template_rule_id,
            q.ebs_template_id,
            q.template_name,
            q.rule_priority,
            q.priority_match_count
        INTO
            x_item_template_rule_id,
            x_ebs_template_id,
            x_template_name,
            x_rule_priority,
            l_priority_match_count
        FROM
        (
            SELECT
                tr.item_template_rule_id,
                tr.ebs_template_id,
                mt.template_name,
                tr.rule_priority,

                ROW_NUMBER() OVER
                (
                    ORDER BY
                        NVL(tr.rule_priority, 999999999),
                        tr.item_template_rule_id
                ) AS rule_row_number,

                COUNT(*) OVER
                (
                    PARTITION BY NVL(tr.rule_priority, 999999999)
                ) AS priority_match_count

            FROM ops.adre_inv_item_template_rule tr

            JOIN apps.mtl_item_templates_vl mt
              ON mt.template_id = tr.ebs_template_id

            WHERE tr.item_type_id =
                  p_item_type_id

              AND tr.ebs_organization_id =
                  p_target_organization_id

              AND UPPER(TRIM(NVL(tr.rule_status, 'READY'))) =
                  'READY'

              AND NVL(tr.active_flag, 'N') =
                  'Y'

              AND
                  (
                      tr.effective_start_date IS NULL
                      OR TRUNC(tr.effective_start_date) <= TRUNC(SYSDATE)
                  )

              AND
                  (
                      tr.effective_end_date IS NULL
                      OR TRUNC(tr.effective_end_date) >= TRUNC(SYSDATE)
                  )

              AND
                  (
                      tr.division_value IS NULL

                      OR EXISTS
                         (
                             SELECT 1
                             FROM ops.adre_inv_item_category cat
                             JOIN ops.adre_inv_item_request_org ro
                               ON ro.request_org_id = cat.request_org_id
                             WHERE ro.item_request_id = p_item_request_id
                               AND UPPER(TRIM(cat.category_value)) =
                                   UPPER(TRIM(tr.division_value))
                         )
                  )

              AND
                  (
                      tr.business_unit_value IS NULL

                      OR EXISTS
                         (
                             SELECT 1
                             FROM ops.adre_inv_item_category cat
                             JOIN ops.adre_inv_item_request_org ro
                               ON ro.request_org_id = cat.request_org_id
                             WHERE ro.item_request_id = p_item_request_id
                               AND UPPER(TRIM(cat.category_value)) =
                                   UPPER(TRIM(tr.business_unit_value))
                         )
                  )

              AND
                  (
                      tr.expense_item_flag IS NULL

                      OR EXISTS
                         (
                             SELECT 1
                             FROM ops.adre_inv_item_attr_value av
                             JOIN ops.adre_inv_item_request_org ro
                               ON ro.request_org_id = av.request_org_id
                             JOIN ops.adre_inv_item_attribute a
                               ON a.item_attribute_id = av.item_attribute_id
                             WHERE ro.item_request_id = p_item_request_id
                               AND a.attribute_code = 'EXPENSE_ITEM_FLAG'
                               AND UPPER(TRIM(av.attribute_char_value)) =
                                   UPPER(TRIM(tr.expense_item_flag))
                         )
                  )
        ) q

        WHERE q.rule_row_number = 1;


        IF l_priority_match_count > 1 THEN

            RAISE_APPLICATION_ERROR
            (
                -20140,
                'Ambiguous TARGET Template configuration. ' ||
                'More than one Template Rule matches the winning priority. ' ||
                'ITEM_REQUEST_ID=' ||
                p_item_request_id ||
                ', TARGET_ORGANIZATION_ID=' ||
                p_target_organization_id ||
                ', RULE_PRIORITY=' ||
                NVL(TO_CHAR(x_rule_priority), 'NULL')
            );

        END IF;


        IF x_ebs_template_id IS NULL THEN

            RAISE_APPLICATION_ERROR
            (
                -20141,
                'The resolved TARGET Template Rule does not contain EBS_TEMPLATE_ID. ' ||
                'ITEM_TEMPLATE_RULE_ID=' ||
                x_item_template_rule_id
            );

        END IF;


    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            RAISE_APPLICATION_ERROR
            (
                -20142,
                'No active TARGET Template Rule matched the Item Request. ' ||
                'ITEM_REQUEST_ID=' ||
                p_item_request_id ||
                ', ITEM_TYPE_ID=' ||
                p_item_type_id ||
                ', TARGET_ORGANIZATION_ID=' ||
                p_target_organization_id
            );

    END pcd_resolve_target_template_rule;

    -- =================================================================
    -- JCALZADILLA - 27.08.2026 - END CHANGE
    -- =================================================================


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Validate that all required dynamic application attributes have a
    -- READY typed value in the request model.
    --
    -- Confirmed mappings are transmitted later by PCD_PROCESS_REQUEST.
    -- Attributes without a confirmed mapping remain application-only.
    -- =================================================================

    PROCEDURE pcd_validate_required_attributes
    (
        p_item_request_id IN NUMBER
    )
    IS

        l_missing_count
            NUMBER;

    BEGIN

        SELECT
            COUNT(*)
        INTO
            l_missing_count
        FROM ops.adre_inv_item_request r
        JOIN ops.adre_inv_item_type_attr ta
          ON ta.item_type_id = r.item_type_id
         AND ta.active_flag  = 'Y'
         AND ta.required_flag = 'Y'
        JOIN ops.adre_inv_item_request_org ro
          ON ro.item_request_id = r.item_request_id
         AND
         (
                ta.organization_scope = ro.organization_role
             OR ta.organization_scope = 'BOTH'
         )
        LEFT JOIN ops.adre_inv_item_attr_value av
          ON av.request_org_id    = ro.request_org_id
         AND av.item_attribute_id = ta.item_attribute_id
        WHERE r.item_request_id = p_item_request_id
          AND
          (
                 av.item_attr_value_id IS NULL
              OR NVL(av.value_status, 'DRAFT') <> 'READY'
              OR
                 (
                     av.attribute_char_value   IS NULL
                 AND av.attribute_number_value IS NULL
                 AND av.attribute_date_value   IS NULL
                 )
          );


        IF l_missing_count > 0 THEN

            RAISE_APPLICATION_ERROR
            (
                -20103,
                'The Item Request has ' ||
                l_missing_count ||
                ' required application attribute value(s) that are missing or not READY.'
            );

        END IF;

    END pcd_validate_required_attributes;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Process saved Category rows directly from ADRE_INV_ITEM_CATEGORY.
    --
    -- Important:
    -- MTL_CATEGORY_SET_VALID_CATS is intentionally not used as a hard
    -- gate. Existing production assignments have demonstrated that it is
    -- not a reliable sole source for every valid assignment in this EBS
    -- environment. The package validates that the Category and Category
    -- Set exist, then lets INV_ITEM_CATEGORY_PUB perform the definitive
    -- EBS business validation.
    -- =================================================================

    PROCEDURE pcd_assign_categories
    (
        p_item_request_id      IN  NUMBER,
        p_user_id              IN  NUMBER   DEFAULT NULL,
        p_resp_id              IN  NUMBER   DEFAULT NULL,
        p_resp_appl_id         IN  NUMBER   DEFAULT NULL,
        p_commit_flag          IN  VARCHAR2 DEFAULT 'N',
        x_return_status        OUT VARCHAR2,
        x_message              OUT CLOB
    )
    IS

        l_context_user_id
            NUMBER;

        l_context_resp_id
            NUMBER;

        l_context_resp_appl_id
            NUMBER;

        l_inventory_item_id
            NUMBER;

        l_item_status_code
            VARCHAR2(30);

        l_existing_category_id
            NUMBER;

        l_category_exists
            NUMBER;

        l_category_set_exists
            NUMBER;

        l_return_status
            VARCHAR2(1);

        l_error_code
            NUMBER;

        l_msg_count
            NUMBER;

        l_msg_data
            VARCHAR2(4000);

        l_api_message
            CLOB;

        l_error_text
            VARCHAR2(4000);

        l_success_count
            NUMBER := 0;

        l_error_count
            NUMBER := 0;

        l_skipped_count
            NUMBER := 0;

        l_commit_flag
            VARCHAR2(1);


        CURSOR c_categories
        IS
            SELECT
                cat.item_category_id,
                cat.request_org_id,
                cat.ebs_category_set_id,
                cat.ebs_category_id,
                cat.category_value,
                cat.assignment_status,
                ro.ebs_organization_id,
                ro.organization_role,
                ro.ebs_inventory_item_id,
                r.item_number,
                cs.control_level
            FROM ops.adre_inv_item_category cat
            JOIN ops.adre_inv_item_request_org ro
              ON ro.request_org_id = cat.request_org_id
            JOIN ops.adre_inv_item_request r
              ON r.item_request_id = ro.item_request_id
            LEFT JOIN apps.mtl_category_sets_b cs
              ON cs.category_set_id = cat.ebs_category_set_id
            WHERE r.item_request_id = p_item_request_id
              AND cat.ebs_category_set_id IS NOT NULL
              AND cat.ebs_category_id IS NOT NULL
              AND NVL(cat.assignment_status, c_assignment_ready)
                  <> c_assignment_processed
            ORDER BY
                CASE ro.organization_role
                    WHEN 'MASTER' THEN 1
                    WHEN 'TARGET' THEN 2
                    ELSE 3
                END,
                ro.ebs_organization_id,
                cat.ebs_category_set_id;

    BEGIN

        x_return_status := c_return_success;
        x_message       := NULL;

        DBMS_LOB.CREATETEMPORARY
        (
            x_message,
            TRUE
        );


        l_commit_flag :=
            CASE
                WHEN UPPER(TRIM(NVL(p_commit_flag, 'N'))) = 'Y'
                    THEN 'Y'
                ELSE 'N'
            END;


        set_env;

        l_context_user_id :=
            NVL
            (
                p_user_id,
                g_user_id
            );

        l_context_resp_id :=
            NVL
            (
                p_resp_id,
                g_resp_id
            );

        l_context_resp_appl_id :=
            NVL
            (
                p_resp_appl_id,
                g_application_id
            );


        pcd_initialize_ebs_context
        (
            p_user_id      => l_context_user_id,
            p_resp_id      => l_context_resp_id,
            p_resp_appl_id => l_context_resp_appl_id
        );


        FOR r IN c_categories
        LOOP

            BEGIN

                l_inventory_item_id    := r.ebs_inventory_item_id;
                l_existing_category_id := NULL;
                l_return_status        := NULL;
                l_error_code           := NULL;
                l_msg_count            := 0;
                l_msg_data             := NULL;
                l_api_message          := NULL;


                -- =====================================================
                -- JCALZADILLA - 25.08.2026
                -- Item/master-controlled Category Sets are processed only
                -- from the MASTER request organization.
                -- =====================================================

                IF r.control_level = c_category_control_item
                   AND r.organization_role <> 'MASTER'
                THEN

                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_skipped,
                        api_return_status  = c_return_success,
                        api_message_count  = 0,
                        api_message_text   =
                            TO_CLOB
                            (
                                'Skipped because the Category Set is item/master controlled.'
                            ),
                        api_processed_date = SYSDATE
                    WHERE item_category_id = r.item_category_id;

                    l_skipped_count := l_skipped_count + 1;

                    CONTINUE;

                END IF;


                SELECT
                    COUNT(*)
                INTO
                    l_category_set_exists
                FROM apps.mtl_category_sets_b
                WHERE category_set_id = r.ebs_category_set_id;


                IF l_category_set_exists = 0 THEN
                    RAISE_APPLICATION_ERROR
                    (
                        -20120,
                        'Category Set does not exist in Oracle EBS. CATEGORY_SET_ID=' ||
                        r.ebs_category_set_id
                    );
                END IF;


                SELECT
                    COUNT(*)
                INTO
                    l_category_exists
                FROM apps.mtl_categories_kfv
                WHERE category_id = r.ebs_category_id;


                IF l_category_exists = 0 THEN
                    RAISE_APPLICATION_ERROR
                    (
                        -20121,
                        'Category does not exist in Oracle EBS. CATEGORY_ID=' ||
                        r.ebs_category_id
                    );
                END IF;


                IF l_inventory_item_id IS NULL THEN

                    IF NOT f_item_exists
                    (
                        p_item_number       => r.item_number,
                        p_organization_id   => r.ebs_organization_id,
                        x_inventory_item_id => l_inventory_item_id,
                        x_item_status_code  => l_item_status_code
                    )
                    THEN
                        RAISE_APPLICATION_ERROR
                        (
                            -20122,
                            'Item does not exist in Oracle EBS for Category processing. ' ||
                            'ITEM_NUMBER=' || r.item_number ||
                            ', ORGANIZATION_ID=' || r.ebs_organization_id
                        );
                    END IF;

                END IF;


                UPDATE ops.adre_inv_item_category
                SET assignment_status = c_assignment_processing
                WHERE item_category_id = r.item_category_id;


                BEGIN

                    SELECT
                        mic.category_id
                    INTO
                        l_existing_category_id
                    FROM apps.mtl_item_categories mic
                    WHERE mic.inventory_item_id = l_inventory_item_id
                      AND mic.organization_id   = r.ebs_organization_id
                      AND mic.category_set_id   = r.ebs_category_set_id
                      AND ROWNUM = 1;

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        l_existing_category_id := NULL;
                END;


                IF l_existing_category_id IS NULL THEN

                    BEGIN
                        apps.fnd_msg_pub.initialize;
                    EXCEPTION
                        WHEN OTHERS THEN
                            NULL;
                    END;


                    apps.inv_item_category_pub.create_category_assignment
                    (
                        p_api_version       => 1.0,
                        p_init_msg_list     => c_api_true,
                        p_commit            => c_api_false,
                        x_return_status     => l_return_status,
                        x_errorcode         => l_error_code,
                        x_msg_count         => l_msg_count,
                        x_msg_data          => l_msg_data,
                        p_category_id       => r.ebs_category_id,
                        p_category_set_id   => r.ebs_category_set_id,
                        p_inventory_item_id => l_inventory_item_id,
                        p_organization_id   => r.ebs_organization_id
                    );


                    l_api_message :=
                        f_get_api_messages
                        (
                            l_msg_count,
                            l_msg_data
                        );

                ELSIF l_existing_category_id = r.ebs_category_id THEN

                    l_return_status := c_return_success;
                    l_msg_count     := 0;

                    l_api_message :=
                        TO_CLOB
                        (
                            'Category assignment already exists in Oracle EBS.'
                        );

                ELSE

                    BEGIN
                        apps.fnd_msg_pub.initialize;
                    EXCEPTION
                        WHEN OTHERS THEN
                            NULL;
                    END;


                    apps.inv_item_category_pub.update_category_assignment
                    (
                        p_api_version       => 1.0,
                        p_init_msg_list     => c_api_true,
                        p_commit            => c_api_false,
                        p_category_id       => r.ebs_category_id,
                        p_old_category_id   => l_existing_category_id,
                        p_category_set_id   => r.ebs_category_set_id,
                        p_inventory_item_id => l_inventory_item_id,
                        p_organization_id   => r.ebs_organization_id,
                        x_return_status     => l_return_status,
                        x_errorcode         => l_error_code,
                        x_msg_count         => l_msg_count,
                        x_msg_data          => l_msg_data
                    );


                    l_api_message :=
                        f_get_api_messages
                        (
                            l_msg_count,
                            l_msg_data
                        );

                END IF;


                IF l_return_status = c_return_success THEN

                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_processed,
                        api_return_status  = l_return_status,
                        api_message_count  = NVL(l_msg_count, 0),
                        api_message_text   = l_api_message,
                        api_processed_date = SYSDATE
                    WHERE item_category_id = r.item_category_id;


                    l_success_count :=
                        l_success_count + 1;

                ELSE

                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_error,
                        api_return_status  =
                            NVL
                            (
                                l_return_status,
                                c_return_error
                            ),
                        api_message_count =
                            NVL
                            (
                                l_msg_count,
                                1
                            ),
                        api_message_text   = l_api_message,
                        api_processed_date = SYSDATE
                    WHERE item_category_id = r.item_category_id;


                    l_error_count :=
                        l_error_count + 1;

                    x_return_status :=
                        c_return_error;

                END IF;


            EXCEPTION
                WHEN OTHERS THEN

                    l_error_text :=
                        'Category processing failed. ITEM_CATEGORY_ID=' ||
                        r.item_category_id ||
                        ', ORGANIZATION_ID=' ||
                        r.ebs_organization_id ||
                        ', CATEGORY_SET_ID=' ||
                        r.ebs_category_set_id ||
                        ', CATEGORY_ID=' ||
                        r.ebs_category_id ||
                        ', SQLERRM=' ||
                        SQLERRM ||
                        ', BACKTRACE=' ||
                        DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;


                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_error,
                        api_return_status  = c_return_unexpected,
                        api_message_count  = 1,
                        api_message_text   = TO_CLOB(l_error_text),
                        api_processed_date = SYSDATE
                    WHERE item_category_id = r.item_category_id;


                    l_error_count :=
                        l_error_count + 1;

                    x_return_status :=
                        c_return_error;


                    pcd_write_log
                    (
                        'PCD_ASSIGN_CATEGORIES',
                        l_error_text
                    );

            END;

        END LOOP;


        pcd_append_text
        (
            x_message,
            'Category processing completed.'
        );

        pcd_append_text
        (
            x_message,
            'Successful rows: ' || l_success_count
        );

        pcd_append_text
        (
            x_message,
            'Skipped rows: ' || l_skipped_count
        );

        pcd_append_text
        (
            x_message,
            'Error rows: ' || l_error_count
        );


        IF l_commit_flag = 'Y' THEN

            IF x_return_status = c_return_success THEN
                COMMIT;
            ELSE
                ROLLBACK;
            END IF;

        END IF;


    EXCEPTION
        WHEN OTHERS THEN

            x_return_status :=
                c_return_unexpected;

            IF x_message IS NULL THEN
                DBMS_LOB.CREATETEMPORARY
                (
                    x_message,
                    TRUE
                );
            END IF;


            pcd_append_text
            (
                x_message,
                'Unexpected Category processing error: ' ||
                SQLERRM
            );


            IF l_commit_flag = 'Y' THEN
                ROLLBACK;
            END IF;

            RAISE;

    END pcd_assign_categories;


    -- =================================================================
    -- JCALZADILLA - 25.08.2026
    -- Main Item Request processing procedure.
    -- =================================================================

    PROCEDURE pcd_process_request
    (
        p_item_request_id      IN  NUMBER,
        p_validate_only_flag   IN  VARCHAR2 DEFAULT 'N',
        p_user_id              IN  NUMBER   DEFAULT NULL,
        p_resp_id              IN  NUMBER   DEFAULT NULL,
        p_resp_appl_id         IN  NUMBER   DEFAULT NULL,
        p_commit_flag          IN  VARCHAR2 DEFAULT 'Y',
        x_return_status        OUT VARCHAR2,
        x_message              OUT CLOB
    )
    IS

        l_request
            ops.adre_inv_item_request%ROWTYPE;

        l_master_request_org_id
            NUMBER;

        l_master_org_id
            NUMBER;

        l_master_org_code
            VARCHAR2(30);

        l_master_template_id
            NUMBER;

        l_master_template_name
            VARCHAR2(240);

        l_master_item_id
            NUMBER;

        l_master_status_code
            VARCHAR2(30);

        l_master_exists
            BOOLEAN;

        l_master_return_status
            VARCHAR2(1);

        l_master_msg_count
            NUMBER := 0;

        l_master_message
            CLOB;

        l_target_exists
            BOOLEAN;

        l_target_item_id
            NUMBER;

        l_target_status_code
            VARCHAR2(30);

        l_target_return_status
            VARCHAR2(1);

        l_target_msg_count
            NUMBER := 0;

        l_target_message
            CLOB;

        l_target_template_name
            VARCHAR2(240);

        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - START CHANGE
        -- Purpose:
        -- Hold TARGET Template Rule resolution results produced by the
        -- main package before any Oracle EBS Item transaction is executed.
        -- =================================================================

        l_resolved_target_rule_id
            NUMBER;

        l_resolved_target_template_id
            NUMBER;

        l_resolved_target_template_name
            VARCHAR2(240);

        l_resolved_target_rule_priority
            NUMBER;

        l_mrp_mapping_count
            NUMBER;

        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - END CHANGE
        -- =================================================================

        l_target_template_item_id
            NUMBER;

        l_target_template_api_org_id
            NUMBER;

        -- =================================================================
        -- JCALZADILLA - 26.08.2026 - START CHANGE
        -- Purpose:
        -- Support TARGET Item Template processing through PROCESS_ITEM
        -- overload 2 while preserving MASTER-controlled attributes and
        -- capturing the complete Oracle EBS Item API error information.
        -- =================================================================

        l_target_template_return_status
            VARCHAR2(1);

        l_target_template_msg_count
            NUMBER := 0;

        l_target_template_msg_data
            VARCHAR2(4000);

        l_target_template_message
            CLOB;

        l_target_combined_message
            CLOB;

        l_master_mrp_planning_code
            NUMBER;

        l_error_handler_message_list
            apps.error_handler.error_tbl_type;

        -- =================================================================
        -- JCALZADILLA - 26.08.2026 - END CHANGE
        -- =================================================================

        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - START CHANGE
        -- Purpose:
        -- Support the application Attribute mappings proven by Test V4.2
        -- and use the actual Oracle EBS Item segments for UPDATE calls.
        -- =================================================================

        l_ebs_item_number
            VARCHAR2(4000);

        l_item_segment1
            VARCHAR2(40);

        l_item_segment2
            VARCHAR2(40);

        l_item_segment3
            VARCHAR2(40);

        l_planning_method
            VARCHAR2(4000);

        -- =================================================================
        -- JCALZADILLA - 31.08.2026 - START CHANGE
        -- Purpose:
        -- Hold the confirmed RAW_MATERIAL_ITEM Attribute values that are
        -- now supported by the Oracle EBS Item API mappings.
        -- =================================================================

        l_engineering_item_flag
            VARCHAR2(4000);

        l_hims
            VARCHAR2(4000);

        l_price_per_uom
            NUMBER;

        l_lead_time_days
            NUMBER;

        -- =================================================================
        -- JCALZADILLA - 31.08.2026 - END CHANGE
        -- =================================================================

        l_requested_mrp_planning_code
            NUMBER;

        l_master_attr_item_id
            NUMBER;

        l_master_attr_api_org_id
            NUMBER;

        l_master_attr_return_status
            VARCHAR2(1);

        l_master_attr_msg_count
            NUMBER := 0;

        l_master_attr_msg_data
            VARCHAR2(4000);

        l_master_attr_message
            CLOB;

        l_outside_processing
            VARCHAR2(4000);

        l_width
            NUMBER;

        l_width_uom
            VARCHAR2(30);

        l_target_length
            NUMBER;

        l_target_length_uom
            VARCHAR2(30);

        l_target_dimension_uom_code
            VARCHAR2(30);

        l_target_unit_width
            NUMBER;

        l_target_unit_length
            NUMBER;

        l_target_attr_value_count
            NUMBER := 0;

        l_target_attr_item_id
            NUMBER;

        l_target_attr_api_org_id
            NUMBER;

        l_target_attr_return_status
            VARCHAR2(1);

        l_target_attr_msg_count
            NUMBER := 0;

        l_target_attr_msg_data
            VARCHAR2(4000);

        l_target_attr_message
            CLOB;

        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - END CHANGE
        -- =================================================================

        l_category_return_status
            VARCHAR2(1);

        l_category_message
            CLOB;

        l_context_user_id
            NUMBER;

        l_context_resp_id
            NUMBER;

        l_context_resp_appl_id
            NUMBER;

        l_commit_flag
            VARCHAR2(1);

        l_validate_only_flag
            VARCHAR2(1);

        l_execution_id
            VARCHAR2(100);

        l_error_text
            VARCHAR2(4000);

        l_actual_item_status_code
            VARCHAR2(30);

        l_required_attribute_count
            NUMBER;

        l_bom_enabled_flag
            VARCHAR2(1);

        l_engineering_status
            VARCHAR2(4000);

        l_eng_item_flag
            VARCHAR2(1);

        l_master_api_org_id
            NUMBER;

        l_api_failure_status
            VARCHAR2(1);

        l_api_failure_msg_count
            NUMBER;

        l_api_failure_message
            CLOB;

        l_api_failure_request_org_id
            NUMBER;

        l_api_failure_api_name
            VARCHAR2(240);

        l_api_failure_process_name
            VARCHAR2(100);

        l_api_failure_entity_id
            NUMBER;

        e_api_failure
            EXCEPTION;


        CURSOR c_targets
        IS
            SELECT
                request_org_id,
                ebs_organization_id,
                ebs_template_id,
                ebs_inventory_item_id,
                assignment_status
            FROM ops.adre_inv_item_request_org
            WHERE item_request_id = p_item_request_id
              AND organization_role = 'TARGET'
            ORDER BY ebs_organization_id;

    BEGIN

        x_return_status := NULL;
        x_message       := NULL;

        DBMS_LOB.CREATETEMPORARY
        (
            x_message,
            TRUE
        );


        l_commit_flag :=
            CASE
                WHEN UPPER(TRIM(NVL(p_commit_flag, 'Y'))) = 'Y'
                    THEN 'Y'
                ELSE 'N'
            END;


        l_validate_only_flag :=
            CASE
                WHEN UPPER(TRIM(NVL(p_validate_only_flag, 'N'))) = 'Y'
                    THEN 'Y'
                ELSE 'N'
            END;


        l_execution_id :=
            'ADRE-' ||
            TO_CHAR
            (
                SYSTIMESTAMP,
                'YYYYMMDDHH24MISSFF3'
            ) ||
            '-' ||
            TO_CHAR(p_item_request_id);


        SELECT
            *
        INTO
            l_request
        FROM ops.adre_inv_item_request
        WHERE item_request_id = p_item_request_id
        FOR UPDATE;


        IF l_request.request_status = c_request_processed THEN

            x_return_status := c_return_success;

            pcd_append_text
            (
                x_message,
                'Item Request is already PROCESSED. No new EBS transaction was executed.'
            );

            RETURN;

        END IF;


        IF l_request.request_status NOT IN
           (
               c_request_ready,
               c_request_error
           )
        THEN

            RAISE_APPLICATION_ERROR
            (
                -20104,
                'Item Request must be READY or ERROR before EBS processing. ' ||
                'Current status=' || l_request.request_status
            );

        END IF;


        IF l_request.item_number IS NULL THEN
            RAISE_APPLICATION_ERROR
            (
                -20105,
                'ITEM_NUMBER is required.'
            );
        END IF;


        IF l_request.item_description IS NULL THEN
            RAISE_APPLICATION_ERROR
            (
                -20106,
                'ITEM_DESCRIPTION is required.'
            );
        END IF;


        IF l_request.primary_uom_code IS NULL THEN
            RAISE_APPLICATION_ERROR
            (
                -20107,
                'PRIMARY_UOM_CODE is required.'
            );
        END IF;


        IF l_request.item_status_code IS NULL THEN
            RAISE_APPLICATION_ERROR
            (
                -20108,
                'ITEM_STATUS_CODE is required.'
            );
        END IF;


        SELECT
            request_org_id,
            ebs_organization_id,
            ebs_template_id
        INTO
            l_master_request_org_id,
            l_master_org_id,
            l_master_template_id
        FROM ops.adre_inv_item_request_org
        WHERE item_request_id = p_item_request_id
          AND organization_role = 'MASTER';


        IF l_master_template_id IS NULL THEN
            RAISE_APPLICATION_ERROR
            (
                -20109,
                'The MASTER Request Organization does not contain EBS_TEMPLATE_ID.'
            );
        END IF;


        SELECT
            template_name
        INTO
            l_master_template_name
        FROM apps.mtl_item_templates
        WHERE template_id = l_master_template_id;


        l_master_org_code :=
            f_get_org_code
            (
                l_master_org_id
            );


        SELECT
            inventory_item_status_code
        INTO
            l_actual_item_status_code
        FROM apps.mtl_item_status
        WHERE UPPER(inventory_item_status_code) =
              UPPER(l_request.item_status_code)
          AND ROWNUM = 1;


        -- =============================================================
        -- JCALZADILLA - 25.08.2026
        -- MASTER and TARGET template identifiers are intentionally
        -- allowed to differ.
        --
        -- MASTER EBS_TEMPLATE_ID is the template passed to
        -- EGO_ITEM_PUB.PROCESS_ITEM during Master Item creation.
        --
        -- TARGET EBS_TEMPLATE_ID is applied after organization
        -- assignment through EGO_ITEM_PUB.PROCESS_ITEM in UPDATE mode.
        -- EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG itself does not accept a
        -- target template parameter.
        -- =============================================================


        pcd_validate_required_attributes
        (
            p_item_request_id
        );


        -- =============================================================
        -- JCALZADILLA - 25.08.2026
        -- Derive the proven EGO_ITEM_PUB flags from the final model.
        --
        -- BOM_ENABLED_FLAG:
        --   Y when at least one BOM exists for this Item Request.
        --   CHR(0) when no explicit BOM decision exists in the model.
        --
        -- ENG_ITEM_FLAG:
        --   Y when ENGINEERING_STATUS has a value for the request.
        --   CHR(0) otherwise.
        -- =============================================================

        SELECT
            CASE
                WHEN COUNT(*) > 0 THEN 'Y'
                ELSE c_missing_char
            END
        INTO
            l_bom_enabled_flag
        FROM ops.adre_inv_item_bom bom
        JOIN ops.adre_inv_item_request_org ro
          ON ro.request_org_id = bom.request_org_id
        WHERE ro.item_request_id = p_item_request_id;


        -- =================================================================
        -- JCALZADILLA - 31.08.2026 - START CHANGE
        -- Purpose:
        -- Prefer the explicit ENGINEERING_ITEM_FLAG application Attribute
        -- for EBS ENG_ITEM_FLAG. Preserve ENGINEERING_STATUS as the
        -- backward-compatible fallback used by the previously validated
        -- Adhesive Coating flow.
        -- =================================================================

        BEGIN

            SELECT
                av.attribute_char_value
            INTO
                l_engineering_item_flag
            FROM ops.adre_inv_item_attr_value av
            JOIN ops.adre_inv_item_attribute a
              ON a.item_attribute_id = av.item_attribute_id
            WHERE av.request_org_id = l_master_request_org_id
              AND a.attribute_code = 'ENGINEERING_ITEM_FLAG'
              AND av.attribute_char_value IS NOT NULL
              AND ROWNUM = 1;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_engineering_item_flag := NULL;
        END;


        IF l_engineering_item_flag IS NOT NULL THEN

            l_engineering_item_flag :=
                UPPER(TRIM(l_engineering_item_flag));


            IF l_engineering_item_flag NOT IN ('Y', 'N') THEN

                RAISE_APPLICATION_ERROR
                (
                    -20134,
                    'ENGINEERING_ITEM_FLAG must be Y or N. VALUE=' ||
                    l_engineering_item_flag
                );

            END IF;


            l_eng_item_flag := l_engineering_item_flag;

        ELSE

            BEGIN

                SELECT
                    av.attribute_char_value
                INTO
                    l_engineering_status
                FROM ops.adre_inv_item_attr_value av
                JOIN ops.adre_inv_item_request_org ro
                  ON ro.request_org_id = av.request_org_id
                JOIN ops.adre_inv_item_attribute a
                  ON a.item_attribute_id = av.item_attribute_id
                WHERE ro.item_request_id = p_item_request_id
                  AND a.attribute_code = 'ENGINEERING_STATUS'
                  AND av.attribute_char_value IS NOT NULL
                  AND ROWNUM = 1;

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    l_engineering_status := NULL;
            END;


            l_eng_item_flag :=
                CASE
                    WHEN l_engineering_status IS NOT NULL THEN 'Y'
                    ELSE c_missing_char
                END;

        END IF;

        -- =================================================================
        -- JCALZADILLA - 31.08.2026 - END CHANGE
        -- =================================================================


        SELECT
            COUNT(*)
        INTO
            l_required_attribute_count
        FROM ops.adre_inv_item_attr_value av
        JOIN ops.adre_inv_item_request_org ro
          ON ro.request_org_id = av.request_org_id
        JOIN ops.adre_inv_item_attribute a
          ON a.item_attribute_id = av.item_attribute_id
        WHERE ro.item_request_id = p_item_request_id
          AND a.attribute_code NOT IN
              (
                  'PLANNING_METHOD',
                  'OUTSIDE_PROCESSING',
                  'WIDTH',
                  'TARGET_LENGTH',
                  'ENGINEERING_ITEM_FLAG',
                  'HIMS',
                  'EXPENSE_ITEM_FLAG',
                  'PRICE_PER_UOM',
                  'LEAD_TIME_DAYS'
              )
          AND
          (
                 a.ebs_attribute_group IS NULL
              OR a.ebs_attribute_name  IS NULL
          );


        pcd_append_text
        (
            x_message,
            'Item Request processing started.'
        );

        pcd_append_text
        (
            x_message,
            'Item Number: ' || l_request.item_number
        );

        pcd_append_text
        (
            x_message,
            'Master Organization: ' ||
            l_master_org_code ||
            ' / ' ||
            l_master_org_id
        );

        pcd_append_text
        (
            x_message,
            'Master EBS Template: ' ||
            l_master_template_name ||
            ' / ' ||
            l_master_template_id
        );

        pcd_append_text
        (
            x_message,
            'BOM Enabled Flag sent to PROCESS_ITEM: ' ||
            CASE
                WHEN l_bom_enabled_flag = c_missing_char THEN 'NOT EXPLICITLY SENT'
                ELSE l_bom_enabled_flag
            END
        );

        pcd_append_text
        (
            x_message,
            'Engineering Item Flag sent to PROCESS_ITEM: ' ||
            CASE
                WHEN l_eng_item_flag = c_missing_char THEN 'NOT EXPLICITLY SENT'
                ELSE l_eng_item_flag
            END
        );


        IF l_required_attribute_count > 0 THEN
            pcd_append_text
            (
                x_message,
                'Application attributes without package-supported EBS mapping: ' ||
                l_required_attribute_count ||
                '. They are validated locally but are not sent by this package version.'
            );
        END IF;


        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - START CHANGE
        -- Purpose:
        -- Resolve and persist every TARGET Template from
        -- ADRE_INV_ITEM_TEMPLATE_RULE before any Oracle EBS Item API call.
        --
        -- The Request may contain a NULL or previously populated TARGET
        -- EBS_TEMPLATE_ID. The rule engine is authoritative and overwrites
        -- the TARGET Request Organization with the resolved configuration.
        -- =================================================================

        FOR r_rule_target IN
        (
            SELECT
                request_org_id,
                ebs_organization_id
            FROM ops.adre_inv_item_request_org
            WHERE item_request_id = p_item_request_id
              AND organization_role = 'TARGET'
            ORDER BY ebs_organization_id
        )
        LOOP

            l_resolved_target_rule_id       := NULL;
            l_resolved_target_template_id   := NULL;
            l_resolved_target_template_name := NULL;
            l_resolved_target_rule_priority := NULL;


            pcd_resolve_target_template_rule
            (
                p_item_request_id        => p_item_request_id,
                p_item_type_id           => l_request.item_type_id,
                p_target_organization_id => r_rule_target.ebs_organization_id,

                x_item_template_rule_id  =>
                    l_resolved_target_rule_id,

                x_ebs_template_id        =>
                    l_resolved_target_template_id,

                x_template_name          =>
                    l_resolved_target_template_name,

                x_rule_priority          =>
                    l_resolved_target_rule_priority
            );


            UPDATE ops.adre_inv_item_request_org
            SET ebs_template_id  = l_resolved_target_template_id,
                last_updated_by  =
                    NVL
                    (
                        SYS_CONTEXT
                        (
                            'APEX$SESSION',
                            'APP_USER'
                        ),
                        USER
                    ),
                last_update_date = SYSDATE
            WHERE request_org_id = r_rule_target.request_org_id;


            pcd_append_text
            (
                x_message,
                'TARGET Template Rule resolved for Organization ' ||
                r_rule_target.ebs_organization_id ||
                ': RULE_ID=' ||
                l_resolved_target_rule_id ||
                ', TEMPLATE=' ||
                l_resolved_target_template_name ||
                ' / ' ||
                l_resolved_target_template_id ||
                ', PRIORITY=' ||
                NVL
                (
                    TO_CHAR(l_resolved_target_rule_priority),
                    'NULL'
                )
            );


            pcd_insert_api_log
            (
                p_execution_id      => l_execution_id,
                p_item_request_id   => p_item_request_id,
                p_request_org_id    => r_rule_target.request_org_id,
                p_process_name      => 'RESOLVE_TARGET_TEMPLATE',
                p_api_name          => NULL,
                p_entity_type       => 'TEMPLATE_RULE',
                p_entity_id         => l_resolved_target_rule_id,
                p_log_level         => 'INFO',
                p_process_status    => 'SUCCESS',
                p_api_return_status => c_return_success,
                p_api_message_count => 0,
                p_message_text      =>
                    TO_CLOB
                    (
                        'TARGET Template resolved from application configuration. ' ||
                        'TEMPLATE=' ||
                        l_resolved_target_template_name ||
                        ' / ' ||
                        l_resolved_target_template_id
                    )
            );

        END LOOP;

        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - END CHANGE
        -- =================================================================


        set_env;

        l_context_user_id :=
            NVL
            (
                p_user_id,
                g_user_id
            );

        l_context_resp_id :=
            NVL
            (
                p_resp_id,
                g_resp_id
            );

        l_context_resp_appl_id :=
            NVL
            (
                p_resp_appl_id,
                g_application_id
            );


        pcd_initialize_ebs_context
        (
            p_user_id      => l_context_user_id,
            p_resp_id      => l_context_resp_id,
            p_resp_appl_id => l_context_resp_appl_id
        );


        UPDATE ops.adre_inv_item_request
        SET request_status = c_request_processing
        WHERE item_request_id = p_item_request_id;


        UPDATE ops.adre_inv_item_request_org
        SET assignment_status = c_assignment_processing
        WHERE item_request_id = p_item_request_id
          AND assignment_status IN
              (
                  c_assignment_ready,
                  c_assignment_error
              );


        -- =============================================================
        -- JCALZADILLA - 25.08.2026
        -- CALL #1 - Create or verify the Master Item.
        -- The existing EBS Item Template is applied here.
        -- =============================================================

        l_master_exists :=
            f_item_exists
            (
                p_item_number       => l_request.item_number,
                p_organization_id   => l_master_org_id,
                x_inventory_item_id => l_master_item_id,
                x_item_status_code  => l_master_status_code
            );


        IF l_master_exists THEN

            l_master_return_status := c_return_success;
            l_master_msg_count     := 0;

            l_master_message :=
                TO_CLOB
                (
                    'Master Item already exists in Oracle EBS. Creation was skipped.'
                );

        ELSE

            BEGIN
                apps.fnd_msg_pub.initialize;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;


            l_master_api_org_id := NULL;

            apps.ego_item_pub.process_item
            (
                p_api_version                => 1.0,
                p_init_msg_list              => c_api_true,
                p_commit                     => c_api_false,
                p_transaction_type           => 'CREATE',
                p_template_name              => l_master_template_name,
                p_item_number                => l_request.item_number,
                p_segment1                   => l_request.item_number,
                p_organization_code          => l_master_org_code,
                p_description                => l_request.item_description,
                p_long_description           =>
                    f_optional_char
                    (
                        DBMS_LOB.SUBSTR
                        (
                            l_request.long_description,
                            4000,
                            1
                        )
                    ),
                p_primary_uom_code           => l_request.primary_uom_code,
                p_inventory_item_status_code =>
                    f_optional_char
                    (
                        l_actual_item_status_code
                    ),
                p_bom_enabled_flag           => l_bom_enabled_flag,
                p_eng_item_flag              => l_eng_item_flag,
                x_inventory_item_id          => l_master_item_id,
                x_organization_id            => l_master_api_org_id,
                x_return_status              => l_master_return_status,
                x_msg_count                  => l_master_msg_count
            );


            l_master_message :=
                f_get_api_messages
                (
                    l_master_msg_count
                );

            pcd_write_log
            (
                'CREATE_MASTER_ITEM',
                'PROCESS_ITEM completed. RETURN_STATUS=' ||
                NVL(l_master_return_status, 'NULL') ||
                ', MSG_COUNT=' ||
                NVL(TO_CHAR(l_master_msg_count), '0') ||
                ', INVENTORY_ITEM_ID=' ||
                NVL(TO_CHAR(l_master_item_id), 'NULL') ||
                ', API_ORGANIZATION_ID=' ||
                NVL(TO_CHAR(l_master_api_org_id), 'NULL') ||
                ', MESSAGE=' ||
                DBMS_LOB.SUBSTR(l_master_message, 1800, 1)
            );

        END IF;


        IF l_master_return_status <> c_return_success THEN

            l_api_failure_status         := NVL(l_master_return_status, c_return_error);
            l_api_failure_msg_count      := NVL(l_master_msg_count, 0);
            l_api_failure_request_org_id := l_master_request_org_id;
            l_api_failure_api_name       := 'EGO_ITEM_PUB.PROCESS_ITEM';
            l_api_failure_process_name   := 'CREATE_MASTER_ITEM';
            l_api_failure_entity_id      := l_master_org_id;

            DBMS_LOB.CREATETEMPORARY
            (
                l_api_failure_message,
                TRUE
            );

            pcd_append_text
            (
                l_api_failure_message,
                'EGO_ITEM_PUB.PROCESS_ITEM failed for the MASTER organization.'
            );

            pcd_append_text
            (
                l_api_failure_message,
                'MASTER_ORGANIZATION_ID=' || l_master_org_id ||
                ', MASTER_TEMPLATE_ID=' || l_master_template_id ||
                ', MASTER_TEMPLATE_NAME=' || l_master_template_name ||
                ', RETURN_STATUS=' || NVL(l_master_return_status, 'NULL') ||
                ', MSG_COUNT=' || NVL(TO_CHAR(l_master_msg_count), '0')
            );

            pcd_append_text
            (
                l_api_failure_message,
                DBMS_LOB.SUBSTR
                (
                    l_master_message,
                    3000,
                    1
                )
            );

            RAISE e_api_failure;

        END IF;


        UPDATE ops.adre_inv_item_request_org
        SET ebs_inventory_item_id = l_master_item_id,
            assignment_status     = c_assignment_processed,
            api_return_status     = l_master_return_status,
            api_message_count     = NVL(l_master_msg_count, 0),
            api_message_text      = l_master_message,
            api_processed_date    = SYSDATE
        WHERE request_org_id = l_master_request_org_id;


        pcd_insert_api_log
        (
            p_execution_id      => l_execution_id,
            p_item_request_id   => p_item_request_id,
            p_request_org_id    => l_master_request_org_id,
            p_process_name      => 'CREATE_MASTER_ITEM',
            p_api_name          => 'EGO_ITEM_PUB.PROCESS_ITEM',
            p_entity_type       => 'ORGANIZATION',
            p_entity_id         => l_master_org_id,
            p_log_level         => 'INFO',
            p_process_status    => 'SUCCESS',
            p_api_return_status => l_master_return_status,
            p_api_message_count => l_master_msg_count,
            p_message_text      => l_master_message
        );


        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - START CHANGE
        -- Purpose:
        -- Resolve the actual Oracle EBS Item segments and apply confirmed
        -- MASTER application Attributes before TARGET assignment/template
        -- processing.
        --
        -- PLANNING_METHOD
        --     -> MRP_PLANNING_CODE resolved from selected TARGET
        --        Template metadata.
        --
        -- MRP_PLANNING_CODE is MASTER controlled in this EBS instance.
        -- =================================================================

        SELECT
            kfv.concatenated_segments,
            msi.segment1,
            msi.segment2,
            msi.segment3
        INTO
            l_ebs_item_number,
            l_item_segment1,
            l_item_segment2,
            l_item_segment3
        FROM apps.mtl_system_items_b msi
        JOIN apps.mtl_system_items_kfv kfv
          ON kfv.inventory_item_id = msi.inventory_item_id
         AND kfv.organization_id   = msi.organization_id
        WHERE msi.inventory_item_id = l_master_item_id
          AND msi.organization_id   = l_master_org_id;


        BEGIN

            SELECT
                av.attribute_char_value
            INTO
                l_planning_method
            FROM ops.adre_inv_item_attr_value av
            JOIN ops.adre_inv_item_attribute a
              ON a.item_attribute_id = av.item_attribute_id
            WHERE av.request_org_id = l_master_request_org_id
              AND a.attribute_code   = 'PLANNING_METHOD'
              AND av.attribute_char_value IS NOT NULL
              AND ROWNUM = 1;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_planning_method := NULL;
        END;


        -- =================================================================
        -- JCALZADILLA - 31.08.2026 - START CHANGE
        -- Purpose:
        -- HIMS is a MASTER RAW_MATERIAL_ITEM Attribute. Oracle EBS
        -- metadata confirms that it is stored in MTL_SYSTEM_ITEMS.ATTRIBUTE14.
        -- =================================================================

        BEGIN

            SELECT
                av.attribute_char_value
            INTO
                l_hims
            FROM ops.adre_inv_item_attr_value av
            JOIN ops.adre_inv_item_attribute a
              ON a.item_attribute_id = av.item_attribute_id
            WHERE av.request_org_id = l_master_request_org_id
              AND a.attribute_code = 'HIMS'
              AND av.attribute_char_value IS NOT NULL
              AND ROWNUM = 1;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_hims := NULL;
        END;


        l_requested_mrp_planning_code := apps.fnd_api.g_miss_num;


        IF    l_planning_method         IS NOT NULL
           OR l_hims                    IS NOT NULL
           OR l_engineering_item_flag   IS NOT NULL
        THEN

        -- =================================================================
        -- JCALZADILLA - 31.08.2026 - END CHANGE
        -- =================================================================

            -- =========================================================
            -- JCALZADILLA - 27.08.2026 - START CHANGE
            -- Purpose:
            -- Resolve the Oracle EBS MRP_PLANNING_CODE dynamically from
            -- the TARGET Template metadata selected by the Template Rule.
            --
            -- No Oracle EBS planning code is hard-coded here.
            -- =========================================================

            IF l_planning_method IS NOT NULL THEN

                SELECT
                    COUNT
                    (
                        DISTINCT TO_NUMBER(ta.attribute_value)
                    ),
                    MIN
                    (
                        TO_NUMBER(ta.attribute_value)
                    )
                INTO
                    l_mrp_mapping_count,
                    l_requested_mrp_planning_code
                FROM ops.adre_inv_item_request_org ro
                JOIN apps.mtl_item_templ_attributes ta
                  ON ta.template_id = ro.ebs_template_id
                WHERE ro.item_request_id = p_item_request_id
                  AND ro.organization_role = 'TARGET'
                  AND ro.ebs_template_id IS NOT NULL
                  AND UPPER(TRIM(ta.attribute_name)) =
                      'MTL_SYSTEM_ITEMS.MRP_PLANNING_CODE'
                  AND ta.enabled_flag = 'Y'
                  AND UPPER(TRIM(ta.report_user_value)) =
                      UPPER(TRIM(l_planning_method));


                IF l_mrp_mapping_count = 0
                   OR l_requested_mrp_planning_code IS NULL
                THEN

                    RAISE_APPLICATION_ERROR
                    (
                        -20131,
                        'PLANNING_METHOD could not be resolved from the selected TARGET Template metadata. ' ||
                        'VALUE=' ||
                        l_planning_method
                    );

                ELSIF l_mrp_mapping_count > 1 THEN

                    RAISE_APPLICATION_ERROR
                    (
                        -20133,
                        'PLANNING_METHOD resolves to more than one Oracle EBS MRP_PLANNING_CODE. ' ||
                        'VALUE=' ||
                        l_planning_method
                    );

                END IF;

            END IF;

            -- =========================================================
            -- JCALZADILLA - 27.08.2026 - END CHANGE
            -- =========================================================


            BEGIN
                apps.fnd_msg_pub.initialize;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;


            l_master_attr_item_id       := NULL;
            l_master_attr_api_org_id    := NULL;
            l_master_attr_return_status := NULL;
            l_master_attr_msg_count     := 0;
            l_master_attr_msg_data      := NULL;
            l_master_attr_message       := NULL;
            l_error_handler_message_list.DELETE;


            apps.ego_item_pub.process_item
            (
                p_api_version         => 1.0,
                p_init_msg_list       => c_api_true,
                p_commit              => c_api_false,
                p_transaction_type    => 'UPDATE',

                p_inventory_item_id   => l_master_item_id,
                p_organization_id     => l_master_org_id,

                p_mrp_planning_code   => l_requested_mrp_planning_code,

                -- =========================================================
                -- JCALZADILLA - 31.08.2026 - START CHANGE
                -- RAW_MATERIAL_ITEM supported MASTER Attributes.
                -- =========================================================
                p_eng_item_flag       => l_eng_item_flag,
                p_attribute14         => f_optional_char(l_hims),
                -- JCALZADILLA - 31.08.2026 - END CHANGE

                p_item_number         => l_ebs_item_number,
                p_segment1            => l_item_segment1,
                p_segment2            => l_item_segment2,
                p_segment3            => l_item_segment3,

                x_inventory_item_id   => l_master_attr_item_id,
                x_organization_id     => l_master_attr_api_org_id,
                x_return_status       => l_master_attr_return_status,
                x_msg_count           => l_master_attr_msg_count,
                x_msg_data            => l_master_attr_msg_data
            );


            l_master_attr_message :=
                f_get_api_messages
                (
                    l_master_attr_msg_count,
                    l_master_attr_msg_data
                );


            IF l_master_attr_return_status <> c_return_success THEN

                BEGIN

                    l_error_handler_message_list.DELETE;

                    apps.error_handler.get_message_list
                    (
                        x_message_list => l_error_handler_message_list
                    );


                    IF l_error_handler_message_list.COUNT > 0 THEN

                        FOR i IN 1 .. l_error_handler_message_list.COUNT
                        LOOP

                            pcd_append_text
                            (
                                l_master_attr_message,
                                'ERROR_HANDLER message ' ||
                                i ||
                                ': ' ||
                                l_error_handler_message_list(i).message_text
                            );

                        END LOOP;

                    END IF;

                EXCEPTION
                    WHEN OTHERS THEN

                        pcd_append_text
                        (
                            l_master_attr_message,
                            'Could not retrieve ERROR_HANDLER messages: ' ||
                            SQLERRM
                        );
                END;


                l_api_failure_status         :=
                    NVL(l_master_attr_return_status, c_return_error);

                l_api_failure_msg_count      :=
                    NVL(l_master_attr_msg_count, 0);

                l_api_failure_request_org_id :=
                    l_master_request_org_id;

                l_api_failure_api_name       :=
                    'EGO_ITEM_PUB.PROCESS_ITEM';

                l_api_failure_process_name   :=
                    'APPLY_MASTER_ATTRIBUTES';

                l_api_failure_entity_id      :=
                    l_master_org_id;


                DBMS_LOB.CREATETEMPORARY
                (
                    l_api_failure_message,
                    TRUE
                );


                pcd_append_text
                (
                    l_api_failure_message,
                    'Failed to apply confirmed MASTER application Attributes.'
                );

                pcd_append_text
                (
                    l_api_failure_message,
                    'PLANNING_METHOD=' ||
                    NVL(l_planning_method, 'NOT SENT') ||
                    ', MRP_PLANNING_CODE=' ||
                    CASE
                        WHEN l_planning_method IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_requested_mrp_planning_code)
                    END ||
                    ', ENGINEERING_ITEM_FLAG=' ||
                    NVL(l_engineering_item_flag, 'NOT EXPLICITLY PROVIDED') ||
                    ', HIMS=' ||
                    NVL(l_hims, 'NOT SENT')
                );

                pcd_append_text
                (
                    l_api_failure_message,
                    DBMS_LOB.SUBSTR
                    (
                        l_master_attr_message,
                        3000,
                        1
                    )
                );


                RAISE e_api_failure;

            END IF;


            UPDATE ops.adre_inv_item_attr_value av
            SET api_return_status  = l_master_attr_return_status,
                api_message_count  = NVL(l_master_attr_msg_count, 0),
                api_message_text   = l_master_attr_message,
                api_processed_date = SYSDATE
            WHERE av.request_org_id = l_master_request_org_id
              AND EXISTS
                  (
                      SELECT 1
                      FROM ops.adre_inv_item_attribute a
                      WHERE a.item_attribute_id = av.item_attribute_id
                        AND a.attribute_code IN
                            (
                                'PLANNING_METHOD',
                                'ENGINEERING_ITEM_FLAG',
                                'HIMS'
                            )
                  );


            pcd_insert_api_log
            (
                p_execution_id      => l_execution_id,
                p_item_request_id   => p_item_request_id,
                p_request_org_id    => l_master_request_org_id,
                p_process_name      => 'APPLY_MASTER_ATTRIBUTES',
                p_api_name          => 'EGO_ITEM_PUB.PROCESS_ITEM',
                p_entity_type       => 'ORGANIZATION',
                p_entity_id         => l_master_org_id,
                p_log_level         => 'INFO',
                p_process_status    => 'SUCCESS',
                p_api_return_status => l_master_attr_return_status,
                p_api_message_count => l_master_attr_msg_count,
                p_message_text      => l_master_attr_message
            );


            pcd_append_text
            (
                x_message,
                'MASTER application Attributes applied: PLANNING_METHOD=' ||
                NVL(l_planning_method, 'NOT SENT') ||
                CASE
                    WHEN l_planning_method IS NULL THEN ''
                    ELSE
                        ' -> MRP_PLANNING_CODE=' ||
                        TO_CHAR(l_requested_mrp_planning_code)
                END ||
                ', ENGINEERING_ITEM_FLAG=' ||
                CASE
                    WHEN l_eng_item_flag = c_missing_char THEN 'NOT SENT'
                    ELSE l_eng_item_flag
                END ||
                ', HIMS=' ||
                NVL(l_hims, 'NOT SENT')
            );

        END IF;

        -- =================================================================
        -- JCALZADILLA - 27.08.2026 - END CHANGE
        -- =================================================================


        -- =================================================================
        -- JCALZADILLA - 26.08.2026 - START CHANGE
        -- Purpose:
        -- Read the current MASTER-controlled MRP_PLANNING_CODE from the
        -- Oracle EBS Master Item. This value must be preserved when a
        -- TARGET Item Template is applied to an Organization Item.
        --
        -- Oracle EBS rejected MEDICAL COATING / Template 742 when its
        -- MRP_PLANNING_CODE conflicted with the value controlled by the
        -- Master Item.
        -- =================================================================

        SELECT
            msi.mrp_planning_code
        INTO
            l_master_mrp_planning_code
        FROM apps.mtl_system_items_b msi
        WHERE msi.inventory_item_id = l_master_item_id
          AND msi.organization_id   = l_master_org_id;


        pcd_write_log
        (
            'READ_MASTER_CONTROLLED_ATTRIBUTES',
            'Master-controlled attributes resolved. ' ||
            'INVENTORY_ITEM_ID=' ||
            NVL(TO_CHAR(l_master_item_id), 'NULL') ||
            ', ORGANIZATION_ID=' ||
            NVL(TO_CHAR(l_master_org_id), 'NULL') ||
            ', MRP_PLANNING_CODE=' ||
            NVL(TO_CHAR(l_master_mrp_planning_code), 'NULL')
        );


        pcd_append_text
        (
            x_message,
            'Master-controlled MRP Planning Code preserved for TARGET Template processing: ' ||
            NVL(TO_CHAR(l_master_mrp_planning_code), 'NULL')
        );

        -- =================================================================
        -- JCALZADILLA - 26.08.2026 - END CHANGE
        -- =================================================================


        -- =============================================================
        -- JCALZADILLA - 25.08.2026
        -- CALL #2 - Assign the Item to every TARGET organization.
        --
        -- CALL #3 - Apply each TARGET EBS Template through
        -- EGO_ITEM_PUB.PROCESS_ITEM in UPDATE mode.
        --
        -- This two-step sequence is required because
        -- EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG does not accept an Item
        -- Template parameter.
        -- =============================================================

        FOR r_target IN c_targets
        LOOP

            l_target_item_id                  := NULL;
            l_target_status_code              := NULL;
            l_target_return_status            := NULL;
            l_target_msg_count                := 0;
            l_target_message                  := NULL;
            l_target_template_name            := NULL;
            l_target_template_item_id         := NULL;
            l_target_template_api_org_id      := NULL;
            l_target_template_return_status   := NULL;
            l_target_template_msg_count       := 0;
            l_target_template_msg_data        := NULL;
            l_target_template_message         := NULL;
            l_target_combined_message         := NULL;
            l_target_attr_value_count          := 0;
            l_target_attr_item_id              := NULL;
            l_target_attr_api_org_id           := NULL;
            l_target_attr_return_status        := NULL;
            l_target_attr_msg_count            := 0;
            l_target_attr_msg_data             := NULL;
            l_target_attr_message              := NULL;
            l_outside_processing               := NULL;
            l_width                            := NULL;
            l_width_uom                        := NULL;
            l_target_length                    := NULL;
            l_target_length_uom                := NULL;

            -- =================================================================
            -- JCALZADILLA - 31.08.2026 - START CHANGE
            -- Reset RAW_MATERIAL_ITEM TARGET Attribute values per Organization.
            -- =================================================================
            l_price_per_uom                    := NULL;
            l_lead_time_days                   := NULL;
            -- JCALZADILLA - 31.08.2026 - END CHANGE

            l_target_dimension_uom_code        := apps.fnd_api.g_miss_char;
            l_target_unit_width                := apps.fnd_api.g_miss_num;
            l_target_unit_length               := apps.fnd_api.g_miss_num;
            l_error_handler_message_list.DELETE;


            l_target_exists :=
                f_item_exists
                (
                    p_item_number       => l_request.item_number,
                    p_organization_id   => r_target.ebs_organization_id,
                    x_inventory_item_id => l_target_item_id,
                    x_item_status_code  => l_target_status_code
                );


            IF l_target_exists THEN

                l_target_return_status := c_return_success;
                l_target_msg_count     := 0;

                l_target_message :=
                    TO_CLOB
                    (
                        'Target Item already exists in Oracle EBS. Organization assignment was skipped.'
                    );

            ELSE

                BEGIN
                    apps.fnd_msg_pub.initialize;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;


                apps.ego_item_pub.assign_item_to_org
                (
                    p_api_version       => 1.0,
                    p_init_msg_list     => c_api_true,
                    p_commit            => c_api_false,
                    p_inventory_item_id => l_master_item_id,
                    p_item_number       => l_request.item_number,
                    p_organization_id   => r_target.ebs_organization_id,
                    p_organization_code =>
                        f_get_org_code
                        (
                            r_target.ebs_organization_id
                        ),
                    p_primary_uom_code  => l_request.primary_uom_code,
                    x_return_status     => l_target_return_status,
                    x_msg_count         => l_target_msg_count
                );


                l_target_message :=
                    f_get_api_messages
                    (
                        l_target_msg_count
                    );


                IF l_target_return_status = c_return_success THEN

                    l_target_exists :=
                        f_item_exists
                        (
                            p_item_number       => l_request.item_number,
                            p_organization_id   => r_target.ebs_organization_id,
                            x_inventory_item_id => l_target_item_id,
                            x_item_status_code  => l_target_status_code
                        );

                END IF;

            END IF;


            IF l_target_return_status <> c_return_success THEN

                l_api_failure_status         := NVL(l_target_return_status, c_return_error);
                l_api_failure_msg_count      := NVL(l_target_msg_count, 0);
                l_api_failure_request_org_id := r_target.request_org_id;
                l_api_failure_api_name       := 'EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG';
                l_api_failure_process_name   := 'ASSIGN_TARGET_ORG';
                l_api_failure_entity_id      := r_target.ebs_organization_id;

                DBMS_LOB.CREATETEMPORARY
                (
                    l_api_failure_message,
                    TRUE
                );

                pcd_append_text
                (
                    l_api_failure_message,
                    'EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG failed.'
                );

                pcd_append_text
                (
                    l_api_failure_message,
                    'TARGET_ORGANIZATION_ID=' ||
                    r_target.ebs_organization_id ||
                    ', TARGET_TEMPLATE_ID=' ||
                    NVL(TO_CHAR(r_target.ebs_template_id), 'NULL') ||
                    ', RETURN_STATUS=' ||
                    NVL(l_target_return_status, 'NULL') ||
                    ', MSG_COUNT=' ||
                    NVL(TO_CHAR(l_target_msg_count), '0')
                );

                pcd_append_text
                (
                    l_api_failure_message,
                    DBMS_LOB.SUBSTR
                    (
                        l_target_message,
                        3000,
                        1
                    )
                );

                RAISE e_api_failure;

            END IF;


            pcd_insert_api_log
            (
                p_execution_id      => l_execution_id,
                p_item_request_id   => p_item_request_id,
                p_request_org_id    => r_target.request_org_id,
                p_process_name      => 'ASSIGN_TARGET_ORG',
                p_api_name          => 'EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG',
                p_entity_type       => 'ORGANIZATION',
                p_entity_id         => r_target.ebs_organization_id,
                p_log_level         => 'INFO',
                p_process_status    => 'SUCCESS',
                p_api_return_status => l_target_return_status,
                p_api_message_count => l_target_msg_count,
                p_message_text      => l_target_message
            );


            pcd_append_text
            (
                l_target_combined_message,
                'Organization assignment result:'
            );

            pcd_append_text
            (
                l_target_combined_message,
                DBMS_LOB.SUBSTR
                (
                    l_target_message,
                    3000,
                    1
                )
            );


            -- =========================================================
            -- JCALZADILLA - 25.08.2026
            -- Apply the target-specific EBS Item Template after the Item
            -- has been assigned to the TARGET organization.
            -- =========================================================

            IF r_target.ebs_template_id IS NOT NULL THEN

                SELECT
                    template_name
                INTO
                    l_target_template_name
                FROM apps.mtl_item_templates
                WHERE template_id = r_target.ebs_template_id;


                BEGIN
                    apps.fnd_msg_pub.initialize;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;


                                -- =================================================================
                -- JCALZADILLA - 26.08.2026 - START CHANGE
                -- Purpose:
                -- Apply the TARGET Item Template through PROCESS_ITEM overload 2.
                --
                -- Preserve the MASTER-controlled MRP_PLANNING_CODE so the TARGET
                -- Organization Item does not conflict with the Master Item.
                --
                -- P_ORGANIZATION_CODE is intentionally not passed because the
                -- required PROCESS_ITEM overload identifies the Organization
                -- through P_ORGANIZATION_ID.
                --
                -- X_MSG_DATA is required by this overload.
                -- =================================================================

                l_target_template_msg_data :=
                    NULL;


                apps.ego_item_pub.process_item
                (
                    p_api_version         => 1.0,
                    p_init_msg_list       => c_api_true,
                    p_commit              => c_api_false,
                    p_transaction_type    => 'UPDATE',

                    p_template_id         => r_target.ebs_template_id,
                    p_template_name       => l_target_template_name,

                    p_inventory_item_id   =>
                        NVL
                        (
                            l_target_item_id,
                            l_master_item_id
                        ),

                    p_organization_id     =>
                        r_target.ebs_organization_id,

                    p_mrp_planning_code   =>
                        l_master_mrp_planning_code,

                    p_item_number         =>
                        l_ebs_item_number,

                    p_segment1            =>
                        l_item_segment1,

                    p_segment2            =>
                        l_item_segment2,

                    p_segment3            =>
                        l_item_segment3,

                    x_inventory_item_id   =>
                        l_target_template_item_id,

                    x_organization_id     =>
                        l_target_template_api_org_id,

                    x_return_status       =>
                        l_target_template_return_status,

                    x_msg_count           =>
                        l_target_template_msg_count,

                    x_msg_data            =>
                        l_target_template_msg_data
                );

                -- =================================================================
                -- JCALZADILLA - 26.08.2026 - END CHANGE
                -- =================================================================


                              -- =================================================================
                -- JCALZADILLA - 26.08.2026 - START CHANGE
                -- Purpose:
                -- Include PROCESS_ITEM X_MSG_DATA when building the TARGET
                -- Template API message text.
                -- =================================================================

                l_target_template_message :=
                    f_get_api_messages
                    (
                        l_target_template_msg_count,
                        l_target_template_msg_data
                    );

                -- =================================================================
                -- JCALZADILLA - 26.08.2026 - END CHANGE
                -- =================================================================


                                -- =================================================================
                -- JCALZADILLA - 26.08.2026 - START CHANGE
                -- Purpose:
                -- Retrieve Oracle EBS Item API validation messages from
                -- ERROR_HANDLER when PROCESS_ITEM returns a failure.
                --
                -- EGO_ITEM_PUB may return detailed Item validation errors through
                -- ERROR_HANDLER even when FND_MSG_PUB does not contain useful text.
                -- =================================================================

                IF l_target_template_return_status <> c_return_success THEN

                    BEGIN

                        l_error_handler_message_list.DELETE;


                        apps.error_handler.get_message_list
                        (
                            x_message_list =>
                                l_error_handler_message_list
                        );


                        IF l_error_handler_message_list.COUNT > 0 THEN

                            FOR i IN 1 .. l_error_handler_message_list.COUNT
                            LOOP

                                pcd_append_text
                                (
                                    l_target_template_message,
                                    'ERROR_HANDLER message ' ||
                                    i ||
                                    ': ' ||
                                    l_error_handler_message_list(i).message_text
                                );

                            END LOOP;

                        END IF;


                    EXCEPTION
                        WHEN OTHERS THEN

                            pcd_append_text
                            (
                                l_target_template_message,
                                'Could not retrieve ERROR_HANDLER messages: ' ||
                                SQLERRM
                            );

                    END;

                END IF;

                -- =================================================================
                -- JCALZADILLA - 26.08.2026 - END CHANGE
                -- =================================================================

                IF l_target_template_return_status <> c_return_success THEN

                    l_api_failure_status         :=
                        NVL
                        (
                            l_target_template_return_status,
                            c_return_error
                        );

                    l_api_failure_msg_count      :=
                        NVL
                        (
                            l_target_template_msg_count,
                            0
                        );

                    l_api_failure_request_org_id :=
                        r_target.request_org_id;

                    l_api_failure_api_name       :=
                        'EGO_ITEM_PUB.PROCESS_ITEM';

                    l_api_failure_process_name   :=
                        'APPLY_TARGET_TEMPLATE';

                    l_api_failure_entity_id      :=
                        r_target.ebs_organization_id;


                    DBMS_LOB.CREATETEMPORARY
                    (
                        l_api_failure_message,
                        TRUE
                    );


                    pcd_append_text
                    (
                        l_api_failure_message,
                        'EGO_ITEM_PUB.PROCESS_ITEM failed while applying the TARGET Item Template.'
                    );


                    pcd_append_text
                    (
                        l_api_failure_message,
                        'TARGET_ORGANIZATION_ID=' ||
                        r_target.ebs_organization_id ||
                        ', TARGET_TEMPLATE_ID=' ||
                        r_target.ebs_template_id ||
                        ', TARGET_TEMPLATE_NAME=' ||
                        l_target_template_name ||
                        ', RETURN_STATUS=' ||
                        NVL(l_target_template_return_status, 'NULL') ||
                        ', MSG_COUNT=' ||
                        NVL
                        (
                            TO_CHAR(l_target_template_msg_count),
                            '0'
                        )
                    );


                    pcd_append_text
                    (
                        l_api_failure_message,
                        DBMS_LOB.SUBSTR
                        (
                            l_target_template_message,
                            3000,
                            1
                        )
                    );


                    RAISE e_api_failure;

                END IF;


                l_target_exists :=
                    f_item_exists
                    (
                        p_item_number       => l_request.item_number,
                        p_organization_id   => r_target.ebs_organization_id,
                        x_inventory_item_id => l_target_item_id,
                        x_item_status_code  => l_target_status_code
                    );


                pcd_insert_api_log
                (
                    p_execution_id      => l_execution_id,
                    p_item_request_id   => p_item_request_id,
                    p_request_org_id    => r_target.request_org_id,
                    p_process_name      => 'APPLY_TARGET_TEMPLATE',
                    p_api_name          => 'EGO_ITEM_PUB.PROCESS_ITEM',
                    p_entity_type       => 'ORGANIZATION',
                    p_entity_id         => r_target.ebs_organization_id,
                    p_log_level         => 'INFO',
                    p_process_status    => 'SUCCESS',
                    p_api_return_status => l_target_template_return_status,
                    p_api_message_count => l_target_template_msg_count,
                    p_message_text      => l_target_template_message
                );


                pcd_append_text
                (
                    l_target_combined_message,
                    'Target EBS Template applied: ' ||
                    l_target_template_name ||
                    ' / ' ||
                    r_target.ebs_template_id
                );


                pcd_append_text
                (
                    l_target_combined_message,
                    DBMS_LOB.SUBSTR
                    (
                        l_target_template_message,
                        3000,
                        1
                    )
                );


                pcd_append_text
                (
                    x_message,
                    'Target EBS Template applied to Organization ' ||
                    r_target.ebs_organization_id ||
                    ': ' ||
                    l_target_template_name ||
                    ' / ' ||
                    r_target.ebs_template_id
                );

            ELSE

                l_target_template_return_status :=
                    c_return_success;

                l_target_template_msg_count :=
                    0;


                pcd_append_text
                (
                    l_target_combined_message,
                    'No TARGET EBS Template was configured. Template update was skipped.'
                );

            END IF;


            -- =================================================================
            -- JCALZADILLA - 27.08.2026 - START CHANGE
            -- Purpose:
            -- Apply confirmed Organization-controlled application Attributes
            -- after the TARGET Template has been applied.
            --
            -- OUTSIDE_PROCESSING -> OUTSIDE_OPERATION_FLAG
            -- WIDTH              -> UNIT_WIDTH
            -- TARGET_LENGTH      -> UNIT_LENGTH
            -- WIDTH/LENGTH UOM   -> DIMENSION_UOM_CODE = IN
            -- PRICE_PER_UOM      -> LIST_PRICE_PER_UNIT
            -- LEAD_TIME_DAYS     -> ATTRIBUTE15
            -- =================================================================

            SELECT
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'OUTSIDE_PROCESSING'
                        THEN av.attribute_char_value
                    END
                ),
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'WIDTH'
                        THEN av.attribute_number_value
                    END
                ),
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'WIDTH'
                        THEN av.value_uom_code
                    END
                ),
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'TARGET_LENGTH'
                        THEN av.attribute_number_value
                    END
                ),
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'TARGET_LENGTH'
                        THEN av.value_uom_code
                    END
                ),
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'PRICE_PER_UOM'
                        THEN av.attribute_number_value
                    END
                ),
                MAX
                (
                    CASE
                        WHEN a.attribute_code = 'LEAD_TIME_DAYS'
                        THEN av.attribute_number_value
                    END
                )
            INTO
                l_outside_processing,
                l_width,
                l_width_uom,
                l_target_length,
                l_target_length_uom,
                l_price_per_uom,
                l_lead_time_days
            FROM ops.adre_inv_item_attr_value av
            JOIN ops.adre_inv_item_attribute a
              ON a.item_attribute_id = av.item_attribute_id
            WHERE av.request_org_id = r_target.request_org_id
              AND a.attribute_code IN
                  (
                      'OUTSIDE_PROCESSING',
                      'WIDTH',
                      'TARGET_LENGTH',
                      'PRICE_PER_UOM',
                      'LEAD_TIME_DAYS'
                  );


            l_target_attr_value_count :=
                  CASE WHEN l_outside_processing IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_width              IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_target_length      IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_price_per_uom      IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_lead_time_days     IS NOT NULL THEN 1 ELSE 0 END;


            IF l_target_attr_value_count > 0 THEN

                IF l_outside_processing IS NOT NULL THEN

                    l_outside_processing :=
                        UPPER(TRIM(l_outside_processing));


                    IF l_outside_processing NOT IN ('Y', 'N') THEN

                        RAISE_APPLICATION_ERROR
                        (
                            -20132,
                            'OUTSIDE_PROCESSING must be Y or N. VALUE=' ||
                            l_outside_processing
                        );

                    END IF;

                ELSE

                    l_outside_processing := apps.fnd_api.g_miss_char;

                END IF;


                IF l_width IS NOT NULL THEN

                    l_target_unit_width :=
                        f_dimension_to_inches
                        (
                            l_width,
                            l_width_uom
                        );

                    l_target_dimension_uom_code := 'IN';

                END IF;


                IF l_target_length IS NOT NULL THEN

                    l_target_unit_length :=
                        f_dimension_to_inches
                        (
                            l_target_length,
                            l_target_length_uom
                        );

                    l_target_dimension_uom_code := 'IN';

                END IF;


                BEGIN
                    apps.fnd_msg_pub.initialize;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;


                l_target_attr_item_id       := NULL;
                l_target_attr_api_org_id    := NULL;
                l_target_attr_return_status := NULL;
                l_target_attr_msg_count     := 0;
                l_target_attr_msg_data      := NULL;
                l_target_attr_message       := NULL;
                l_error_handler_message_list.DELETE;


                apps.ego_item_pub.process_item
                (
                    p_api_version             => 1.0,
                    p_init_msg_list           => c_api_true,
                    p_commit                  => c_api_false,
                    p_transaction_type        => 'UPDATE',

                    p_inventory_item_id       =>
                        NVL(l_target_item_id, l_master_item_id),

                    p_organization_id         =>
                        r_target.ebs_organization_id,

                    p_outside_operation_flag  =>
                        l_outside_processing,

                    p_dimension_uom_code      =>
                        l_target_dimension_uom_code,

                    p_unit_width              =>
                        l_target_unit_width,

                    p_unit_length             =>
                        l_target_unit_length,

                    -- =========================================================
                    -- JCALZADILLA - 31.08.2026 - START CHANGE
                    -- RAW_MATERIAL_ITEM supported TARGET Attributes.
                    -- =========================================================
                    p_list_price_per_unit     =>
                        NVL
                        (
                            l_price_per_uom,
                            apps.fnd_api.g_miss_num
                        ),

                    p_attribute15             =>
                        CASE
                            WHEN l_lead_time_days IS NULL
                                THEN apps.fnd_api.g_miss_char
                            ELSE
                                TO_CHAR
                                (
                                    l_lead_time_days,
                                    'TM9',
                                    'NLS_NUMERIC_CHARACTERS=''.,'''
                                )
                        END,

                    -- =========================================================
                    -- JCALZADILLA - 31.08.2026 - START CHANGE V7
                    -- Raw Material Lead Time is stored in both the LEADTIME
                    -- flexfield and the standard Oracle EBS Item Attribute.
                    -- =========================================================
                    p_full_lead_time          =>
                        NVL
                        (
                            l_lead_time_days,
                            apps.fnd_api.g_miss_num
                        ),
                    -- JCALZADILLA - 31.08.2026 - END CHANGE V7
                    -- JCALZADILLA - 31.08.2026 - END CHANGE

                    p_item_number             =>
                        l_ebs_item_number,

                    p_segment1                =>
                        l_item_segment1,

                    p_segment2                =>
                        l_item_segment2,

                    p_segment3                =>
                        l_item_segment3,

                    x_inventory_item_id       =>
                        l_target_attr_item_id,

                    x_organization_id         =>
                        l_target_attr_api_org_id,

                    x_return_status           =>
                        l_target_attr_return_status,

                    x_msg_count               =>
                        l_target_attr_msg_count,

                    x_msg_data                =>
                        l_target_attr_msg_data
                );


                l_target_attr_message :=
                    f_get_api_messages
                    (
                        l_target_attr_msg_count,
                        l_target_attr_msg_data
                    );


                IF l_target_attr_return_status <> c_return_success THEN

                    BEGIN

                        l_error_handler_message_list.DELETE;

                        apps.error_handler.get_message_list
                        (
                            x_message_list =>
                                l_error_handler_message_list
                        );


                        IF l_error_handler_message_list.COUNT > 0 THEN

                            FOR i IN 1 .. l_error_handler_message_list.COUNT
                            LOOP

                                pcd_append_text
                                (
                                    l_target_attr_message,
                                    'ERROR_HANDLER message ' ||
                                    i ||
                                    ': ' ||
                                    l_error_handler_message_list(i).message_text
                                );

                            END LOOP;

                        END IF;

                    EXCEPTION
                        WHEN OTHERS THEN

                            pcd_append_text
                            (
                                l_target_attr_message,
                                'Could not retrieve ERROR_HANDLER messages: ' ||
                                SQLERRM
                            );
                    END;


                    l_api_failure_status         :=
                        NVL(l_target_attr_return_status, c_return_error);

                    l_api_failure_msg_count      :=
                        NVL(l_target_attr_msg_count, 0);

                    l_api_failure_request_org_id :=
                        r_target.request_org_id;

                    l_api_failure_api_name       :=
                        'EGO_ITEM_PUB.PROCESS_ITEM';

                    l_api_failure_process_name   :=
                        'APPLY_TARGET_ATTRIBUTES';

                    l_api_failure_entity_id      :=
                        r_target.ebs_organization_id;


                    DBMS_LOB.CREATETEMPORARY
                    (
                        l_api_failure_message,
                        TRUE
                    );


                    pcd_append_text
                    (
                        l_api_failure_message,
                        'Failed to apply confirmed TARGET application Attributes.'
                    );

                    pcd_append_text
                    (
                        l_api_failure_message,
                        DBMS_LOB.SUBSTR
                        (
                            l_target_attr_message,
                            3000,
                            1
                        )
                    );


                    RAISE e_api_failure;

                END IF;


                UPDATE ops.adre_inv_item_attr_value av
                SET api_return_status  = l_target_attr_return_status,
                    api_message_count  = NVL(l_target_attr_msg_count, 0),
                    api_message_text   = l_target_attr_message,
                    api_processed_date = SYSDATE
                WHERE av.request_org_id = r_target.request_org_id
                  AND EXISTS
                      (
                          SELECT 1
                          FROM ops.adre_inv_item_attribute a
                          WHERE a.item_attribute_id = av.item_attribute_id
                            AND a.attribute_code IN
                                (
                                    'OUTSIDE_PROCESSING',
                                    'WIDTH',
                                    'TARGET_LENGTH',
                                    'PRICE_PER_UOM',
                                    'LEAD_TIME_DAYS'
                                )
                      );


                pcd_insert_api_log
                (
                    p_execution_id      => l_execution_id,
                    p_item_request_id   => p_item_request_id,
                    p_request_org_id    => r_target.request_org_id,
                    p_process_name      => 'APPLY_TARGET_ATTRIBUTES',
                    p_api_name          => 'EGO_ITEM_PUB.PROCESS_ITEM',
                    p_entity_type       => 'ORGANIZATION',
                    p_entity_id         => r_target.ebs_organization_id,
                    p_log_level         => 'INFO',
                    p_process_status    => 'SUCCESS',
                    p_api_return_status => l_target_attr_return_status,
                    p_api_message_count => l_target_attr_msg_count,
                    p_message_text      => l_target_attr_message
                );


                pcd_append_text
                (
                    l_target_combined_message,
                    'Confirmed TARGET application Attributes applied successfully.'
                );


                pcd_append_text
                (
                    x_message,
                    'TARGET application Attributes applied to Organization ' ||
                    r_target.ebs_organization_id ||
                    ': OUTSIDE_PROCESSING=' ||
                    CASE
                        WHEN l_outside_processing = apps.fnd_api.g_miss_char
                            THEN 'NOT SENT'
                        ELSE l_outside_processing
                    END ||
                    ', WIDTH=' ||
                    CASE
                        WHEN l_width IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_target_unit_width) || ' IN'
                    END ||
                    ', TARGET_LENGTH=' ||
                    CASE
                        WHEN l_target_length IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_target_unit_length) || ' IN'
                    END ||
                    ', PRICE_PER_UOM=' ||
                    CASE
                        WHEN l_price_per_uom IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_price_per_uom)
                    END ||
                    ', LEAD_TIME_DAYS=' ||
                    CASE
                        WHEN l_lead_time_days IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_lead_time_days) ||
                             ' (ATTRIBUTE15 + FULL_LEAD_TIME)'
                    END
                );

            END IF;

            -- =================================================================
            -- JCALZADILLA - 27.08.2026 - END CHANGE
            -- =================================================================


            UPDATE ops.adre_inv_item_request_org
            SET ebs_inventory_item_id =
                    NVL
                    (
                        l_target_item_id,
                        l_master_item_id
                    ),
                assignment_status =
                    c_assignment_processed,
                api_return_status =
                    NVL
                    (
                        l_target_attr_return_status,
                        NVL
                        (
                            l_target_template_return_status,
                            l_target_return_status
                        )
                    ),
                api_message_count =
                    NVL(l_target_msg_count, 0) +
                    NVL(l_target_template_msg_count, 0) +
                    NVL(l_target_attr_msg_count, 0),
                api_message_text =
                    l_target_combined_message,
                api_processed_date =
                    SYSDATE
            WHERE request_org_id =
                  r_target.request_org_id;

        END LOOP;


        -- =============================================================
        -- JCALZADILLA - 25.08.2026
        -- CALL #4 - Process all saved Category assignments.
        -- =============================================================

        pcd_assign_categories
        (
            p_item_request_id => p_item_request_id,
            p_user_id         => l_context_user_id,
            p_resp_id         => l_context_resp_id,
            p_resp_appl_id    => l_context_resp_appl_id,
            p_commit_flag     => 'N',
            x_return_status   => l_category_return_status,
            x_message         => l_category_message
        );


        pcd_append_text
        (
            x_message,
            DBMS_LOB.SUBSTR
            (
                l_category_message,
                3000,
                1
            )
        );


        IF l_category_return_status <> c_return_success THEN

            l_api_failure_status         := NVL(l_category_return_status, c_return_error);
            l_api_failure_msg_count      := 1;
            l_api_failure_request_org_id := NULL;
            l_api_failure_api_name       := 'INV_ITEM_CATEGORY_PUB';
            l_api_failure_process_name   := 'ASSIGN_CATEGORIES';
            l_api_failure_entity_id      := p_item_request_id;

            DBMS_LOB.CREATETEMPORARY
            (
                l_api_failure_message,
                TRUE
            );

            pcd_append_text
            (
                l_api_failure_message,
                'One or more Oracle EBS Category assignments failed.'
            );

            pcd_append_text
            (
                l_api_failure_message,
                DBMS_LOB.SUBSTR
                (
                    l_category_message,
                    3000,
                    1
                )
            );

            RAISE e_api_failure;

        END IF;


        IF l_validate_only_flag = 'Y' THEN

            ROLLBACK;

            x_return_status := c_return_success;

            pcd_append_text
            (
                x_message,
                'Validate-only processing completed successfully. All Oracle EBS changes were rolled back.'
            );


            IF l_commit_flag = 'Y' THEN

                pcd_insert_api_log
                (
                    p_execution_id      => l_execution_id,
                    p_item_request_id   => p_item_request_id,
                    p_request_org_id    => NULL,
                    p_process_name      => 'VALIDATE_ITEM_REQUEST',
                    p_api_name          => NULL,
                    p_entity_type       => 'ITEM_REQUEST',
                    p_entity_id         => p_item_request_id,
                    p_log_level         => 'INFO',
                    p_process_status    => 'SUCCESS',
                    p_api_return_status => c_return_success,
                    p_api_message_count => 0,
                    p_message_text      => x_message
                );

                COMMIT;

            END IF;


            RETURN;

        END IF;


        x_return_status := c_return_success;


        UPDATE ops.adre_inv_item_request
        SET request_status       = c_request_processed,
            ebs_submit_date      = NVL
                                   (
                                       ebs_submit_date,
                                       SYSDATE
                                   ),
            api_return_status    = c_return_success,
            api_message_count    =
                NVL
                (
                    l_master_msg_count,
                    0
                ),
            api_message_text     = x_message,
            api_processed_date   = SYSDATE
        WHERE item_request_id = p_item_request_id;


        pcd_append_text
        (
            x_message,
            'Item Request completed successfully.'
        );


        pcd_insert_api_log
        (
            p_execution_id      => l_execution_id,
            p_item_request_id   => p_item_request_id,
            p_request_org_id    => NULL,
            p_process_name      => 'SEND_TO_EBS',
            p_api_name          => NULL,
            p_entity_type       => 'ITEM_REQUEST',
            p_entity_id         => p_item_request_id,
            p_log_level         => 'INFO',
            p_process_status    => 'SUCCESS',
            p_api_return_status => c_return_success,
            p_api_message_count => 0,
            p_message_text      => x_message
        );


        pcd_write_log
        (
            'ADRE_CREATE_INV_ITEM',
            'Completed successfully. ITEM_REQUEST_ID=' ||
            p_item_request_id ||
            ', ITEM_NUMBER=' ||
            l_request.item_number ||
            ', MASTER_ITEM_ID=' ||
            l_master_item_id
        );


        IF l_commit_flag = 'Y' THEN
            COMMIT;
        END IF;


    EXCEPTION

        WHEN e_api_failure THEN

            ROLLBACK;

            x_return_status :=
                NVL
                (
                    l_api_failure_status,
                    c_return_error
                );

            IF l_api_failure_message IS NULL THEN

                x_message :=
                    TO_CLOB
                    (
                        'Oracle EBS API processing failed without a detailed message.'
                    );

            ELSE
                x_message := l_api_failure_message;
            END IF;


            BEGIN

                UPDATE ops.adre_inv_item_request
                SET request_status     = c_request_error,
                    api_return_status  = x_return_status,
                    api_message_count  = NVL(l_api_failure_msg_count, 1),
                    api_message_text   = x_message,
                    api_processed_date = SYSDATE
                WHERE item_request_id = p_item_request_id;


                IF l_api_failure_request_org_id IS NOT NULL THEN

                    UPDATE ops.adre_inv_item_request_org
                    SET assignment_status = c_assignment_error,
                        api_return_status  = x_return_status,
                        api_message_count  = NVL(l_api_failure_msg_count, 1),
                        api_message_text   = x_message,
                        api_processed_date = SYSDATE
                    WHERE request_org_id = l_api_failure_request_org_id;

                END IF;


                pcd_insert_api_log
                (
                    p_execution_id      => l_execution_id,
                    p_item_request_id   => p_item_request_id,
                    p_request_org_id    => l_api_failure_request_org_id,
                    p_process_name      => NVL(l_api_failure_process_name, 'SEND_TO_EBS'),
                    p_api_name          => l_api_failure_api_name,
                    p_entity_type       =>
                        CASE
                            WHEN l_api_failure_request_org_id IS NULL
                                THEN 'ITEM_REQUEST'
                            ELSE 'ORGANIZATION'
                        END,
                    p_entity_id         => NVL(l_api_failure_entity_id, p_item_request_id),
                    p_log_level         => 'ERROR',
                    p_process_status    => 'ERROR',
                    p_api_return_status => x_return_status,
                    p_api_message_count => NVL(l_api_failure_msg_count, 1),
                    p_message_text      => x_message
                );


                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;


        WHEN NO_DATA_FOUND THEN

            ROLLBACK;

            x_return_status :=
                c_return_error;

            x_message :=
                TO_CLOB
                (
                    'Required Item Request, Request Organization, Template, ' ||
                    'Item Status, or Oracle EBS configuration data was not found. ' ||
                    'ITEM_REQUEST_ID=' || p_item_request_id
                );


            BEGIN

                UPDATE ops.adre_inv_item_request
                SET request_status     = c_request_error,
                    api_return_status  = c_return_error,
                    api_message_count  = 1,
                    api_message_text   = x_message,
                    api_processed_date = SYSDATE
                WHERE item_request_id = p_item_request_id;


                pcd_insert_api_log
                (
                    p_execution_id      => l_execution_id,
                    p_item_request_id   => p_item_request_id,
                    p_request_org_id    => NULL,
                    p_process_name      => 'SEND_TO_EBS',
                    p_api_name          => NULL,
                    p_entity_type       => 'ITEM_REQUEST',
                    p_entity_id         => p_item_request_id,
                    p_log_level         => 'ERROR',
                    p_process_status    => 'ERROR',
                    p_api_return_status => c_return_error,
                    p_api_message_count => 1,
                    p_message_text      => x_message
                );


                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;


        WHEN OTHERS THEN

            l_error_text :=
                'Unexpected Item Request processing error. ITEM_REQUEST_ID=' ||
                p_item_request_id ||
                ', SQLERRM=' ||
                SQLERRM ||
                ', BACKTRACE=' ||
                DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;


            ROLLBACK;


            x_return_status :=
                c_return_unexpected;

            x_message :=
                TO_CLOB
                (
                    l_error_text
                );


            pcd_write_log
            (
                'ADRE_CREATE_INV_ITEM',
                l_error_text
            );


            BEGIN

                UPDATE ops.adre_inv_item_request
                SET request_status     = c_request_error,
                    api_return_status  = c_return_unexpected,
                    api_message_count  = 1,
                    api_message_text   = x_message,
                    api_processed_date = SYSDATE
                WHERE item_request_id = p_item_request_id;


                pcd_insert_api_log
                (
                    p_execution_id      => l_execution_id,
                    p_item_request_id   => p_item_request_id,
                    p_request_org_id    => NULL,
                    p_process_name      => 'SEND_TO_EBS',
                    p_api_name          => NULL,
                    p_entity_type       => 'ITEM_REQUEST',
                    p_entity_id         => p_item_request_id,
                    p_log_level         => 'ERROR',
                    p_process_status    => 'ERROR',
                    p_api_return_status => c_return_unexpected,
                    p_api_message_count => 1,
                    p_message_text      => x_message
                );


                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

    END pcd_process_request;

END adre_create_inv_item;
/

SHOW ERRORS PACKAGE BODY apps.adre_create_inv_item

-- =====================================================================
-- JCALZADILLA - 25.08.2026 - END CHANGE
-- =====================================================================
