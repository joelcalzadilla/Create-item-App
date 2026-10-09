-- =====================================================================
-- Adhesives Research
-- Package   : APPS.ADRE_CREATE_INV_ITEM
-- Component : Package Specification and Body
-- Author    : Joel Calzadilla
-- Date      : 10/07/2026
-- Version   : V34
-- Purpose   : Processes staged inventory item requests in Oracle EBS,
--             resolves configured item types, templates and categories,
--             assigns organizations, applies eligible attributes and
--             records the verified result in OPS.
-- EntryPoint : pcd_process_request
-- =====================================================================

CREATE OR REPLACE PACKAGE apps.adre_create_inv_item AS
    PROCEDURE pcd_process_request
    (
        p_item_request_id IN NUMBER,
        p_validate_only_flag IN VARCHAR2 DEFAULT 'N',
        p_user_id IN NUMBER DEFAULT NULL,
        p_resp_id IN NUMBER DEFAULT NULL,
        p_resp_appl_id IN NUMBER DEFAULT NULL,
        p_commit_flag IN VARCHAR2 DEFAULT 'Y',
        x_return_status OUT VARCHAR2,
        x_message OUT CLOB
    );
    FUNCTION fnc_release_version RETURN VARCHAR2;
END adre_create_inv_item;
/

CREATE OR REPLACE PACKAGE BODY apps.adre_create_inv_item AS
    c_application_code      CONSTANT VARCHAR2(30)  := 'XINV';
    c_return_success        CONSTANT VARCHAR2(1)   := 'S';
    c_return_error          CONSTANT VARCHAR2(1)   := 'E';
    c_return_unexpected     CONSTANT VARCHAR2(1)   := 'U';
    c_api_true              CONSTANT VARCHAR2(1)   := 'T';
    c_api_false             CONSTANT VARCHAR2(1)   := 'F';
    c_request_ready         CONSTANT VARCHAR2(30)  := 'READY';
    c_request_processing    CONSTANT VARCHAR2(30)  := 'PROCESSING';
    c_request_processed     CONSTANT VARCHAR2(30)  := 'PROCESSED';
    c_request_error         CONSTANT VARCHAR2(30)  := 'ERROR';
    c_assignment_ready      CONSTANT VARCHAR2(30)  := 'READY';
    c_assignment_processing CONSTANT VARCHAR2(30)  := 'PROCESSING';
    c_assignment_processed  CONSTANT VARCHAR2(30)  := 'PROCESSED';
    c_assignment_error      CONSTANT VARCHAR2(30)  := 'ERROR';
    c_assignment_skipped    CONSTANT VARCHAR2(30)  := 'SKIPPED';
    c_category_control_item CONSTANT NUMBER        := 1;
    c_category_control_org  CONSTANT NUMBER        := 2;
    c_missing_char          CONSTANT VARCHAR2(1)   := CHR(0);
    c_number_format         CONSTANT VARCHAR2(80)  := '999999999999999999999999999999D999999999999999999999999999';
    g_inventory_application_id NUMBER;
    g_text_correction_flag     VARCHAR2(1) := 'N';
    g_fnd_log_initialized      BOOLEAN := FALSE;
    g_default_user_name          CONSTANT VARCHAR2(100) := 'CWILLS';
    g_default_application_name   CONSTANT VARCHAR2(100) := 'Inventory';
    g_default_responsibility_key CONSTANT VARCHAR2(100) := 'INVENTORY';

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_write_log (forward declaration)
    -- Purpose    : Write diagnostic information to the EBS application log without interrupting
    --              the caller.
    -- Parameters:
    --   p_business_process IN VARCHAR2 - Name of the process associated with the log entry.
    --   p_message IN VARCHAR2 - Diagnostic text to write to the log.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_write_log
    (
        p_business_process IN VARCHAR2,
        p_message IN VARCHAR2
    );

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_append_text
    -- Purpose    : Append one diagnostic line to a temporary CLOB, creating it when needed.
    -- Parameters:
    --   io_clob IN OUT NOCOPY CLOB - Text buffer updated with the appended line.
    --   p_text IN VARCHAR2 - Text to append to the CLOB.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_append_text
    (
        io_clob IN OUT NOCOPY CLOB,
        p_text IN VARCHAR2
    )
    IS
    BEGIN
        IF io_clob IS NULL THEN
            dbms_lob.createtemporary
            (
                io_clob,
                TRUE
            );
        END IF;
        dbms_lob.append
        (
            io_clob,
            TO_CLOB
            (
                NVL(p_text, '') || CHR(10)
            )
        );
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_APPEND_TEXT',
                SQLERRM
            );
            raise_application_error
            (
                -20000,
                'Unexpected Error in pcd_append_text: ' || SQLERRM,
                TRUE
            );
    END pcd_append_text;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_get_session_user
    -- Purpose    : Identify the current APEX user, falling back to the database session user.
    -- Parameters:
    --   None.
    -- Returns   : VARCHAR2 - Current APEX user or database user.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_get_session_user
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
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'F_GET_SESSION_USER',
                SQLERRM
            );
            raise_application_error
            (
                -20005,
                'Unexpected Error in fnc_get_session_user: ' || SQLERRM,
                TRUE
            );
    END fnc_get_session_user;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_write_log
    -- Purpose    : Write diagnostic information to the EBS application log without interrupting
    --              the caller.
    -- Parameters:
    --   p_business_process IN VARCHAR2 - Name of the process associated with the log entry.
    --   p_message IN VARCHAR2 - Diagnostic text to write to the log.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_write_log
    (
        p_business_process IN VARCHAR2,
        p_message IN VARCHAR2
    )
    IS
        l_module VARCHAR2(200) := 'ADRE.CREATE_INV_ITEM.' || SUBSTR(p_business_process, 1, 120);
    BEGIN
        IF NOT g_fnd_log_initialized THEN
            apps.fnd_profile.put('AFLOG_ENABLED', 'Y');
            apps.fnd_profile.put('AFLOG_MODULE', 'ADRE.CREATE_INV_ITEM%');
            apps.fnd_profile.put('AFLOG_LEVEL', TO_CHAR(apps.fnd_log.level_statement));
            apps.fnd_profile.put('AFLOG_FILENAME', NULL);
            apps.fnd_log_repository.init();
            g_fnd_log_initialized := TRUE;
        END IF;
        apps.fnd_log.string
        (
            apps.fnd_log.level_statement,
            l_module,
            SUBSTR(p_message, 1, 4000)
        );
    EXCEPTION
        WHEN OTHERS THEN
            raise_application_error
            (
                -20010,
                'Unexpected Error in pcd_write_log: ' || SQLERRM,
                TRUE
            );
    END pcd_write_log;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_insert_api_log
    -- Purpose    : Record one API execution event and its outcome in the OPS audit table.
    -- Parameters:
    --   p_execution_id IN VARCHAR2 - Correlation identifier for this execution.
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_request_org_id IN NUMBER - OPS assignment identifying the staged organization values.
    --   p_process_name IN VARCHAR2 - Processing step associated with the API event.
    --   p_api_name IN VARCHAR2 - EBS API name associated with the event.
    --   p_entity_type IN VARCHAR2 - Kind of business entity involved in the event.
    --   p_entity_id IN NUMBER - Identifier of the EBS entity involved in the event.
    --   p_log_level IN VARCHAR2 - Severity assigned to the audit event.
    --   p_process_status IN VARCHAR2 - Outcome of the processing step.
    --   p_api_return_status IN VARCHAR2 - Status returned by the EBS API.
    --   p_api_message_count IN NUMBER - Number of messages reported by the API.
    --   p_message_text IN CLOB - Detailed API or processing message to store.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_insert_api_log
    (
        p_execution_id IN VARCHAR2,
        p_item_request_id IN NUMBER,
        p_request_org_id IN NUMBER,
        p_process_name IN VARCHAR2,
        p_api_name IN VARCHAR2,
        p_entity_type IN VARCHAR2,
        p_entity_id IN NUMBER,
        p_log_level IN VARCHAR2,
        p_process_status IN VARCHAR2,
        p_api_return_status IN VARCHAR2,
        p_api_message_count IN NUMBER,
        p_message_text IN CLOB
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
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_INSERT_API_LOG',
                SQLERRM
            );
            raise_application_error
            (
                -20015,
                'Unexpected Error in pcd_insert_api_log: ' || SQLERRM,
                TRUE
            );
    END pcd_insert_api_log;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_initialize_ebs_context
    -- Purpose    : Resolve and validate the EBS user and responsibility, then initialize the
    --              application context.
    -- Parameters:
    --   p_user_id IN NUMBER - EBS user identifier; NULL invokes the existing context fallback.
    --   p_resp_id IN NUMBER - EBS responsibility identifier; NULL invokes the existing context
    --     fallback.
    --   p_resp_appl_id IN NUMBER - EBS responsibility application identifier; NULL uses the
    --     existing fallback.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_initialize_ebs_context
    (
        p_user_id IN NUMBER,
        p_resp_id IN NUMBER,
        p_resp_appl_id IN NUMBER
    )
    IS
        l_user_id              NUMBER := p_user_id;
        l_resp_id              NUMBER := p_resp_id;
        l_resp_appl_id         NUMBER := p_resp_appl_id;
        l_count                NUMBER;
        l_development_fallback BOOLEAN := FALSE;
    BEGIN
        IF l_user_id IS NULL AND l_resp_id IS NULL AND l_resp_appl_id IS NULL THEN
            l_development_fallback := TRUE;
            SELECT
                fnduse.user_id,
                fnrevl.responsibility_id,
                fnrevl.application_id
            INTO
                l_user_id,
                l_resp_id,
                l_resp_appl_id
            FROM
                apps.fnd_user fnduse,
                apps.fnd_responsibility_vl fnrevl,
                apps.fnd_application_vl fnapvl
            WHERE  UPPER(fnduse.user_name)   = UPPER(g_default_user_name)
              AND  fnrevl.responsibility_key = g_default_responsibility_key
              AND  fnapvl.application_id     = fnrevl.application_id
              AND  fnapvl.application_name   = g_default_application_name;
        ELSIF l_user_id IS NULL OR l_resp_id IS NULL OR l_resp_appl_id IS NULL THEN
            raise_application_error
            (
                -20020,
                'Supply all EBS context values or leave all three NULL to use the established development fallback.'
            );
        END IF;
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            apps.fnd_user fnduse,
            apps.fnd_responsibility fndres,
            apps.fnd_application fndapp
        WHERE  fnduse.user_id           = l_user_id
          AND  fndres.responsibility_id = l_resp_id
          AND  fndres.application_id    = l_resp_appl_id
          AND  fndapp.application_id    = fndres.application_id
          AND  (fnduse.start_date       IS NULL OR fnduse.start_date <= SYSDATE)
          AND  (fnduse.end_date         IS NULL OR fnduse.end_date   >= SYSDATE)
          AND  (fndres.start_date       IS NULL OR fndres.start_date <= SYSDATE)
          AND  (fndres.end_date         IS NULL OR fndres.end_date   >= SYSDATE);
        IF l_count <> 1 THEN
            raise_application_error
            (
                -20025,
                'Invalid or inactive EBS user, responsibility, or application.'
            );
        END IF;
        IF NOT l_development_fallback THEN
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                apps.fnd_user_resp_groups fnusregr
            WHERE  fnusregr.user_id                       = l_user_id
              AND  fnusregr.responsibility_id             = l_resp_id
              AND  fnusregr.responsibility_application_id = l_resp_appl_id
              AND  (fnusregr.start_date                   IS NULL OR fnusregr.start_date <= SYSDATE)
              AND  (fnusregr.end_date                     IS NULL OR fnusregr.end_date   >= SYSDATE);
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20030,
                    'Invalid or inactive EBS user/responsibility/application assignment.'
                );
            END IF;
        END IF;
        SELECT
            application_id
        INTO
            g_inventory_application_id
        FROM
            apps.fnd_application
        WHERE  application_short_name = 'INV';
        apps.fnd_global.apps_initialize
        (
            user_id      => l_user_id,
            resp_id      => l_resp_id,
            resp_appl_id => l_resp_appl_id
        );
        BEGIN
            apps.mo_global.init('INV');
        EXCEPTION
            WHEN OTHERS THEN
                pcd_write_log
                (
                    'PCD_INITIALIZE_EBS_CONTEXT',
                    'MO_GLOBAL.INIT returned: ' || SQLERRM
                );
                raise_application_error
                (
                    -20035,
                    'Unexpected Error in pcd_initialize_ebs_context: ' || SQLERRM,
                    TRUE
                );
        END;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_INITIALIZE_EBS_CONTEXT',
                SQLERRM
            );
            raise_application_error
            (
                -20040,
                'Unexpected Error in pcd_initialize_ebs_context: ' || SQLERRM,
                TRUE
            );
    END pcd_initialize_ebs_context;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_append_ego_error_messages
    -- Purpose    : Append messages from the EGO error handler to the caller diagnostic text.
    -- Parameters:
    --   io_message IN OUT NOCOPY CLOB - Accumulated processing details updated by this routine.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_append_ego_error_messages
    (
        io_message IN OUT NOCOPY CLOB
    )
    IS
        l_errors apps.error_handler.error_tbl_type;
        l_index  BINARY_INTEGER;
    BEGIN
        apps.error_handler.get_message_list(x_message_list => l_errors);
        pcd_append_text
        (
            io_message,
            'ERROR_HANDLER entries=' || l_errors.count
        );
        l_index := l_errors.first;
        WHILE l_index IS NOT NULL LOOP
            pcd_append_text(io_message, 'ERROR_HANDLER message ' || l_index || ': ' ||
                NVL(l_errors(l_index).message_text, '[empty message_text]'));
            l_index := l_errors.next(l_index);
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
        pcd_append_text
        (
            io_message,
            'Could not read ERROR_HANDLER: ' || SQLERRM
        );
            raise_application_error
            (
                -20045,
                'Unexpected Error in pcd_append_ego_error_messages: ' || SQLERRM,
                TRUE
            );
    END pcd_append_ego_error_messages;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_get_api_messages
    -- Purpose    : Collect API message data and FND message stack details into a CLOB.
    -- Parameters:
    --   p_msg_count IN NUMBER - Number of API messages to retrieve from the FND stack.
    --   p_msg_data IN VARCHAR2 - Optional message text returned directly by the API.
    -- Returns   : CLOB - Aggregated API and FND diagnostics.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_get_api_messages
    (
        p_msg_count IN NUMBER,
        p_msg_data IN VARCHAR2 DEFAULT NULL
    )
    RETURN CLOB
    IS
        l_message_text  CLOB;
        l_fnd_message   VARCHAR2(4000);
        l_msg_index_out NUMBER;
        l_stack_count   NUMBER;
        l_stack_data    VARCHAR2(4000);
    BEGIN
        dbms_lob.createtemporary
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
                p_count => l_stack_count,
                p_data => l_stack_data
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
                raise_application_error
                (
                    -20050,
                    'Unexpected Error in fnc_get_api_messages: ' || SQLERRM,
                    TRUE
                );
        END;
        IF NVL(p_msg_count, 0) > 0 THEN
            FOR i IN 1 .. p_msg_count
            LOOP
                BEGIN
                    apps.fnd_msg_pub.get
                    (
                        p_msg_index => i,
                        p_encoded => apps.fnd_api.g_false,
                        p_data => l_fnd_message,
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
                        raise_application_error
                        (
                            -20055,
                            'Unexpected Error in fnc_get_api_messages: ' || SQLERRM,
                            TRUE
                        );
                END;
            END LOOP;
        END IF;
        IF dbms_lob.getlength(l_message_text) = 0 THEN
            pcd_append_text
            (
                l_message_text,
                'No detailed FND message was returned; see ERROR_HANDLER details when present.'
            );
        END IF;
        RETURN l_message_text;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'F_GET_API_MESSAGES',
                SQLERRM
            );
            raise_application_error
            (
                -20060,
                'Unexpected Error in fnc_get_api_messages: ' || SQLERRM,
                TRUE
            );
    END fnc_get_api_messages;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_optional_char
    -- Purpose    : Represent an absent optional character input with the package missing-value
    --              marker.
    -- Parameters:
    --   p_value IN VARCHAR2 - Input value to convert or normalize.
    -- Returns   : VARCHAR2 - Input value or missing-value marker.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_optional_char
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
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'F_OPTIONAL_CHAR',
                SQLERRM
            );
            raise_application_error
            (
                -20065,
                'Unexpected Error in fnc_optional_char: ' || SQLERRM,
                TRUE
            );
    END fnc_optional_char;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_convert_dimension
    -- Purpose    : Convert a dimension between active EBS units in the same unit class.
    -- Parameters:
    --   p_value IN NUMBER - Input value to convert or normalize.
    --   p_from_uom IN VARCHAR2 - Source dimension unit of measure.
    --   p_to_uom IN VARCHAR2 - Destination dimension unit of measure.
    -- Returns   : NUMBER - Converted dimension in the destination unit.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_convert_dimension
    (
        p_value IN NUMBER,
        p_from_uom IN VARCHAR2,
        p_to_uom IN VARCHAR2
    )
    RETURN NUMBER
    IS
        l_from_code  VARCHAR2(30);
        l_to_code    VARCHAR2(30);
        l_from_class VARCHAR2(30);
        l_to_class   VARCHAR2(30);
        l_from_rate  NUMBER;
        l_to_rate    NUMBER;
    BEGIN
        IF p_value IS NULL THEN
            RETURN NULL;
        END IF;
        IF p_value <= 0 THEN
            raise_application_error
            (
                -20070,
                'Dimension must be greater than zero.'
            );
        END IF;
        SELECT
            uom_code,
            uom_class
        INTO
            l_from_code,
            l_from_class
        FROM
            apps.mtl_units_of_measure_vl
        WHERE  (UPPER(TRIM(uom_code)) = UPPER(TRIM(p_from_uom)) OR UPPER(TRIM(unit_of_measure)) = UPPER(TRIM(p_from_uom)))
          AND  (disable_date          IS NULL OR disable_date > SYSDATE);
        SELECT
            uom_code,
            uom_class
        INTO
            l_to_code,
            l_to_class
        FROM
            apps.mtl_units_of_measure_vl
        WHERE  (UPPER(TRIM(uom_code)) = UPPER(TRIM(p_to_uom)) OR UPPER(TRIM(unit_of_measure)) = UPPER(TRIM(p_to_uom)))
          AND  (disable_date          IS NULL OR disable_date > SYSDATE);
        IF l_from_class IS NULL OR l_to_class IS NULL OR l_from_class <> l_to_class THEN
            raise_application_error
            (
                -20075,
                'Dimension UOMs must belong to the same EBS class.'
            );
        END IF;
        IF l_from_code = l_to_code THEN
            RETURN p_value;
        END IF;
        SELECT
            conversion_rate
        INTO
            l_from_rate
        FROM
            apps.mtl_uom_conversions
        WHERE  inventory_item_id = 0
          AND  uom_code          = l_from_code
          AND  (disable_date     IS NULL OR disable_date > SYSDATE);
        SELECT
            conversion_rate
        INTO
            l_to_rate
        FROM
            apps.mtl_uom_conversions
        WHERE  inventory_item_id = 0
          AND  uom_code          = l_to_code
          AND  (disable_date     IS NULL OR disable_date > SYSDATE);
        IF l_from_rate IS NULL OR l_to_rate IS NULL OR l_from_rate <= 0 OR l_to_rate <= 0 THEN
            raise_application_error
            (
                -20080,
                'EBS standard UOM conversion rate is missing or invalid.'
            );
        END IF;
        RETURN p_value * l_from_rate / l_to_rate;
    EXCEPTION
        WHEN no_data_found THEN
            raise_application_error
            (
                -20085,
                'Missing active EBS dimension UOM/conversion: ' || p_from_uom || ' -> ' || p_to_uom
            );
        WHEN too_many_rows THEN
            raise_application_error
            (
                -20090,
                'Ambiguous EBS dimension UOM/conversion: ' || p_from_uom || ' -> ' || p_to_uom
            );
        WHEN OTHERS THEN
            raise_application_error
            (
                -20095,
                'Unexpected Error in fnc_convert_dimension: ' || SQLERRM,
                TRUE
            );
    END fnc_convert_dimension;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_shelf_life_control
    -- Purpose    : Resolve the staged shelf-life control value to its configured EBS lookup code.
    -- Parameters:
    --   p_request_org_id IN NUMBER - OPS assignment identifying the staged organization values.
    -- Returns   : NUMBER - Resolved EBS shelf-life control code or missing-value number.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_shelf_life_control
    (
        p_request_org_id IN NUMBER
    )
    RETURN NUMBER
    IS
        l_value VARCHAR2(4000);
        l_count NUMBER;
        l_code  NUMBER;
    BEGIN
        SELECT
            COUNT(*),
            MAX(av.attribute_value)
        INTO
            l_count,
            l_value
        FROM
            (
                SELECT
                    adinitatva.*
                FROM
                    ops.adre_inv_item_attr_value adinitatva,
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_request adinitre,
                    ops.adre_inv_item_type adinitty,
                    ops.adre_inv_item_attribute adinitat
                WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                  AND  adinitre.item_request_id    = adinitreor.item_request_id
                  AND  adinitty.item_type_id       = adinitre.item_type_id
                  AND  adinitty.active_flag        = 'Y'
                  AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                  AND  adinitat.active_flag        = 'Y'
                  AND  (adinitatva.value_status    = 'READY'
                        OR (g_text_correction_flag = 'Y'
                  AND  adinitatva.value_status     = 'PROCESSED'
                  AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                  AND  EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_type_attr adinittyat
                        WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                          AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                          AND  adinittyat.active_flag        = 'Y'
                          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                    )
            )
            av,
            ops.adre_inv_item_attribute adinitat
        WHERE  adinitat.item_attribute_id = av.item_attribute_id
          AND  av.request_org_id          = p_request_org_id
          AND  adinitat.attribute_code    = 'SHELF_LIFE_CONTROL';
        IF l_count > 1 THEN
            raise_application_error
            (
                -20100,
                'Duplicate staged SHELF_LIFE_CONTROL.'
            );
        END IF;
        IF TRIM(l_value) IS NULL THEN
            RETURN apps.fnd_api.g_miss_num;
        END IF;
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            ops.adre_inv_item_attribute adinitat,
            ops.adre_inv_item_type_attr adinittyat,
            ops.adre_inv_item_request adinitre,
            ops.adre_inv_item_request_org adinitreor,
            (
                SELECT
                    adinitatva.*
                FROM
                    ops.adre_inv_item_attr_value adinitatva,
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_request adinitre,
                    ops.adre_inv_item_type adinitty,
                    ops.adre_inv_item_attribute adinitat
                WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                  AND  adinitre.item_request_id    = adinitreor.item_request_id
                  AND  adinitty.item_type_id       = adinitre.item_type_id
                  AND  adinitty.active_flag        = 'Y'
                  AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                  AND  adinitat.active_flag        = 'Y'
                  AND  (adinitatva.value_status    = 'READY'
                        OR (g_text_correction_flag = 'Y'
                  AND  adinitatva.value_status     = 'PROCESSED'
                  AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                  AND  EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_type_attr adinittyat
                        WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                          AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                          AND  adinittyat.active_flag        = 'Y'
                          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                    )
            )
            av
        WHERE  adinittyat.item_attribute_id  = adinitat.item_attribute_id
          AND  adinitre.item_type_id         = adinittyat.item_type_id
          AND  adinitreor.item_request_id    = adinitre.item_request_id
          AND  av.request_org_id             = adinitreor.request_org_id
          AND  av.item_attribute_id          = adinitat.item_attribute_id
          AND  adinitreor.request_org_id     = p_request_org_id
          AND  adinitat.attribute_code       = 'SHELF_LIFE_CONTROL'
          AND  adinitat.attribute_data_type  = 'CHAR'
          AND  adinitat.active_flag          = 'Y'
          AND  adinittyat.active_flag        = 'Y'
          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
          AND  adinitat.ebs_attribute_name   = 'SHELF_LIFE_CODE'
          AND  av.value_status               IN ('READY', 'PROCESSED');
        IF l_count <> 1 THEN
            raise_application_error
            (
                -20105,
                'SHELF_LIFE_CONTROL input must be configured and READY.'
            );
        END IF;
        SELECT
            COUNT(*),
            MIN(code)
        INTO
            l_count,
            l_code
        FROM
            (
                SELECT
                    CASE WHEN REGEXP_LIKE(TRIM(fnlovavl.lookup_code), '^[0-9]+$') THEN TO_NUMBER(TRIM(fnlovavl.lookup_code)) END code
                FROM
                    apps.fnd_lookup_values_vl fnlovavl
                WHERE  fnlovavl.lookup_type                                                   = 'MTL_SHELF_LIFE'
                  AND  fnlovavl.enabled_flag                                                  = 'Y'
                  AND  (fnlovavl.start_date_active                                            IS NULL OR fnlovavl.start_date_active <= SYSDATE)
                  AND  (fnlovavl.end_date_active                                              IS NULL OR fnlovavl.end_date_active > SYSDATE)
                  AND  REGEXP_REPLACE(UPPER(TRIM(fnlovavl.meaning)), '^ITEM[[:space:]]+', '') = REGEXP_REPLACE(UPPER(TRIM(l_value)), '^ITEM[[:space:]]+', '')
            );
        IF l_count <> 1 OR l_code IS NULL THEN
            raise_application_error
            (
                -20110,
                'No unique EBS shelf-life control mapping for: ' || l_value
            );
        END IF;
        RETURN l_code;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'F_SHELF_LIFE_CONTROL',
                SQLERRM
            );
            raise_application_error
            (
                -20115,
                'Unexpected Error in fnc_shelf_life_control: ' || SQLERRM,
                TRUE
            );
    END fnc_shelf_life_control;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_verify_attributes
    -- Purpose    : Compare eligible staged attributes with the item values persisted in EBS.
    -- Parameters:
    --   p_request_org_id IN NUMBER - OPS assignment identifying the staged organization values.
    --   p_inventory_item_id IN NUMBER - EBS inventory item identifier to inspect or update.
    --   p_organization_id IN NUMBER - EBS organization identifier to inspect or update.
    --   p_phase IN VARCHAR2 - Master or target processing phase used for verification.
    --   p_mrp_planning_code IN NUMBER - Expected resolved MRP planning code, when supplied.
    --   p_construction IN VARCHAR2 - Expected Construction flexfield text, when supplied.
    --   p_template_rule_id IN NUMBER - Resolved template rule used during attribute verification.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_verify_attributes
    (
        p_request_org_id IN NUMBER,
        p_inventory_item_id IN NUMBER,
        p_organization_id IN NUMBER,
        p_phase IN VARCHAR2,
        p_mrp_planning_code IN NUMBER DEFAULT NULL,
        p_construction IN VARCHAR2 DEFAULT NULL,
        p_template_rule_id IN NUMBER DEFAULT NULL
    )
    IS
        l_item            apps.mtl_system_items_b%ROWTYPE;
        l_expected_char   VARCHAR2(4000);
        l_actual_char     VARCHAR2(4000);
        l_expected_number NUMBER;
        l_actual_number   NUMBER;
        l_numeric         BOOLEAN;
        l_type_code       VARCHAR2(100);
        l_count           NUMBER;
    BEGIN
        SELECT
            *
        INTO
            l_item
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = p_inventory_item_id
          AND  organization_id   = p_organization_id;
        SELECT
            adinitty.item_type_code
        INTO
            l_type_code
        FROM
            ops.adre_inv_item_request_org adinitreor,
            ops.adre_inv_item_request adinitre,
            ops.adre_inv_item_type adinitty
        WHERE  adinitreor.request_org_id = p_request_org_id
          AND  adinitre.item_request_id  = adinitreor.item_request_id
          AND  adinitty.item_type_id     = adinitre.item_type_id;
        FOR r IN
        (
            SELECT
                v.*,
                adinitat.attribute_code
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                v,
                ops.adre_inv_item_attribute adinitat
            WHERE  v.request_org_id             = p_request_org_id
              AND  adinitat.item_attribute_id   = v.item_attribute_id
              AND  v.attribute_value IS NOT NULL
            ORDER BY
                v.item_attr_value_id
        )
        LOOP
            IF r.attribute_code IN
               ('WIDTH', 'TARGET_LENGTH', 'PRICE_PER_UOM', 'LEAD_TIME_DAYS',
                'SHELF_LIFE_DAYS', 'PERCENT_SOLIDS', 'WEIGHT_PER_GALLON')
            THEN
                IF r.attribute_value IS NULL THEN
                    CONTINUE;
                END IF;
            ELSIF r.attribute_value IS NULL
                OR (r.attribute_code = 'SHELF_LIFE_CONTROL'
                AND TRIM(r.attribute_value) IS NULL)
            THEN
                CONTINUE;
            END IF;
            l_numeric := FALSE;
            l_expected_char := r.attribute_value;
            l_actual_char := NULL;
            l_expected_number := NULL;
            l_actual_number := NULL;
            IF p_phase = 'MASTER' THEN
                CASE r.attribute_code
                    WHEN 'ENGINEERING_ITEM_FLAG' THEN
                        l_expected_char := UPPER(TRIM(r.attribute_value));
                        l_actual_char := l_item.eng_item_flag;
                    WHEN 'HIMS' THEN
                        l_actual_char := l_item.attribute14;
                    WHEN 'PLANNING_METHOD' THEN
                        l_numeric := TRUE;
                        l_expected_number := p_mrp_planning_code;
                        l_actual_number := l_item.mrp_planning_code;
                    ELSE
                        CONTINUE;
                END CASE;
            ELSIF p_phase = 'TARGET' THEN
                CASE r.attribute_code
                    WHEN 'OUTSIDE_PROCESSING' THEN
                        l_expected_char := UPPER(TRIM(r.attribute_value));
                        l_actual_char := l_item.outside_operation_flag;
                    WHEN 'WIDTH' THEN
                        l_numeric := TRUE;
                        l_expected_number := fnc_convert_dimension
                        (
                            TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,'''),
                            r.value_uom_code,
                            l_item.dimension_uom_code
                        );
                        l_actual_number := l_item.unit_width;
                    WHEN 'TARGET_LENGTH' THEN
                        l_numeric := TRUE;
                        l_expected_number := fnc_convert_dimension
                        (
                            TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,'''),
                            r.value_uom_code,
                            l_item.dimension_uom_code
                        );
                        l_actual_number := l_item.unit_length;
                    WHEN 'PRICE_PER_UOM' THEN
                        l_numeric := TRUE;
                        l_expected_number := TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''');
                        l_actual_number := l_item.list_price_per_unit;
                    WHEN 'LEAD_TIME_DAYS' THEN
                        l_expected_char := TO_CHAR(TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,'''), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
                        l_actual_char := l_item.attribute15;
                        IF (l_type_code = 'RAW_MATERIAL_ITEM'
                AND (l_item.full_lead_time IS NULL
                            OR l_item.full_lead_time <> TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''')))
                            OR (l_type_code <> 'RAW_MATERIAL_ITEM' AND l_item.full_lead_time IS NOT NULL)
                        THEN
                            raise_application_error
                            (
                                -20120,
                                'FULL_LEAD_TIME postcondition failed. REQUEST_ORG_ID=' || p_request_org_id
                            );
                        END IF;
                    WHEN 'BATCH_SIZE' THEN
                        l_expected_char := TRIM(r.attribute_value);
                        l_actual_char := l_item.attribute9;
                    WHEN 'SHELF_LIFE_DAYS' THEN
                        l_numeric := TRUE;
                        l_expected_number := TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''');
                        l_actual_number := l_item.shelf_life_days;
                    WHEN 'SHELF_LIFE_CONTROL' THEN
                        l_numeric := TRUE;
                        l_expected_number := fnc_shelf_life_control(p_request_org_id);
                        l_actual_number := l_item.shelf_life_code;
                    WHEN 'PLANNER' THEN
                        l_expected_char := TRIM(r.attribute_value);
                        l_actual_char := l_item.planner_code;
                    WHEN 'SHIPPABLE_ITEM_FLAG' THEN
                        l_expected_char := UPPER(TRIM(r.attribute_value));
                        l_actual_char := l_item.shippable_item_flag;
                    WHEN 'PDR_NUMBER' THEN
                        l_expected_char := TRIM(r.attribute_value);
                        l_actual_char := l_item.attribute1;
                    WHEN 'PERCENT_SOLIDS' THEN
                        l_expected_char := TO_CHAR(TO_NUMBER(r.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,'''), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
                        l_actual_char := l_item.attribute16;
                    WHEN 'WEIGHT_PER_GALLON' THEN
                        l_expected_char := p_construction;
                        l_actual_char := l_item.attribute3;
                        IF l_item.weight_uom_code IS NOT NULL OR l_item.unit_weight IS NOT NULL THEN
                            raise_application_error
                            (
                                -20125,
                                'Physical weight was not cleared. REQUEST_ORG_ID=' || p_request_org_id
                            );
                        END IF;
                    WHEN 'CONSTRUCTION' THEN
                        l_expected_char := TRIM(r.attribute_value);
                        l_actual_char := l_item.attribute3;
                    WHEN 'EXPENSE_ITEM_FLAG' THEN
                        SELECT
                            COUNT(*)
                        INTO
                            l_count
                        FROM
                            ops.adre_inv_item_request_org adinitreor,
                            ops.adre_inv_item_template_rule adinitteru,
                            ops.adre_inv_item_request adinitre
                        WHERE  adinitreor.request_org_id        = p_request_org_id
                          AND  adinitre.item_request_id         = adinitreor.item_request_id
                          AND  adinitteru.item_type_id          = adinitre.item_type_id
                          AND  adinitteru.ebs_organization_id   = adinitreor.ebs_organization_id
                          AND  adinitteru.ebs_template_id       = adinitreor.ebs_template_id
                          AND  adinitteru.item_template_rule_id = p_template_rule_id
                          AND  adinitteru.expense_item_flag     = UPPER(TRIM(r.attribute_value))
                          AND  adinitteru.active_flag           = 'Y'
                          AND  adinitteru.rule_status           = 'READY'
                          AND  (adinitteru.effective_start_date IS NULL OR TRUNC(adinitteru.effective_start_date) <= TRUNC(SYSDATE))
                          AND  (adinitteru.effective_end_date   IS NULL OR TRUNC(adinitteru.effective_end_date) >= TRUNC(SYSDATE));
                        IF p_template_rule_id IS NULL OR l_count <> 1 THEN
                            CONTINUE;
                        END IF;
                        l_actual_char := r.attribute_value;
                    ELSE
                        CONTINUE;
                END CASE;
            ELSE
                raise_application_error
                (
                    -20130,
                    'Unsupported attribute verification phase.'
                );
            END IF;
            IF NOT l_numeric AND l_expected_char IS NULL THEN
                CONTINUE;
            END IF;
            IF l_numeric THEN
                IF l_expected_number IS NULL OR l_actual_number IS NULL
                    OR ABS(l_actual_number - l_expected_number) > 0.000001
                THEN
                    raise_application_error
                    (
                        -20135,
                        'EBS numeric postcondition failed: ' || r.attribute_code || ', REQUEST_ORG_ID=' || p_request_org_id || ', EXPECTED=' || l_expected_number || ', ACTUAL=' || l_actual_number
                    );
                END IF;
            ELSIF (l_actual_char <> l_expected_char)
                OR (l_actual_char IS NULL AND l_expected_char IS NOT NULL)
                OR (l_actual_char IS NOT NULL AND l_expected_char IS NULL)
            THEN
                raise_application_error
                (
                    -20140,
                    'EBS text postcondition failed: ' || r.attribute_code || ', REQUEST_ORG_ID=' || p_request_org_id
                );
            END IF;
            UPDATE
                ops.adre_inv_item_attr_value
            SET
                value_status = 'PROCESSED',
                api_return_status = c_return_success,
                api_message_count = 0,
                api_message_text = TO_CLOB('Applied and verified: ' || r.attribute_code),
                api_processed_date = SYSDATE
            WHERE  item_attr_value_id = r.item_attr_value_id
              AND  value_status       = 'READY';
        END LOOP;
        IF p_phase = 'TARGET' AND p_construction IS NOT NULL
                AND (l_item.attribute3 IS NULL OR l_item.attribute3 <> p_construction)
        THEN
            raise_application_error
            (
                -20145,
                'Derived Construction postcondition failed. REQUEST_ORG_ID=' || p_request_org_id
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_VERIFY_ATTRIBUTES',
                SQLERRM
            );
            raise_application_error
            (
                -20150,
                'Unexpected Error in pcd_verify_attributes: ' || SQLERRM,
                TRUE
            );
    END pcd_verify_attributes;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_get_org_code
    -- Purpose    : Look up the EBS organization code for a numeric organization identifier.
    -- Parameters:
    --   p_organization_id IN NUMBER - EBS organization identifier to inspect or update.
    -- Returns   : VARCHAR2 - EBS organization code.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_get_org_code
    (
        p_organization_id IN NUMBER
    )
    RETURN VARCHAR2
    IS
        l_organization_code VARCHAR2(30);
    BEGIN
        SELECT
            organization_code
        INTO
            l_organization_code
        FROM
            apps.mtl_parameters
        WHERE  organization_id = p_organization_id;
        RETURN l_organization_code;
    EXCEPTION
        WHEN no_data_found THEN
            raise_application_error
            (
                -20155,
                'Oracle EBS Inventory Organization was not found. ' ||
                'ORGANIZATION_ID=' || p_organization_id
            );
        WHEN OTHERS THEN
            raise_application_error
            (
                -20160,
                'Unexpected Error in fnc_get_org_code: ' || SQLERRM,
                TRUE
            );
    END fnc_get_org_code;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_item_exists
    -- Purpose    : Find an item in an EBS organization and return its identifier and item status.
    -- Parameters:
    --   p_item_number IN VARCHAR2 - Item number to locate in the EBS organization.
    --   p_organization_id IN NUMBER - EBS organization identifier to inspect or update.
    --   x_inventory_item_id OUT NUMBER - EBS inventory item identifier found, or NULL if absent.
    --   x_item_status_code OUT VARCHAR2 - EBS item status found, or NULL if absent.
    -- Returns   : BOOLEAN - TRUE if the item exists in the organization; otherwise FALSE.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_item_exists
    (
        p_item_number IN VARCHAR2,
        p_organization_id IN NUMBER,
        x_inventory_item_id OUT NUMBER,
        x_item_status_code OUT VARCHAR2
    )
    RETURN BOOLEAN
    IS
    BEGIN
        SELECT
            mtsyitkf.inventory_item_id,
            mtsyitb.inventory_item_status_code
        INTO
            x_inventory_item_id,
            x_item_status_code
        FROM
            apps.mtl_system_items_kfv mtsyitkf,
            apps.mtl_system_items_b mtsyitb
        WHERE  mtsyitb.inventory_item_id                   = mtsyitkf.inventory_item_id
          AND  mtsyitb.organization_id                     = mtsyitkf.organization_id
          AND  UPPER(TRIM(mtsyitkf.concatenated_segments)) = UPPER(TRIM(p_item_number))
          AND  mtsyitkf.organization_id                    = p_organization_id
          AND  ROWNUM                                      = 1;
        RETURN TRUE;
    EXCEPTION
        WHEN no_data_found THEN
            x_inventory_item_id := NULL;
            x_item_status_code := NULL;
            RETURN FALSE;
        WHEN OTHERS THEN
            raise_application_error
            (
                -20165,
                'Unexpected Error in fnc_item_exists: ' || SQLERRM,
                TRUE
            );
    END fnc_item_exists;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_validate_attribute_inputs
    -- Purpose    : Validate the configured staged attribute values for the item request.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_validate_attribute_inputs
    (
        p_item_request_id IN NUMBER
    )
    IS
        l_count            NUMBER;
        l_validated_number NUMBER;
        l_validated_date   DATE;
    BEGIN
        FOR r_lock IN
        (
            SELECT
                adinitatva.item_attr_value_id
            FROM
                ops.adre_inv_item_attr_value adinitatva,
                ops.adre_inv_item_request_org adinitreor
            WHERE  adinitreor.item_request_id = p_item_request_id
              AND  adinitatva.request_org_id  = adinitreor.request_org_id FOR UPDATE OF adinitatva.value_status NOWAIT
        )
        LOOP
            NULL;
        END LOOP;
        FOR r IN
        (
            SELECT
                av.request_org_id,
                av.item_attribute_id,
                av.attribute_value,
                adinitat.attribute_code,
                adinitat.attribute_data_type
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat,
                ops.adre_inv_item_request_org adinitreor
            WHERE  adinitreor.item_request_id = p_item_request_id
              AND  av.request_org_id          = adinitreor.request_org_id
              AND  adinitat.item_attribute_id = av.item_attribute_id
        )
        LOOP
            IF r.attribute_value IS NOT NULL THEN
                IF r.attribute_data_type = 'NUMBER' THEN
                    BEGIN
                        l_validated_number := TO_NUMBER
                        (
                            r.attribute_value,
                            c_number_format,
                            'NLS_NUMERIC_CHARACTERS=''.,'''
                        );
                    EXCEPTION
                        WHEN OTHERS THEN
                            raise_application_error
                            (
                                -20170,
                                'Unexpected Error: Invalid NUMBER for ' || r.attribute_code || ': ' || SQLERRM,
                                TRUE
                            );
                    END;
                ELSIF r.attribute_data_type = 'DATE' THEN
                    BEGIN
                        l_validated_date := TO_DATE
                        (
                            r.attribute_value,
                            'FXYYYY-MM-DD"T"HH24:MI:SS'
                        );
                    EXCEPTION
                        WHEN OTHERS THEN
                            raise_application_error
                            (
                                -20175,
                                'Unexpected Error: Invalid DATE for ' || r.attribute_code || ': ' || SQLERRM,
                                TRUE
                            );
                    END;
                ELSIF r.attribute_data_type = 'YES_NO' THEN
                    IF r.attribute_value NOT IN ('Y', 'N') THEN
                        raise_application_error
                        (
                            -20180,
                            'YES_NO attribute requires Y or N: ' || r.attribute_code
                        );
                    END IF;
                ELSIF NVL(r.attribute_data_type, '?') <> 'CHAR' THEN
                    raise_application_error
                    (
                        -20185,
                        'Unsupported attribute data type: ' || r.attribute_code
                    );
                END IF;
            END IF;
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                ops.adre_inv_item_type_attr adinittyat,
                ops.adre_inv_item_request_org adinitreor,
                ops.adre_inv_item_request adinitre
            WHERE  adinitreor.request_org_id     = r.request_org_id
              AND  adinitre.item_request_id      = adinitreor.item_request_id
              AND  adinittyat.item_type_id       = adinitre.item_type_id
              AND  adinittyat.item_attribute_id  = r.item_attribute_id
              AND  adinittyat.active_flag        = 'Y'
              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH');
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20190,
                    'Ambiguous active attribute configuration: ' || r.attribute_code
                );
            END IF;
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat
            WHERE  av.request_org_id          = r.request_org_id
              AND  adinitat.item_attribute_id = av.item_attribute_id
              AND  adinitat.attribute_code    = r.attribute_code;
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20195,
                    'Duplicate eligible attribute: ' || r.attribute_code || ', REQUEST_ORG_ID=' || r.request_org_id
                );
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_VALIDATE_ATTRIBUTE_INPUTS',
                SQLERRM
            );
            raise_application_error
            (
                -20200,
                'Unexpected Error in pcd_validate_attribute_inputs: ' || SQLERRM,
                TRUE
            );
    END pcd_validate_attribute_inputs;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_category_role_id
    -- Purpose    : Resolve the active EBS category set configured for the master
    --              organization and validate its EBS control level.
    -- Parameters:
    --   p_role_code IN VARCHAR2 - Name of the category set used by template rules.
    --   p_master_organization_id IN NUMBER - EBS master organization identifier.
    -- Returns   : NUMBER - Configured EBS category set identifier.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_category_role_id
    (
        p_role_code IN VARCHAR2,
        p_master_organization_id IN NUMBER
    )
    RETURN NUMBER
    IS
        l_id    NUMBER;
        l_count NUMBER;
    BEGIN
        SELECT casetvl.category_set_id
          INTO l_id
          FROM ops.adre_inv_item_org_cat_set orcaset,
               apps.mtl_category_sets_vl casetvl
         WHERE orcaset.ebs_organization_id            = p_master_organization_id
           AND orcaset.active_flag                    = 'Y'
           AND casetvl.category_set_id                = orcaset.ebs_category_set_id
           AND UPPER(TRIM(casetvl.category_set_name)) = UPPER(TRIM(p_role_code));
        SELECT COUNT(*)
          INTO l_count
          FROM apps.mtl_category_sets_b mtcaseb
         WHERE mtcaseb.category_set_id = l_id
           AND mtcaseb.control_level   = c_category_control_item;
        IF l_count <> 1 THEN
            raise_application_error
            (
                -20205,
                'Invalid master-level EBS Category Set configured for ' || p_role_code ||
                ', ORGANIZATION_ID=' || p_master_organization_id
            );
        END IF;
        RETURN l_id;
    EXCEPTION
        WHEN no_data_found THEN
            raise_application_error
            (
                -20210,
                'Missing active OPS master Category Set configuration: ' || p_role_code ||
                ', ORGANIZATION_ID=' || p_master_organization_id
            );
        WHEN too_many_rows THEN
            raise_application_error
            (
                -20215,
                'Ambiguous active OPS master Category Set configuration: ' || p_role_code ||
                ', ORGANIZATION_ID=' || p_master_organization_id
            );
        WHEN OTHERS THEN
            raise_application_error
            (
                -20220,
                'Unexpected Error in fnc_category_role_id: ' || SQLERRM,
                TRUE
            );
    END fnc_category_role_id;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_validate_template_categories
    -- Purpose    : Check that staged division and business unit categories support target template
    --              selection.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_target_organization_id IN NUMBER - Target EBS organization for rule and category
    --     validation.
    --   p_division_set_id IN NUMBER - Configured Division category set identifier.
    --   p_business_set_id IN NUMBER - Configured Business Unit category set identifier.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_validate_template_categories
    (
        p_item_request_id IN NUMBER,
        p_target_organization_id IN NUMBER,
        p_division_set_id IN NUMBER,
        p_business_set_id IN NUMBER
    )
    IS
        l_master_organization_id NUMBER;
        l_count                  NUMBER;
    BEGIN
        IF p_division_set_id = p_business_set_id THEN
            raise_application_error
            (
                -20225,
                'DIVISION and BUSINESS UNIT cannot resolve to the same Category Set.'
            );
        END IF;
        SELECT
            master_organization_id
        INTO
            l_master_organization_id
        FROM
            apps.mtl_parameters
        WHERE  organization_id = p_target_organization_id;
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            ops.adre_inv_item_request_org adinitreor
        WHERE  adinitreor.item_request_id     = p_item_request_id
          AND  adinitreor.organization_role   = 'MASTER'
          AND  adinitreor.ebs_organization_id = l_master_organization_id;
        IF l_count <> 1 THEN
            raise_application_error
            (
                -20230,
                'Request MASTER does not match the EBS TARGET master organization.'
            );
        END IF;
        FOR r IN
        (
            SELECT
                adinitca.request_org_id,
                adinitca.ebs_category_set_id,
                adinitca.ebs_category_id,
                adinitca.category_value,
                mtcaseb.structure_id
            FROM
                ops.adre_inv_item_category adinitca,
                ops.adre_inv_item_request_org adinitreor,
                apps.mtl_category_sets_b mtcaseb
            WHERE  adinitreor.item_request_id     = p_item_request_id
              AND  adinitreor.request_org_id      = adinitca.request_org_id
              AND  adinitca.assignment_status     = 'READY'
              AND  adinitca.ebs_category_set_id   IN (p_division_set_id, p_business_set_id)
              AND  mtcaseb.category_set_id        = adinitca.ebs_category_set_id
              AND  ((mtcaseb.control_level        = c_category_control_item
              AND  adinitreor.organization_role   = 'MASTER'
              AND  adinitreor.ebs_organization_id = l_master_organization_id)
                    OR (mtcaseb.control_level     = c_category_control_org
              AND  adinitreor.organization_role   = 'TARGET'
              AND  adinitreor.ebs_organization_id = p_target_organization_id))
        )
        LOOP
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                apps.mtl_categories_kfv mtcakf
            WHERE  mtcakf.category_id                        = r.ebs_category_id
              AND  mtcakf.structure_id                       = r.structure_id
              AND  mtcakf.enabled_flag                       = 'Y'
              AND  (mtcakf.disable_date                      IS NULL OR mtcakf.disable_date > SYSDATE)
              AND  UPPER(TRIM(mtcakf.concatenated_segments)) = UPPER(TRIM(r.category_value));
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20235,
                    'Invalid template category ID, structure or value. CATEGORY_SET_ID=' || r.ebs_category_set_id || ', REQUEST_ORG_ID=' || r.request_org_id
                );
            END IF;
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                ops.adre_inv_item_category adinitca
            WHERE  adinitca.request_org_id      = r.request_org_id
              AND  adinitca.ebs_category_set_id = r.ebs_category_set_id
              AND  adinitca.assignment_status   = 'READY';
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20240,
                    'Duplicate READY template category. CATEGORY_SET_ID=' || r.ebs_category_set_id
                );
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_VALIDATE_TEMPLATE_CATEGORIES',
                SQLERRM
            );
            raise_application_error
            (
                -20245,
                'Unexpected Error in pcd_validate_template_categories: ' || SQLERRM,
                TRUE
            );
    END pcd_validate_template_categories;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_resolve_target_template_rule
    -- Purpose    : Select the winning configured target template rule for the request and
    --              organization.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_item_type_id IN NUMBER - OPS item type identifier used to resolve EBS configuration.
    --   p_target_organization_id IN NUMBER - Target EBS organization for rule and category
    --     validation.
    --   x_item_template_rule_id OUT NUMBER - Identifier of the winning OPS template rule.
    --   x_ebs_template_id OUT NUMBER - EBS template identifier selected by that rule.
    --   x_template_name OUT VARCHAR2 - EBS template name selected by that rule.
    --   x_rule_priority OUT NUMBER - Priority of the selected template rule.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_resolve_target_template_rule
    (
        p_item_request_id IN NUMBER,
        p_item_type_id IN NUMBER,
        p_target_organization_id IN NUMBER,
        x_item_template_rule_id OUT NUMBER,
        x_ebs_template_id OUT NUMBER,
        x_template_name OUT VARCHAR2,
        x_rule_priority OUT NUMBER
    )
    IS
        l_division_set_id        NUMBER;
        l_business_set_id        NUMBER;
        l_master_organization_id NUMBER;
        l_priority_match_count   NUMBER;
    BEGIN
        SELECT master_organization_id
          INTO l_master_organization_id
          FROM apps.mtl_parameters
         WHERE organization_id = p_target_organization_id;
        l_division_set_id := fnc_category_role_id('DIVISION', l_master_organization_id);
        l_business_set_id := fnc_category_role_id('BUSINESS UNIT', l_master_organization_id);
        pcd_validate_template_categories
        (
            p_item_request_id,
            p_target_organization_id,
            l_division_set_id,
            l_business_set_id
        );
        SELECT
            ranked_template_rules.item_template_rule_id,
            ranked_template_rules.ebs_template_id,
            ranked_template_rules.template_name,
            ranked_template_rules.rule_priority,
            ranked_template_rules.priority_match_count
        INTO
            x_item_template_rule_id,
            x_ebs_template_id,
            x_template_name,
            x_rule_priority,
            l_priority_match_count
        FROM
            (
                SELECT
                    adinitteru.item_template_rule_id,
                    adinitteru.ebs_template_id,
                    mtittevl.template_name,
                    adinitteru.rule_priority,
                    ROW_NUMBER() OVER (ORDER BY NVL(adinitteru.rule_priority, 999999999), adinitteru.item_template_rule_id) AS rule_row_number,
                    COUNT(*) OVER (PARTITION BY NVL(adinitteru.rule_priority, 999999999)) AS priority_match_count
                FROM
                    ops.adre_inv_item_template_rule adinitteru,
                    apps.mtl_item_templates_vl mtittevl
                WHERE  mtittevl.template_id                              = adinitteru.ebs_template_id
                  AND  adinitteru.item_type_id                           = p_item_type_id
                  AND  adinitteru.ebs_organization_id                    = p_target_organization_id
                  AND  UPPER(TRIM(NVL(adinitteru.rule_status, 'READY'))) = 'READY'
                  AND  NVL(adinitteru.active_flag, 'N')                  = 'Y'
                  AND  (adinitteru.effective_start_date                  IS NULL
                        OR TRUNC(adinitteru.effective_start_date)        <= TRUNC(SYSDATE))
                  AND  (adinitteru.effective_end_date                    IS NULL
                        OR TRUNC(adinitteru.effective_end_date)          >= TRUNC(SYSDATE))
                  AND  (adinitteru.division_value                        IS NULL
                        OR EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_category adinitca,
                            ops.adre_inv_item_request_org adinitreor,
                            apps.mtl_category_sets_b mtcaseb,
                            apps.mtl_categories_kfv mtcakf
                        WHERE  adinitreor.request_org_id                 = adinitca.request_org_id
                          AND  adinitreor.item_request_id                = p_item_request_id
                          AND  adinitca.assignment_status                = 'READY'
                          AND  adinitca.ebs_category_set_id              = l_division_set_id
                          AND  mtcaseb.category_set_id                   = adinitca.ebs_category_set_id
                          AND  mtcakf.category_id                        = adinitca.ebs_category_id
                          AND  mtcakf.structure_id                       = mtcaseb.structure_id
                          AND  mtcakf.enabled_flag                       = 'Y'
                          AND  (mtcakf.disable_date                      IS NULL OR mtcakf.disable_date > SYSDATE)
                          AND  ((mtcaseb.control_level                   = c_category_control_item
                          AND  adinitreor.organization_role              = 'MASTER'
                          AND  adinitreor.ebs_organization_id            = l_master_organization_id)
                                OR (mtcaseb.control_level                = c_category_control_org
                          AND  adinitreor.organization_role              = 'TARGET'
                          AND  adinitreor.ebs_organization_id            = p_target_organization_id))
                          AND  UPPER(TRIM(mtcakf.concatenated_segments)) = UPPER(TRIM(adinitca.category_value))
                          AND  UPPER(TRIM(adinitca.category_value))      = UPPER(TRIM(adinitteru.division_value))
                    )
                    ) AND (adinitteru.business_unit_value IS NULL OR EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_category adinitca,
                            ops.adre_inv_item_request_org adinitreor,
                            apps.mtl_category_sets_b mtcaseb,
                            apps.mtl_categories_kfv mtcakf
                        WHERE  adinitreor.request_org_id                 = adinitca.request_org_id
                          AND  adinitreor.item_request_id                = p_item_request_id
                          AND  adinitca.assignment_status                = 'READY'
                          AND  adinitca.ebs_category_set_id              = l_business_set_id
                          AND  mtcaseb.category_set_id                   = adinitca.ebs_category_set_id
                          AND  mtcakf.category_id                        = adinitca.ebs_category_id
                          AND  mtcakf.structure_id                       = mtcaseb.structure_id
                          AND  mtcakf.enabled_flag                       = 'Y'
                          AND  (mtcakf.disable_date                      IS NULL OR mtcakf.disable_date > SYSDATE)
                          AND  ((mtcaseb.control_level                   = c_category_control_item
                          AND  adinitreor.organization_role              = 'MASTER'
                          AND  adinitreor.ebs_organization_id            = l_master_organization_id)
                                OR (mtcaseb.control_level                = c_category_control_org
                          AND  adinitreor.organization_role              = 'TARGET'
                          AND  adinitreor.ebs_organization_id            = p_target_organization_id))
                          AND  UPPER(TRIM(mtcakf.concatenated_segments)) = UPPER(TRIM(adinitca.category_value))
                          AND  UPPER(TRIM(adinitca.category_value))      = UPPER(TRIM(adinitteru.business_unit_value))
                    )
                    ) AND (adinitteru.expense_item_flag IS NULL OR EXISTS
                    (
                        SELECT
                            1
                        FROM
                            (
                                SELECT
                                    adinitatva.*
                                FROM
                                    ops.adre_inv_item_attr_value adinitatva,
                                    ops.adre_inv_item_request_org adinitreor,
                                    ops.adre_inv_item_request adinitre,
                                    ops.adre_inv_item_type adinitty,
                                    ops.adre_inv_item_attribute adinitat
                                WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                                  AND  adinitre.item_request_id    = adinitreor.item_request_id
                                  AND  adinitty.item_type_id       = adinitre.item_type_id
                                  AND  adinitty.active_flag        = 'Y'
                                  AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                                  AND  adinitat.active_flag        = 'Y'
                                  AND  (adinitatva.value_status    = 'READY'
                                        OR (g_text_correction_flag = 'Y'
                                  AND  adinitatva.value_status     = 'PROCESSED'
                                  AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                                  AND  EXISTS
                                    (
                                        SELECT
                                            1
                                        FROM
                                            ops.adre_inv_item_type_attr adinittyat
                                        WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                                          AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                                          AND  adinittyat.active_flag        = 'Y'
                                          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                                    )
                            )
                            av,
                            ops.adre_inv_item_request_org adinitreor,
                            ops.adre_inv_item_attribute adinitat
                        WHERE  adinitreor.request_org_id            = av.request_org_id
                          AND  adinitat.item_attribute_id           = av.item_attribute_id
                          AND  adinitreor.item_request_id           = p_item_request_id
                          AND  adinitreor.organization_role         = 'TARGET'
                          AND  adinitreor.ebs_organization_id       = p_target_organization_id
                          AND  adinitat.attribute_code              = 'EXPENSE_ITEM_FLAG'
                          AND  UPPER(TRIM(av.attribute_value)) = UPPER(TRIM(adinitteru.expense_item_flag))
                    )
                    )
            )
            ranked_template_rules
        WHERE  ranked_template_rules.rule_row_number = 1;
        IF l_priority_match_count > 1 THEN
            raise_application_error
            (
                -20250,
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
            raise_application_error
            (
                -20255,
                'The resolved TARGET Template Rule does not contain EBS_TEMPLATE_ID. ' ||
                'ITEM_TEMPLATE_RULE_ID=' ||
                x_item_template_rule_id
            );
        END IF;
    EXCEPTION
        WHEN no_data_found THEN
            raise_application_error
            (
                -20260,
                'No active TARGET Template Rule matched the Item Request. ' ||
                'ITEM_REQUEST_ID=' ||
                p_item_request_id ||
                ', ITEM_TYPE_ID=' ||
                p_item_type_id ||
                ', TARGET_ORGANIZATION_ID=' ||
                p_target_organization_id
            );
        WHEN OTHERS THEN
            raise_application_error
            (
                -20265,
                'Unexpected Error in pcd_resolve_target_template_rule: ' || SQLERRM,
                TRUE
            );
    END pcd_resolve_target_template_rule;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_apply_auto_planner
    -- Purpose    : Resolve an eligible planner rule and stage the planner attribute for the
    --              request.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   io_message IN OUT NOCOPY CLOB - Accumulated processing details updated by this routine.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_apply_auto_planner
    (
        p_item_request_id IN NUMBER,
        io_message IN OUT NOCOPY CLOB
    )
    IS
        l_item_type_id     NUMBER;
        l_item_prefix      VARCHAR2(100);
        l_count            NUMBER;
        l_attribute_id     NUMBER;
        l_auto_flag        VARCHAR2(1);
        l_row_id           NUMBER;
        l_status           VARCHAR2(30);
        l_input            VARCHAR2(4000);
        l_business_planner VARCHAR2(30);
        l_resolved_code    apps.mtl_planners.planner_code%TYPE;
        l_actor            VARCHAR2(100);
        l_evaluation_date  DATE := SYSDATE;
    BEGIN
        SELECT
            adinitre.item_type_id,
            UPPER(TRIM(REGEXP_SUBSTR(adinitre.item_number, '^[^-]+')))
        INTO
            l_item_type_id,
            l_item_prefix
        FROM
            ops.adre_inv_item_request adinitre
        WHERE  adinitre.item_request_id = p_item_request_id;
        SELECT
            COUNT(*),
            MIN(adinitat.item_attribute_id),
            MIN(adinittyat.auto_derive_flag)
        INTO
            l_count,
            l_attribute_id,
            l_auto_flag
        FROM
            ops.adre_inv_item_attribute adinitat,
            ops.adre_inv_item_type_attr adinittyat
        WHERE  adinitat.item_attribute_id    = adinittyat.item_attribute_id
          AND  adinitat.attribute_code       = 'PLANNER'
          AND  adinitat.active_flag          = 'Y'
          AND  adinittyat.item_type_id       = l_item_type_id
          AND  adinittyat.active_flag        = 'Y'
          AND  adinittyat.organization_scope IN ('TARGET', 'BOTH');
        IF l_count = 0 THEN
            RETURN;
        ELSIF l_count <> 1 THEN
            raise_application_error
            (
                -20270,
                'PLANNER must have one active TARGET configuration.'
            );
        END IF;
        l_actor := fnc_get_session_user;
        FOR r_target IN
        (
            SELECT
                adinitreor.request_org_id,
                adinitreor.ebs_organization_id
            FROM
                ops.adre_inv_item_request_org adinitreor
            WHERE  adinitreor.item_request_id   = p_item_request_id
              AND  adinitreor.organization_role = 'TARGET'
        )
        LOOP
            SELECT
                COUNT(*),
                MIN(adinitatva.item_attr_value_id),
                MIN(adinitatva.value_status),
                MIN(adinitatva.attribute_value)
            INTO
                l_count,
                l_row_id,
                l_status,
                l_input
            FROM
                ops.adre_inv_item_attr_value adinitatva
            WHERE  adinitatva.request_org_id    = r_target.request_org_id
              AND  adinitatva.item_attribute_id = l_attribute_id;
            IF l_count > 1 THEN
                raise_application_error
                (
                    -20275,
                    'Duplicate staged TARGET Planner. REQUEST_ORG_ID=' || r_target.request_org_id
                );
            ELSIF l_count = 0 OR NVL(l_status, 'DRAFT') <> 'READY' THEN
                CONTINUE;
            END IF;
            IF TRIM(l_input) IS NOT NULL THEN
                SELECT
                    COUNT(*)
                INTO
                    l_count
                FROM
                    apps.mtl_planners mtlpla
                WHERE  mtlpla.organization_id = r_target.ebs_organization_id
                  AND  (mtlpla.disable_date   IS NULL OR mtlpla.disable_date > l_evaluation_date)
                  AND  mtlpla.planner_code    = TRIM(l_input);
                IF l_count <> 1 THEN
                    raise_application_error
                    (
                        -20280,
                        'Explicit Planner is not an active EBS code in TARGET. REQUEST_ORG_ID=' || r_target.request_org_id || ', PLANNER=' || l_input
                    );
                END IF;
                CONTINUE;
            END IF;
            IF NVL(l_auto_flag, 'N') <> 'Y' THEN
                CONTINUE;
            END IF;
            SELECT
                COUNT(*),
                MIN(ranked_planner_rules.planner_code)
            INTO
                l_count,
                l_business_planner
            FROM
                (
                    SELECT
                        adinitplru.planner_code,
                        DENSE_RANK() OVER (ORDER BY adinitplru.priority) AS precedence_rank
                    FROM
                        ops.adre_inv_item_planner_rule adinitplru
                    WHERE  adinitplru.item_type_id        = l_item_type_id
                      AND  adinitplru.active_flag         = 'Y'
                      AND  adinitplru.effective_from_date <= l_evaluation_date
                      AND  (adinitplru.effective_to_date  IS NULL OR l_evaluation_date < adinitplru.effective_to_date)
                      AND  (adinitplru.organization_id    IS NULL OR adinitplru.organization_id = r_target.ebs_organization_id)
                      AND  (adinitplru.item_prefix        IS NULL OR adinitplru.item_prefix = l_item_prefix)
                )
                ranked_planner_rules
            WHERE  ranked_planner_rules.precedence_rank = 1;
            IF l_count = 0 THEN
                CONTINUE;
            ELSIF l_count <> 1 THEN
                raise_application_error
                (
                    -20285,
                    'Ambiguous winning Planner rules. REQUEST_ORG_ID=' || r_target.request_org_id
                );
            END IF;
            SELECT
                COUNT(*),
                MIN(mtlpla.planner_code)
            INTO
                l_count,
                l_resolved_code
            FROM
                apps.mtl_planners mtlpla
            WHERE  mtlpla.organization_id                           = r_target.ebs_organization_id
              AND  (mtlpla.disable_date                             IS NULL OR mtlpla.disable_date > l_evaluation_date)
              AND  (UPPER(TRIM(mtlpla.planner_code))                = UPPER(TRIM(l_business_planner))
                    OR LTRIM(UPPER(TRIM(mtlpla.planner_code)), '0') = LTRIM(UPPER(TRIM(l_business_planner)), '0'));
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20290,
                    'Derived Planner does not resolve uniquely in TARGET. REQUEST_ORG_ID=' || r_target.request_org_id || ', PLANNER=' || l_business_planner
                );
            END IF;
            UPDATE ops.adre_inv_item_attr_value adinitatva
            SET attribute_value = l_resolved_code,
                value_uom_code = NULL,
                api_return_status = NULL,
                api_message_count = NULL,
                api_message_text = NULL,
                api_processed_date = NULL,
                last_updated_by = l_actor,
                last_update_date = SYSDATE
            WHERE  adinitatva.item_attr_value_id         = l_row_id
              AND  adinitatva.value_status               = 'READY'
              AND  TRIM(adinitatva.attribute_value) IS NULL;
            pcd_append_text
            (
                io_message,
                'Configured Planner resolved for TARGET ' || r_target.ebs_organization_id || ': ' || l_resolved_code
            );
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_APPLY_AUTO_PLANNER',
                SQLERRM
            );
            raise_application_error
            (
                -20295,
                'Unexpected Error in pcd_apply_auto_planner: ' || SQLERRM,
                TRUE
            );
    END pcd_apply_auto_planner;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_read_text_dff
    -- Purpose    : Read and validate staged TSR and Customer text values for an organization
    --              assignment.
    -- Parameters:
    --   p_request_org_id IN NUMBER - OPS assignment identifying the staged organization values.
    --   x_tsr OUT VARCHAR2 - Validated staged TSR text, or the missing-value marker.
    --   x_customer OUT VARCHAR2 - Validated staged Customer text, or the missing-value marker.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_read_text_dff
    (
        p_request_org_id IN NUMBER,
        x_tsr OUT VARCHAR2,
        x_customer OUT VARCHAR2
    )
    IS
        l_count         PLS_INTEGER;
        l_seen_tsr      BOOLEAN := FALSE;
        l_seen_customer BOOLEAN := FALSE;
        l_column        VARCHAR2(30);
        l_validation    VARCHAR2(1);
        l_format        VARCHAR2(1);
        l_max           NUMBER;
        l_upper         VARCHAR2(1);
        l_numeric       VARCHAR2(1);
        l_alpha         VARCHAR2(1);
        l_security      VARCHAR2(1);
        l_min_value     VARCHAR2(4000);
        l_max_value     VARCHAR2(4000);
    BEGIN
        x_tsr := c_missing_char;
        x_customer := c_missing_char;
        FOR r IN (
            SELECT
                av.*,
                adinitat.attribute_code,
                adinitat.attribute_data_type,
                adinitat.active_flag AS attribute_active,
                adinitat.ebs_attribute_name,
                adinitat.ebs_attribute_group,
                adinitre.item_type_id,
                adinitreor.organization_role
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat,
                ops.adre_inv_item_request_org adinitreor,
                ops.adre_inv_item_request adinitre
            WHERE  adinitat.item_attribute_id = av.item_attribute_id
              AND  adinitreor.request_org_id  = av.request_org_id
              AND  adinitre.item_request_id   = adinitreor.item_request_id
              AND  av.request_org_id          = p_request_org_id
              AND  adinitat.attribute_code    IN ('TSR_NUMBER', 'CUSTOMER')
            ORDER BY
                adinitat.attribute_code,
                av.item_attr_value_id
        )
        LOOP
            IF (r.attribute_code = 'TSR_NUMBER' AND l_seen_tsr)
               OR (r.attribute_code = 'CUSTOMER' AND l_seen_customer) THEN
                raise_application_error
                (
                    -20300,
                    'Duplicate text input: ' || r.attribute_code
                );
            END IF;
            IF r.attribute_code = 'TSR_NUMBER' THEN
                l_seen_tsr := TRUE;
                l_column := 'ATTRIBUTE2';
            ELSE
                l_seen_customer := TRUE;
                l_column := 'ATTRIBUTE4';
            END IF;
            IF NVL(r.attribute_active, 'N') <> 'Y'
               OR NVL(r.attribute_data_type, '?') <> 'CHAR'
               OR NVL(r.ebs_attribute_group, '?') <> 'MTL_SYSTEM_ITEMS'
               OR NVL(r.ebs_attribute_name, '?') <> l_column THEN
                raise_application_error
                (
                    -20305,
                    'Invalid catalog/mapping for ' || r.attribute_code
                );
            END IF;
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                ops.adre_inv_item_type_attr adinittyat
            WHERE  adinittyat.item_type_id       = r.item_type_id
              AND  adinittyat.item_attribute_id  = r.item_attribute_id
              AND  adinittyat.active_flag        = 'Y'
              AND  adinittyat.organization_scope IN (r.organization_role, 'BOTH');
            IF l_count <> 1 THEN
                raise_application_error
                (
                    -20310,
                    'Missing/ambiguous type and organization association: ' || r.attribute_code
                );
            END IF;
            IF r.value_uom_code IS NOT NULL THEN
                raise_application_error
                (
                    -20315,
                    'Text input must not contain a UOM: ' || r.attribute_code
                );
            END IF;
            IF r.attribute_value IS NOT NULL THEN
                IF NVL(r.value_status, 'DRAFT') NOT IN ('READY', 'PROCESSED') THEN
                    raise_application_error
                    (
                        -20320,
                        'Text input must be READY or previously PROCESSED: ' || r.attribute_code
                    );
                END IF;
                SELECT
                    fnflvase.validation_type,
                    fnflvase.format_type,
                    fnflvase.maximum_size,
                    fnflvase.uppercase_only_flag,
                    fnflvase.numeric_mode_enabled_flag,
                    fnflvase.alphanumeric_allowed_flag,
                    fnflvase.security_enabled_flag,
                    fnflvase.minimum_value,
                    fnflvase.maximum_value
                INTO
                    l_validation,
                    l_format,
                    l_max,
                    l_upper,
                    l_numeric,
                    l_alpha,
                    l_security,
                    l_min_value,
                    l_max_value
                FROM
                    apps.fnd_descr_flex_col_usage_vl fndeflcousvl,
                    apps.fnd_flex_value_sets fnflvase
                WHERE  fnflvase.flex_value_set_id                 = fndeflcousvl.flex_value_set_id
                  AND  fndeflcousvl.application_id                = g_inventory_application_id
                  AND  fndeflcousvl.descriptive_flexfield_name    = r.ebs_attribute_group
                  AND  fndeflcousvl.application_column_name       = l_column
                  AND  fndeflcousvl.descriptive_flex_context_code = 'Global Data Elements'
                  AND  fndeflcousvl.enabled_flag                  = 'Y';
                IF NVL(l_validation, '?') <> 'N' OR NVL(l_format, '?') <> 'C'
                   OR l_max IS NULL OR l_max <= 0
                   OR NVL(l_upper, '?') <> 'N' OR NVL(l_numeric, '?') <> 'N'
                   OR NVL(l_alpha, '?') <> 'Y' OR NVL(l_security, '?') <> 'N'
                   OR l_min_value IS NOT NULL OR l_max_value IS NOT NULL THEN
                    raise_application_error
                    (
                        -20325,
                        'Unsupported/changed EBS text validation: ' || r.attribute_code
                    );
                END IF;
                IF LENGTH(r.attribute_value) > l_max
                   OR LENGTHB(r.attribute_value) > l_max
                   OR INSTR(r.attribute_value, CHR(0)) > 0 THEN
                    raise_application_error
                    (
                        -20330,
                        'Text exceeds configured limit or contains a missing-value sentinel: ' || r.attribute_code
                    );
                END IF;
                IF r.attribute_code = 'TSR_NUMBER' THEN
                    x_tsr := r.attribute_value;
                ELSE
                    x_customer := r.attribute_value;
                END IF;
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_READ_TEXT_DFF',
                SQLERRM
            );
            raise_application_error
            (
                -20335,
                'Unexpected Error in pcd_read_text_dff: ' || SQLERRM,
                TRUE
            );
    END pcd_read_text_dff;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_validate_text_dff
    -- Purpose    : Validate staged TSR and Customer text flexfield inputs for the request.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_validate_text_dff
    (
        p_item_request_id IN NUMBER
    )
    IS
        l_tsr      VARCHAR2(4000);
        l_customer VARCHAR2(4000);
    BEGIN
        FOR r IN (
            SELECT
                request_org_id
            FROM
                ops.adre_inv_item_request_org
            WHERE  item_request_id = p_item_request_id
        )
        LOOP
            pcd_read_text_dff
            (
                r.request_org_id,
                l_tsr,
                l_customer
            );
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_VALIDATE_TEXT_DFF',
                SQLERRM
            );
            raise_application_error
            (
                -20340,
                'Unexpected Error in pcd_validate_text_dff: ' || SQLERRM,
                TRUE
            );
    END pcd_validate_text_dff;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_apply_text_dff
    -- Purpose    : Apply and verify staged TSR and Customer values on the EBS item flexfield.
    -- Parameters:
    --   p_request_org_id IN NUMBER - OPS assignment identifying the staged organization values.
    --   p_inventory_item_id IN NUMBER - EBS inventory item identifier to inspect or update.
    --   p_organization_id IN NUMBER - EBS organization identifier to inspect or update.
    --   io_message IN OUT NOCOPY CLOB - Accumulated processing details updated by this routine.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_apply_text_dff
    (
        p_request_org_id IN NUMBER,
        p_inventory_item_id IN NUMBER,
        p_organization_id IN NUMBER,
        io_message IN OUT NOCOPY CLOB
    )
    IS
        l_tsr      VARCHAR2(4000);
        l_customer VARCHAR2(4000);
        TYPE t_item_snapshot IS RECORD
        (
            segment1                    apps.mtl_system_items_b.segment1%TYPE,
            description                 apps.mtl_system_items_b.description%TYPE,
            primary_uom_code            apps.mtl_system_items_b.primary_uom_code%TYPE,
            inventory_item_status_code  apps.mtl_system_items_b.inventory_item_status_code%TYPE,
            item_type                   apps.mtl_system_items_b.item_type%TYPE,
            eng_item_flag               apps.mtl_system_items_b.eng_item_flag%TYPE,
            default_include_in_rollup_flag apps.mtl_system_items_b.default_include_in_rollup_flag%TYPE,
            attribute_category          apps.mtl_system_items_b.attribute_category%TYPE,
            attribute1                  apps.mtl_system_items_b.attribute1%TYPE,
            attribute2                  apps.mtl_system_items_b.attribute2%TYPE,
            attribute3                  apps.mtl_system_items_b.attribute3%TYPE,
            attribute4                  apps.mtl_system_items_b.attribute4%TYPE,
            attribute5                  apps.mtl_system_items_b.attribute5%TYPE,
            attribute6                  apps.mtl_system_items_b.attribute6%TYPE,
            attribute7                  apps.mtl_system_items_b.attribute7%TYPE,
            attribute8                  apps.mtl_system_items_b.attribute8%TYPE,
            attribute9                  apps.mtl_system_items_b.attribute9%TYPE,
            attribute10                 apps.mtl_system_items_b.attribute10%TYPE,
            attribute11                 apps.mtl_system_items_b.attribute11%TYPE,
            attribute12                 apps.mtl_system_items_b.attribute12%TYPE,
            attribute13                 apps.mtl_system_items_b.attribute13%TYPE,
            attribute14                 apps.mtl_system_items_b.attribute14%TYPE,
            attribute15                 apps.mtl_system_items_b.attribute15%TYPE,
            attribute16                 apps.mtl_system_items_b.attribute16%TYPE,
            attribute17                 apps.mtl_system_items_b.attribute17%TYPE,
            attribute18                 apps.mtl_system_items_b.attribute18%TYPE,
            shelf_life_code             apps.mtl_system_items_b.shelf_life_code%TYPE,
            shelf_life_days             apps.mtl_system_items_b.shelf_life_days%TYPE,
            full_lead_time              apps.mtl_system_items_b.full_lead_time%TYPE,
            fixed_lead_time             apps.mtl_system_items_b.fixed_lead_time%TYPE,
            variable_lead_time           apps.mtl_system_items_b.variable_lead_time%TYPE,
            unit_width                  apps.mtl_system_items_b.unit_width%TYPE,
            unit_length                 apps.mtl_system_items_b.unit_length%TYPE,
            dimension_uom_code          apps.mtl_system_items_b.dimension_uom_code%TYPE,
            planner_code                apps.mtl_system_items_b.planner_code%TYPE,
            mrp_planning_code           apps.mtl_system_items_b.mrp_planning_code%TYPE,
            shippable_item_flag         apps.mtl_system_items_b.shippable_item_flag%TYPE,
            bom_enabled_flag            apps.mtl_system_items_b.bom_enabled_flag%TYPE,
            unit_weight                 apps.mtl_system_items_b.unit_weight%TYPE,
            weight_uom_code             apps.mtl_system_items_b.weight_uom_code%TYPE,
            creation_date               apps.mtl_system_items_b.creation_date%TYPE,
            created_by                  apps.mtl_system_items_b.created_by%TYPE
        );
        l_before            t_item_snapshot;
        l_after             t_item_snapshot;
        l_expected_tsr      apps.mtl_system_items_b.attribute2%TYPE;
        l_expected_customer apps.mtl_system_items_b.attribute4%TYPE;
        l_return            VARCHAR2(1);
        l_count             NUMBER;
        l_msg               VARCHAR2(4000);
        l_out_item          NUMBER;
        l_out_org           NUMBER;
        l_details           CLOB;
        l_request_id        NUMBER;
        l_execution_id      VARCHAR2(100) := 'ADRE-DFF-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') || '-' || p_request_org_id;
    BEGIN
        pcd_read_text_dff
        (
            p_request_org_id,
            l_tsr,
            l_customer
        );
        IF l_tsr = c_missing_char
                    AND l_customer = c_missing_char
        THEN
            RETURN;
        END IF;
        SELECT
            segment1,
            description,
            primary_uom_code,
            inventory_item_status_code,
            item_type,
            eng_item_flag,
            default_include_in_rollup_flag,
            attribute_category,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            attribute16,
            attribute17,
            attribute18,
            shelf_life_code,
            shelf_life_days,
            full_lead_time,
            fixed_lead_time,
            variable_lead_time,
            unit_width,
            unit_length,
            dimension_uom_code,
            planner_code,
            mrp_planning_code,
            shippable_item_flag,
            bom_enabled_flag,
            unit_weight,
            weight_uom_code,
            creation_date,
            created_by
        INTO
            l_before
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = p_inventory_item_id
          AND  organization_id   = p_organization_id;
        l_expected_tsr := CASE WHEN l_tsr = c_missing_char THEN l_before.attribute2 ELSE l_tsr END;
        l_expected_customer := CASE WHEN l_customer = c_missing_char THEN l_before.attribute4 ELSE l_customer END;
        IF NVL(l_before.attribute2, c_missing_char) <> NVL(l_expected_tsr, c_missing_char)
           OR NVL(l_before.attribute4, c_missing_char) <> NVL(l_expected_customer, c_missing_char) THEN
            apps.ego_item_pub.process_item
            (
                p_api_version => 1.0,
                p_init_msg_list => c_api_true,
                p_commit => c_api_false,
                p_transaction_type => 'UPDATE',
                p_inventory_item_id => p_inventory_item_id,
                p_organization_id => p_organization_id,
                p_attribute2 => l_tsr,
                p_attribute4 => l_customer,
                x_inventory_item_id => l_out_item,
                x_organization_id => l_out_org,
                x_return_status => l_return,
                x_msg_count => l_count,
                x_msg_data => l_msg
            );
            IF NVL(l_return, c_return_error) <> c_return_success THEN
                l_details := fnc_get_api_messages(l_count);
                pcd_append_text
                (
                    io_message,
                    l_msg
                );
                pcd_append_text
                (
                    io_message,
                    dbms_lob.substr(l_details, 3000, 1)
                );
                raise_application_error
                (
                    -20345,
                    'EBS text DFF update failed: ' || SUBSTR(NVL(l_msg, dbms_lob.substr(l_details, 1500, 1)), 1, 1500)
                );
            END IF;
        END IF;
        SELECT
            segment1,
            description,
            primary_uom_code,
            inventory_item_status_code,
            item_type,
            eng_item_flag,
            default_include_in_rollup_flag,
            attribute_category,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            attribute16,
            attribute17,
            attribute18,
            shelf_life_code,
            shelf_life_days,
            full_lead_time,
            fixed_lead_time,
            variable_lead_time,
            unit_width,
            unit_length,
            dimension_uom_code,
            planner_code,
            mrp_planning_code,
            shippable_item_flag,
            bom_enabled_flag,
            unit_weight,
            weight_uom_code,
            creation_date,
            created_by
        INTO
            l_after
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = p_inventory_item_id
          AND  organization_id   = p_organization_id;
        IF NVL(l_after.attribute2, c_missing_char) <> NVL(l_expected_tsr, c_missing_char)
           OR NVL(l_after.attribute4, c_missing_char) <> NVL(l_expected_customer, c_missing_char) THEN
            raise_application_error
            (
                -20350,
                'TSR/Customer differ from explicit OPS inputs after EBS API.'
            );
        END IF;
        IF l_before.segment1 <> l_after.segment1
           OR (l_before.segment1 IS NULL AND l_after.segment1 IS NOT NULL)
           OR (l_before.segment1 IS NOT NULL AND l_after.segment1 IS NULL) THEN
            raise_application_error
            (
                -20355,
                'Unexpected change outside TSR/Customer: SEGMENT1'
            );
        END IF;
        IF l_before.description <> l_after.description
           OR (l_before.description IS NULL AND l_after.description IS NOT NULL)
           OR (l_before.description IS NOT NULL AND l_after.description IS NULL) THEN
            raise_application_error
            (
                -20360,
                'Unexpected change outside TSR/Customer: DESCRIPTION'
            );
        END IF;
        IF l_before.primary_uom_code <> l_after.primary_uom_code
           OR (l_before.primary_uom_code IS NULL AND l_after.primary_uom_code IS NOT NULL)
           OR (l_before.primary_uom_code IS NOT NULL AND l_after.primary_uom_code IS NULL) THEN
            raise_application_error
            (
                -20365,
                'Unexpected change outside TSR/Customer: PRIMARY_UOM_CODE'
            );
        END IF;
        IF l_before.inventory_item_status_code <> l_after.inventory_item_status_code
           OR (l_before.inventory_item_status_code IS NULL AND l_after.inventory_item_status_code IS NOT NULL)
           OR (l_before.inventory_item_status_code IS NOT NULL AND l_after.inventory_item_status_code IS NULL) THEN
            raise_application_error
            (
                -20370,
                'Unexpected change outside TSR/Customer: INVENTORY_ITEM_STATUS_CODE'
            );
        END IF;
        IF l_before.item_type <> l_after.item_type
           OR (l_before.item_type IS NULL AND l_after.item_type IS NOT NULL)
           OR (l_before.item_type IS NOT NULL AND l_after.item_type IS NULL) THEN
            raise_application_error
            (
                -20375,
                'Unexpected change outside TSR/Customer: ITEM_TYPE'
            );
        END IF;
        IF l_before.eng_item_flag <> l_after.eng_item_flag
           OR (l_before.eng_item_flag IS NULL AND l_after.eng_item_flag IS NOT NULL)
           OR (l_before.eng_item_flag IS NOT NULL AND l_after.eng_item_flag IS NULL) THEN
            raise_application_error
            (
                -20380,
                'Unexpected change outside TSR/Customer: ENG_ITEM_FLAG'
            );
        END IF;
        IF l_before.default_include_in_rollup_flag <> l_after.default_include_in_rollup_flag
           OR (l_before.default_include_in_rollup_flag IS NULL AND l_after.default_include_in_rollup_flag IS NOT NULL)
           OR (l_before.default_include_in_rollup_flag IS NOT NULL
               AND l_after.default_include_in_rollup_flag IS NULL) THEN
            raise_application_error
            (
                -20385,
                'Unexpected change outside TSR/Customer: DEFAULT_INCLUDE_IN_ROLLUP_FLAG'
            );
        END IF;
        IF l_before.attribute_category <> l_after.attribute_category
           OR (l_before.attribute_category IS NULL AND l_after.attribute_category IS NOT NULL)
           OR (l_before.attribute_category IS NOT NULL AND l_after.attribute_category IS NULL) THEN
            raise_application_error
            (
                -20390,
                'Unexpected change outside TSR/Customer: ATTRIBUTE_CATEGORY'
            );
        END IF;
        IF l_before.attribute1 <> l_after.attribute1
           OR (l_before.attribute1 IS NULL AND l_after.attribute1 IS NOT NULL)
           OR (l_before.attribute1 IS NOT NULL AND l_after.attribute1 IS NULL) THEN
            raise_application_error
            (
                -20395,
                'Unexpected change outside TSR/Customer: ATTRIBUTE1'
            );
        END IF;
        IF l_before.attribute3 <> l_after.attribute3
           OR (l_before.attribute3 IS NULL AND l_after.attribute3 IS NOT NULL)
           OR (l_before.attribute3 IS NOT NULL AND l_after.attribute3 IS NULL) THEN
            raise_application_error
            (
                -20400,
                'Unexpected change outside TSR/Customer: ATTRIBUTE3'
            );
        END IF;
        IF l_before.attribute5 <> l_after.attribute5
           OR (l_before.attribute5 IS NULL AND l_after.attribute5 IS NOT NULL)
           OR (l_before.attribute5 IS NOT NULL AND l_after.attribute5 IS NULL) THEN
            raise_application_error
            (
                -20405,
                'Unexpected change outside TSR/Customer: ATTRIBUTE5'
            );
        END IF;
        IF l_before.attribute6 <> l_after.attribute6
           OR (l_before.attribute6 IS NULL AND l_after.attribute6 IS NOT NULL)
           OR (l_before.attribute6 IS NOT NULL AND l_after.attribute6 IS NULL) THEN
            raise_application_error
            (
                -20410,
                'Unexpected change outside TSR/Customer: ATTRIBUTE6'
            );
        END IF;
        IF l_before.attribute7 <> l_after.attribute7
           OR (l_before.attribute7 IS NULL AND l_after.attribute7 IS NOT NULL)
           OR (l_before.attribute7 IS NOT NULL AND l_after.attribute7 IS NULL) THEN
            raise_application_error
            (
                -20415,
                'Unexpected change outside TSR/Customer: ATTRIBUTE7'
            );
        END IF;
        IF l_before.attribute8 <> l_after.attribute8
           OR (l_before.attribute8 IS NULL AND l_after.attribute8 IS NOT NULL)
           OR (l_before.attribute8 IS NOT NULL AND l_after.attribute8 IS NULL) THEN
            raise_application_error
            (
                -20420,
                'Unexpected change outside TSR/Customer: ATTRIBUTE8'
            );
        END IF;
        IF l_before.attribute9 <> l_after.attribute9
           OR (l_before.attribute9 IS NULL AND l_after.attribute9 IS NOT NULL)
           OR (l_before.attribute9 IS NOT NULL AND l_after.attribute9 IS NULL) THEN
            raise_application_error
            (
                -20425,
                'Unexpected change outside TSR/Customer: ATTRIBUTE9'
            );
        END IF;
        IF l_before.attribute10 <> l_after.attribute10
           OR (l_before.attribute10 IS NULL AND l_after.attribute10 IS NOT NULL)
           OR (l_before.attribute10 IS NOT NULL AND l_after.attribute10 IS NULL) THEN
            raise_application_error
            (
                -20430,
                'Unexpected change outside TSR/Customer: ATTRIBUTE10'
            );
        END IF;
        IF l_before.attribute11 <> l_after.attribute11
           OR (l_before.attribute11 IS NULL AND l_after.attribute11 IS NOT NULL)
           OR (l_before.attribute11 IS NOT NULL AND l_after.attribute11 IS NULL) THEN
            raise_application_error
            (
                -20435,
                'Unexpected change outside TSR/Customer: ATTRIBUTE11'
            );
        END IF;
        IF l_before.attribute12 <> l_after.attribute12
           OR (l_before.attribute12 IS NULL AND l_after.attribute12 IS NOT NULL)
           OR (l_before.attribute12 IS NOT NULL AND l_after.attribute12 IS NULL) THEN
            raise_application_error
            (
                -20440,
                'Unexpected change outside TSR/Customer: ATTRIBUTE12'
            );
        END IF;
        IF l_before.attribute13 <> l_after.attribute13
           OR (l_before.attribute13 IS NULL AND l_after.attribute13 IS NOT NULL)
           OR (l_before.attribute13 IS NOT NULL AND l_after.attribute13 IS NULL) THEN
            raise_application_error
            (
                -20445,
                'Unexpected change outside TSR/Customer: ATTRIBUTE13'
            );
        END IF;
        IF l_before.attribute14 <> l_after.attribute14
           OR (l_before.attribute14 IS NULL AND l_after.attribute14 IS NOT NULL)
           OR (l_before.attribute14 IS NOT NULL AND l_after.attribute14 IS NULL) THEN
            raise_application_error
            (
                -20450,
                'Unexpected change outside TSR/Customer: ATTRIBUTE14'
            );
        END IF;
        IF l_before.attribute15 <> l_after.attribute15
           OR (l_before.attribute15 IS NULL AND l_after.attribute15 IS NOT NULL)
           OR (l_before.attribute15 IS NOT NULL AND l_after.attribute15 IS NULL) THEN
            raise_application_error
            (
                -20455,
                'Unexpected change outside TSR/Customer: ATTRIBUTE15'
            );
        END IF;
        IF l_before.attribute16 <> l_after.attribute16
           OR (l_before.attribute16 IS NULL AND l_after.attribute16 IS NOT NULL)
           OR (l_before.attribute16 IS NOT NULL AND l_after.attribute16 IS NULL) THEN
            raise_application_error
            (
                -20460,
                'Unexpected change outside TSR/Customer: ATTRIBUTE16'
            );
        END IF;
        IF l_before.attribute17 <> l_after.attribute17
           OR (l_before.attribute17 IS NULL AND l_after.attribute17 IS NOT NULL)
           OR (l_before.attribute17 IS NOT NULL AND l_after.attribute17 IS NULL) THEN
            raise_application_error
            (
                -20465,
                'Unexpected change outside TSR/Customer: ATTRIBUTE17'
            );
        END IF;
        IF l_before.attribute18 <> l_after.attribute18
           OR (l_before.attribute18 IS NULL AND l_after.attribute18 IS NOT NULL)
           OR (l_before.attribute18 IS NOT NULL AND l_after.attribute18 IS NULL) THEN
            raise_application_error
            (
                -20470,
                'Unexpected change outside TSR/Customer: ATTRIBUTE18'
            );
        END IF;
        IF l_before.shelf_life_code <> l_after.shelf_life_code
           OR (l_before.shelf_life_code IS NULL AND l_after.shelf_life_code IS NOT NULL)
           OR (l_before.shelf_life_code IS NOT NULL AND l_after.shelf_life_code IS NULL) THEN
            raise_application_error
            (
                -20475,
                'Unexpected change outside TSR/Customer: SHELF_LIFE_CODE'
            );
        END IF;
        IF l_before.shelf_life_days <> l_after.shelf_life_days
           OR (l_before.shelf_life_days IS NULL AND l_after.shelf_life_days IS NOT NULL)
           OR (l_before.shelf_life_days IS NOT NULL AND l_after.shelf_life_days IS NULL) THEN
            raise_application_error
            (
                -20480,
                'Unexpected change outside TSR/Customer: SHELF_LIFE_DAYS'
            );
        END IF;
        IF l_before.full_lead_time <> l_after.full_lead_time
           OR (l_before.full_lead_time IS NULL AND l_after.full_lead_time IS NOT NULL)
           OR (l_before.full_lead_time IS NOT NULL AND l_after.full_lead_time IS NULL) THEN
            raise_application_error
            (
                -20485,
                'Unexpected change outside TSR/Customer: FULL_LEAD_TIME'
            );
        END IF;
        IF l_before.fixed_lead_time <> l_after.fixed_lead_time
           OR (l_before.fixed_lead_time IS NULL AND l_after.fixed_lead_time IS NOT NULL)
           OR (l_before.fixed_lead_time IS NOT NULL AND l_after.fixed_lead_time IS NULL) THEN
            raise_application_error
            (
                -20490,
                'Unexpected change outside TSR/Customer: FIXED_LEAD_TIME'
            );
        END IF;
        IF l_before.variable_lead_time <> l_after.variable_lead_time
           OR (l_before.variable_lead_time IS NULL AND l_after.variable_lead_time IS NOT NULL)
           OR (l_before.variable_lead_time IS NOT NULL AND l_after.variable_lead_time IS NULL) THEN
            raise_application_error
            (
                -20495,
                'Unexpected change outside TSR/Customer: VARIABLE_LEAD_TIME'
            );
        END IF;
        IF l_before.unit_width <> l_after.unit_width
           OR (l_before.unit_width IS NULL AND l_after.unit_width IS NOT NULL)
           OR (l_before.unit_width IS NOT NULL AND l_after.unit_width IS NULL) THEN
            raise_application_error
            (
                -20500,
                'Unexpected change outside TSR/Customer: UNIT_WIDTH'
            );
        END IF;
        IF l_before.unit_length <> l_after.unit_length
           OR (l_before.unit_length IS NULL AND l_after.unit_length IS NOT NULL)
           OR (l_before.unit_length IS NOT NULL AND l_after.unit_length IS NULL) THEN
            raise_application_error
            (
                -20505,
                'Unexpected change outside TSR/Customer: UNIT_LENGTH'
            );
        END IF;
        IF l_before.dimension_uom_code <> l_after.dimension_uom_code
           OR (l_before.dimension_uom_code IS NULL AND l_after.dimension_uom_code IS NOT NULL)
           OR (l_before.dimension_uom_code IS NOT NULL AND l_after.dimension_uom_code IS NULL) THEN
            raise_application_error
            (
                -20510,
                'Unexpected change outside TSR/Customer: DIMENSION_UOM_CODE'
            );
        END IF;
        IF l_before.planner_code <> l_after.planner_code
           OR (l_before.planner_code IS NULL AND l_after.planner_code IS NOT NULL)
           OR (l_before.planner_code IS NOT NULL AND l_after.planner_code IS NULL) THEN
            raise_application_error
            (
                -20515,
                'Unexpected change outside TSR/Customer: PLANNER_CODE'
            );
        END IF;
        IF l_before.mrp_planning_code <> l_after.mrp_planning_code
           OR (l_before.mrp_planning_code IS NULL AND l_after.mrp_planning_code IS NOT NULL)
           OR (l_before.mrp_planning_code IS NOT NULL AND l_after.mrp_planning_code IS NULL) THEN
            raise_application_error
            (
                -20520,
                'Unexpected change outside TSR/Customer: MRP_PLANNING_CODE'
            );
        END IF;
        IF l_before.shippable_item_flag <> l_after.shippable_item_flag
           OR (l_before.shippable_item_flag IS NULL AND l_after.shippable_item_flag IS NOT NULL)
           OR (l_before.shippable_item_flag IS NOT NULL AND l_after.shippable_item_flag IS NULL) THEN
            raise_application_error
            (
                -20525,
                'Unexpected change outside TSR/Customer: SHIPPABLE_ITEM_FLAG'
            );
        END IF;
        IF l_before.bom_enabled_flag <> l_after.bom_enabled_flag
           OR (l_before.bom_enabled_flag IS NULL AND l_after.bom_enabled_flag IS NOT NULL)
           OR (l_before.bom_enabled_flag IS NOT NULL AND l_after.bom_enabled_flag IS NULL) THEN
            raise_application_error
            (
                -20530,
                'Unexpected change outside TSR/Customer: BOM_ENABLED_FLAG'
            );
        END IF;
        IF l_before.unit_weight <> l_after.unit_weight
           OR (l_before.unit_weight IS NULL AND l_after.unit_weight IS NOT NULL)
           OR (l_before.unit_weight IS NOT NULL AND l_after.unit_weight IS NULL) THEN
            raise_application_error
            (
                -20535,
                'Unexpected change outside TSR/Customer: UNIT_WEIGHT'
            );
        END IF;
        IF l_before.weight_uom_code <> l_after.weight_uom_code
           OR (l_before.weight_uom_code IS NULL AND l_after.weight_uom_code IS NOT NULL)
           OR (l_before.weight_uom_code IS NOT NULL AND l_after.weight_uom_code IS NULL) THEN
            raise_application_error
            (
                -20540,
                'Unexpected change outside TSR/Customer: WEIGHT_UOM_CODE'
            );
        END IF;
        IF l_before.creation_date <> l_after.creation_date
           OR (l_before.creation_date IS NULL AND l_after.creation_date IS NOT NULL)
           OR (l_before.creation_date IS NOT NULL AND l_after.creation_date IS NULL) THEN
            raise_application_error
            (
                -20545,
                'Unexpected change outside TSR/Customer: CREATION_DATE'
            );
        END IF;
        IF l_before.created_by <> l_after.created_by
           OR (l_before.created_by IS NULL AND l_after.created_by IS NOT NULL)
           OR (l_before.created_by IS NOT NULL AND l_after.created_by IS NULL) THEN
            raise_application_error
            (
                -20550,
                'Unexpected change outside TSR/Customer: CREATED_BY'
            );
        END IF;
        SELECT
            item_request_id
        INTO
            l_request_id
        FROM
            ops.adre_inv_item_request_org
        WHERE  request_org_id = p_request_org_id;
        l_details := TO_CLOB('ITEM_ID=' || p_inventory_item_id || ', ORG_ID=' || p_organization_id ||
            ', TSR BEFORE=' || NVL(l_before.attribute2, 'NULL') || ', AFTER=' || NVL(l_after.attribute2, 'NULL') ||
            ', CUSTOMER BEFORE=' || NVL(l_before.attribute4, 'NULL') || ', AFTER=' || NVL(l_after.attribute4, 'NULL'));
        pcd_append_text
        (
            io_message,
            dbms_lob.substr(l_details, 3000, 1)
        );
        pcd_insert_api_log
        (
            l_execution_id,
            l_request_id,
            p_request_org_id,
            'APPLY_TEXT_DFF',
            'EGO_ITEM_PUB.PROCESS_ITEM',
            'ORGANIZATION',
            p_organization_id,
            'INFO',
            'SUCCESS',
            c_return_success,
            0,
            l_details
        );
        UPDATE ops.adre_inv_item_attr_value adinitatva
           SET value_status = 'PROCESSED',
               api_return_status = c_return_success,
               api_message_count = 0,
               api_message_text = l_details,
               api_processed_date = SYSDATE
         WHERE  adinitatva.request_org_id     = p_request_org_id
           AND  adinitatva.item_attr_value_id IN
               (
                   SELECT
                       ev.item_attr_value_id
                   FROM
                       (
                           SELECT
                               adinitatva.*
                           FROM
                               ops.adre_inv_item_attr_value adinitatva,
                               ops.adre_inv_item_request_org adinitreor,
                               ops.adre_inv_item_request adinitre,
                               ops.adre_inv_item_type adinitty,
                               ops.adre_inv_item_attribute adinitat
                           WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                             AND  adinitre.item_request_id    = adinitreor.item_request_id
                             AND  adinitty.item_type_id       = adinitre.item_type_id
                             AND  adinitty.active_flag        = 'Y'
                             AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                             AND  adinitat.active_flag        = 'Y'
                             AND  (adinitatva.value_status    = 'READY'
                                   OR (g_text_correction_flag = 'Y'
                             AND  adinitatva.value_status     = 'PROCESSED'
                             AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                             AND  EXISTS
                               (
                                   SELECT
                                       1
                                   FROM
                                       ops.adre_inv_item_type_attr adinittyat
                                   WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                                     AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                                     AND  adinittyat.active_flag        = 'Y'
                                     AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                               )
                       )
                       ev
                   WHERE  ev.request_org_id = p_request_org_id
               )
           AND  adinitatva.attribute_value IS NOT NULL
           AND  adinitatva.item_attribute_id    IN
               (
                   SELECT
                       adinitat.item_attribute_id
                   FROM
                       ops.adre_inv_item_attribute adinitat
                   WHERE  adinitat.attribute_code IN ('TSR_NUMBER', 'CUSTOMER')
               );
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_APPLY_TEXT_DFF',
                SQLERRM
            );
            raise_application_error
            (
                -20555,
                'Unexpected Error in pcd_apply_text_dff: ' || SQLERRM,
                TRUE
            );
    END pcd_apply_text_dff;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_apply_request_text_dff
    -- Purpose    : Apply TSR and Customer flexfield values to eligible assignments in the request.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   io_message IN OUT NOCOPY CLOB - Accumulated processing details updated by this routine.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_apply_request_text_dff
    (
        p_item_request_id IN NUMBER,
        io_message IN OUT NOCOPY CLOB
    )
    IS
        l_item_id NUMBER;
        l_status  VARCHAR2(30);
        l_count   PLS_INTEGER;
        l_orgs    PLS_INTEGER;
    BEGIN
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            (
                SELECT
                    adinitatva.*
                FROM
                    ops.adre_inv_item_attr_value adinitatva,
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_request adinitre,
                    ops.adre_inv_item_type adinitty,
                    ops.adre_inv_item_attribute adinitat
                WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                  AND  adinitre.item_request_id    = adinitreor.item_request_id
                  AND  adinitty.item_type_id       = adinitre.item_type_id
                  AND  adinitty.active_flag        = 'Y'
                  AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                  AND  adinitat.active_flag        = 'Y'
                  AND  (adinitatva.value_status    = 'READY'
                        OR (g_text_correction_flag = 'Y'
                  AND  adinitatva.value_status     = 'PROCESSED'
                  AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                  AND  EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_type_attr adinittyat
                        WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                          AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                          AND  adinittyat.active_flag        = 'Y'
                          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                    )
            )
            av,
            ops.adre_inv_item_attribute adinitat,
            ops.adre_inv_item_request_org adinitreor
        WHERE  adinitat.item_attribute_id = av.item_attribute_id
          AND  adinitreor.request_org_id  = av.request_org_id
          AND  adinitreor.item_request_id = p_item_request_id
          AND  adinitat.attribute_code    IN ('TSR_NUMBER', 'CUSTOMER')
          AND  av.attribute_value    IS NOT NULL;
        IF l_count = 0 THEN
            RETURN;
        END IF;
        pcd_validate_text_dff(p_item_request_id);
        SELECT
            COUNT(*),
            COUNT(DISTINCT ebs_organization_id)
        INTO
            l_orgs,
            l_count
        FROM
            ops.adre_inv_item_request_org
        WHERE  item_request_id = p_item_request_id;
        IF l_orgs = 0 OR l_count <> l_orgs THEN
            raise_application_error
            (
                -20560,
                'Missing/duplicate request organizations.'
            );
        END IF;
        FOR r IN (
            SELECT
                adinitreor.*,
                adinitre.item_number
            FROM
                ops.adre_inv_item_request_org adinitreor,
                ops.adre_inv_item_request adinitre
            WHERE  adinitre.item_request_id = adinitreor.item_request_id
              AND  adinitre.item_request_id = p_item_request_id
        )
        LOOP
            IF NVL(r.assignment_status, '?') <> c_assignment_processed
               OR NVL(r.organization_role, '?') NOT IN ('MASTER', 'TARGET') THEN
                raise_application_error
                (
                    -20565,
                    'Text DFF update requires PROCESSED MASTER/TARGET organizations.'
                );
            END IF;
            IF NOT fnc_item_exists(r.item_number, r.ebs_organization_id, l_item_id, l_status) THEN
                raise_application_error
                (
                    -20570,
                    'Request item missing in EBS organization.'
                );
            END IF;
            IF r.ebs_inventory_item_id IS NULL OR r.ebs_inventory_item_id <> l_item_id THEN
                raise_application_error
                (
                    -20575,
                    'Request EBS item ID differs from actual EBS item.'
                );
            END IF;
        END LOOP;
        FOR r IN (
            SELECT
                request_org_id,
                ebs_inventory_item_id,
                ebs_organization_id
            FROM
                ops.adre_inv_item_request_org
            WHERE  item_request_id = p_item_request_id
            ORDER BY
                CASE organization_role WHEN 'MASTER' THEN 0 ELSE 1 END,
                request_org_id
        )
        LOOP
            pcd_apply_text_dff
            (
                r.request_org_id,
                r.ebs_inventory_item_id,
                r.ebs_organization_id,
                io_message
            );
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_APPLY_REQUEST_TEXT_DFF',
                SQLERRM
            );
            raise_application_error
            (
                -20580,
                'Unexpected Error in pcd_apply_request_text_dff: ' || SQLERRM,
                TRUE
            );
    END pcd_apply_request_text_dff;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_validate_required_attributes
    -- Purpose    : Ensure each required configured attribute is staged for the applicable
    --              organization.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_validate_required_attributes
    (
        p_item_request_id IN NUMBER
    )
    IS
        l_missing_count NUMBER;
    BEGIN
        SELECT
            COUNT(*)
        INTO
            l_missing_count
        FROM
            ops.adre_inv_item_request adinitre,
            ops.adre_inv_item_type adinitty,
            ops.adre_inv_item_request_org adinitreor,
            ops.adre_inv_item_type_attr adinittyat,
            ops.adre_inv_item_attribute adinitat
        WHERE  adinitre.item_request_id      = p_item_request_id
          AND  adinitty.item_type_id         = adinitre.item_type_id
          AND  adinitty.active_flag          = 'Y'
          AND  adinitreor.item_request_id    = adinitre.item_request_id
          AND  adinittyat.item_type_id       = adinitre.item_type_id
          AND  adinittyat.active_flag        = 'Y'
          AND  adinittyat.required_flag      = 'Y'
          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
          AND  adinitat.item_attribute_id    = adinittyat.item_attribute_id
          AND  adinitat.active_flag          = 'Y'
          AND  NOT EXISTS
            (
                SELECT
                    1
                FROM
                    (
                        SELECT
                            adinitatva.*
                        FROM
                            ops.adre_inv_item_attr_value adinitatva,
                            ops.adre_inv_item_request_org adinitreor,
                            ops.adre_inv_item_request adinitre,
                            ops.adre_inv_item_type adinitty,
                            ops.adre_inv_item_attribute adinitat
                        WHERE  adinitreor.request_org_id        = adinitatva.request_org_id
                          AND  adinitre.item_request_id         = adinitreor.item_request_id
                          AND  adinitty.item_type_id            = adinitre.item_type_id
                          AND  adinitty.active_flag             = 'Y'
                          AND  adinitat.item_attribute_id       = adinitatva.item_attribute_id
                          AND  adinitat.active_flag             = 'Y'
                          AND  (adinitatva.value_status         = 'READY'
                                OR (g_text_correction_flag      = 'Y'
                          AND  adinitatva.value_status          = 'PROCESSED'
                          AND  adinitat.attribute_code          IN ('TSR_NUMBER', 'CUSTOMER'))
                                OR (adinitatva.value_status     = 'PROCESSED'
                          AND  adinitat.attribute_code          = 'ENGINEERING_ITEM_FLAG'
                          AND  adinitreor.organization_role     = 'MASTER'
                          AND  adinitreor.assignment_status     = c_assignment_processed
                          AND  adinitreor.ebs_inventory_item_id IS NOT NULL
                          AND  EXISTS
                               (
                                   SELECT 1
                                     FROM apps.mtl_system_items_b mtsyitb
                                    WHERE  mtsyitb.inventory_item_id =
                                           adinitreor.ebs_inventory_item_id
                                      AND  mtsyitb.organization_id =
                                           adinitreor.ebs_organization_id
                                      AND  UPPER(TRIM(mtsyitb.eng_item_flag)) =
                                           UPPER(TRIM(adinitatva.attribute_value))
                               )))
                          AND  EXISTS
                            (
                                SELECT
                                    1
                                FROM
                                    ops.adre_inv_item_type_attr adinittyat
                                WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                                  AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                                  AND  adinittyat.active_flag        = 'Y'
                                  AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                            )
                    )
                    av
                WHERE  av.request_org_id             = adinitreor.request_org_id
                  AND  av.item_attribute_id          = adinittyat.item_attribute_id
                  AND  av.attribute_value IS NOT NULL
            );
        IF l_missing_count > 0 THEN
            raise_application_error
            (
                -20585,
                'Required application attributes are missing or not READY. COUNT=' || l_missing_count
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_VALIDATE_REQUIRED_ATTRIBUTES',
                SQLERRM
            );
            raise_application_error
            (
                -20590,
                'Unexpected Error in pcd_validate_required_attributes: ' || SQLERRM,
                TRUE
            );
    END pcd_validate_required_attributes;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_assign_categories
    -- Purpose    : Validate and assign staged categories to the corresponding EBS items and
    --              organizations.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_user_id IN NUMBER - EBS user identifier; NULL invokes the existing context fallback.
    --   p_resp_id IN NUMBER - EBS responsibility identifier; NULL invokes the existing context
    --     fallback.
    --   p_resp_appl_id IN NUMBER - EBS responsibility application identifier; NULL uses the
    --     existing fallback.
    --   p_commit_flag IN VARCHAR2 - Controls whether the routine commits successful changes.
    --   x_return_status OUT VARCHAR2 - Success, error or unexpected status returned to the caller.
    --   x_message OUT CLOB - Detailed result or diagnostic text returned to the caller.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_assign_categories
    (
        p_item_request_id IN NUMBER,
        p_user_id IN NUMBER DEFAULT NULL,
        p_resp_id IN NUMBER DEFAULT NULL,
        p_resp_appl_id IN NUMBER DEFAULT NULL,
        p_commit_flag IN VARCHAR2 DEFAULT 'N',
        x_return_status OUT VARCHAR2,
        x_message OUT CLOB
    )
    IS
        l_context_user_id      NUMBER;
        l_context_resp_id      NUMBER;
        l_context_resp_appl_id NUMBER;
        l_inventory_item_id    NUMBER;
        l_item_status_code     VARCHAR2(30);
        l_existing_category_id NUMBER;
        l_category_exists      NUMBER;
        l_category_set_exists  NUMBER;
        l_return_status        VARCHAR2(1);
        l_error_code           NUMBER;
        l_msg_count            NUMBER;
        l_msg_data             VARCHAR2(4000);
        l_api_message          CLOB;
        l_error_text           VARCHAR2(4000);
        l_success_count        NUMBER := 0;
        l_error_count          NUMBER := 0;
        l_skipped_count        NUMBER := 0;
        l_commit_flag          VARCHAR2(1);
        CURSOR c_categories
        IS
            SELECT
                adinitca.item_category_id,
                adinitca.request_org_id,
                adinitca.ebs_category_set_id,
                adinitca.ebs_category_id,
                adinitca.category_value,
                adinitca.assignment_status,
                adinitreor.ebs_organization_id,
                adinitreor.organization_role,
                adinitreor.ebs_inventory_item_id,
                adinitre.item_number,
                mtcaseb.control_level
            FROM
                ops.adre_inv_item_category adinitca,
                ops.adre_inv_item_request_org adinitreor,
                ops.adre_inv_item_request adinitre,
                apps.mtl_category_sets_b mtcaseb
            WHERE  adinitreor.request_org_id    = adinitca.request_org_id
              AND  adinitre.item_request_id     = adinitreor.item_request_id
              AND  mtcaseb.category_set_id(+)   = adinitca.ebs_category_set_id
              AND  adinitre.item_request_id     = p_item_request_id
              AND  adinitca.ebs_category_set_id IS NOT NULL
              AND  adinitca.ebs_category_id     IS NOT NULL
              AND  adinitca.assignment_status   = c_assignment_ready
            ORDER BY
                CASE adinitreor.organization_role WHEN 'MASTER' THEN 1 WHEN 'TARGET' THEN 2 ELSE 3 END,
                adinitreor.ebs_organization_id,
                adinitca.ebs_category_set_id;
    BEGIN
        g_text_correction_flag := 'N';
        x_return_status := c_return_success;
        x_message := NULL;
        dbms_lob.createtemporary
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
        l_context_user_id :=
            p_user_id;
        l_context_resp_id :=
            p_resp_id;
        l_context_resp_appl_id :=
            p_resp_appl_id;
        pcd_initialize_ebs_context
        (
            p_user_id => l_context_user_id,
            p_resp_id => l_context_resp_id,
            p_resp_appl_id => l_context_resp_appl_id
        );
        FOR r IN c_categories
        LOOP
            BEGIN
                l_inventory_item_id := r.ebs_inventory_item_id;
                l_existing_category_id := NULL;
                l_return_status := NULL;
                l_error_code := NULL;
                l_msg_count := 0;
                l_msg_data := NULL;
                l_api_message := NULL;
                IF r.control_level = c_category_control_item
                AND r.organization_role <> 'MASTER'
                THEN
                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_skipped,
                        api_return_status = c_return_success,
                        api_message_count = 0,
                        api_message_text =
                            TO_CLOB
                            (
                                'Skipped because the Category Set is item/master controlled.'
                            ),
                        api_processed_date = SYSDATE
                    WHERE  item_category_id = r.item_category_id;
                    l_skipped_count := l_skipped_count + 1;
                    CONTINUE;
                END IF;
                SELECT
                    COUNT(*)
                INTO
                    l_category_set_exists
                FROM
                    apps.mtl_category_sets_b
                WHERE  category_set_id = r.ebs_category_set_id;
                IF l_category_set_exists = 0 THEN
                    raise_application_error
                    (
                        -20595,
                        'Category Set does not exist in Oracle EBS. CATEGORY_SET_ID=' ||
                        r.ebs_category_set_id
                    );
                END IF;
                SELECT
                    COUNT(*)
                INTO
                    l_category_exists
                FROM
                    apps.mtl_categories_kfv
                WHERE  category_id = r.ebs_category_id;
                IF l_category_exists = 0 THEN
                    raise_application_error
                    (
                        -20600,
                        'Category does not exist in Oracle EBS. CATEGORY_ID=' ||
                        r.ebs_category_id
                    );
                END IF;
                IF l_inventory_item_id IS NULL THEN
                    IF NOT fnc_item_exists
                    (
                        p_item_number => r.item_number,
                        p_organization_id => r.ebs_organization_id,
                        x_inventory_item_id => l_inventory_item_id,
                        x_item_status_code => l_item_status_code
                    )
                    THEN
                        raise_application_error
                        (
                            -20605,
                            'Item does not exist in Oracle EBS for Category processing. ' ||
                            'ITEM_NUMBER=' || r.item_number ||
                            ', ORGANIZATION_ID=' || r.ebs_organization_id
                        );
                    END IF;
                END IF;
                UPDATE ops.adre_inv_item_category
                SET assignment_status = c_assignment_processing
                WHERE  item_category_id = r.item_category_id;
                BEGIN
                    SELECT
                        mtitca.category_id
                    INTO
                        l_existing_category_id
                    FROM
                        apps.mtl_item_categories mtitca
                    WHERE  mtitca.inventory_item_id = l_inventory_item_id
                      AND  mtitca.organization_id   = r.ebs_organization_id
                      AND  mtitca.category_set_id   = r.ebs_category_set_id
                      AND  ROWNUM                   = 1;
                EXCEPTION
                    WHEN no_data_found THEN
                        l_existing_category_id := NULL;
                    WHEN OTHERS THEN
                        raise_application_error
                        (
                            -20610,
                            'Unexpected Error in pcd_assign_categories: ' || SQLERRM,
                            TRUE
                        );
                END;
                IF l_existing_category_id IS NULL THEN
                    BEGIN
                        apps.fnd_msg_pub.initialize;
                    EXCEPTION
                        WHEN OTHERS THEN
                            raise_application_error
                            (
                                -20615,
                                'Unexpected Error in pcd_assign_categories: ' || SQLERRM,
                                TRUE
                            );
                    END;
                    apps.inv_item_category_pub.create_category_assignment
                    (
                        p_api_version => 1.0,
                        p_init_msg_list => c_api_true,
                        p_commit => c_api_false,
                        x_return_status => l_return_status,
                        x_errorcode => l_error_code,
                        x_msg_count => l_msg_count,
                        x_msg_data => l_msg_data,
                        p_category_id => r.ebs_category_id,
                        p_category_set_id => r.ebs_category_set_id,
                        p_inventory_item_id => l_inventory_item_id,
                        p_organization_id => r.ebs_organization_id
                    );
                    l_api_message :=
                        fnc_get_api_messages
                        (
                            l_msg_count,
                            l_msg_data
                        );
                ELSIF l_existing_category_id = r.ebs_category_id THEN
                    l_return_status := c_return_success;
                    l_msg_count := 0;
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
                            raise_application_error
                            (
                                -20620,
                                'Unexpected Error in pcd_assign_categories: ' || SQLERRM,
                                TRUE
                            );
                    END;
                    apps.inv_item_category_pub.update_category_assignment
                    (
                        p_api_version => 1.0,
                        p_init_msg_list => c_api_true,
                        p_commit => c_api_false,
                        p_category_id => r.ebs_category_id,
                        p_old_category_id => l_existing_category_id,
                        p_category_set_id => r.ebs_category_set_id,
                        p_inventory_item_id => l_inventory_item_id,
                        p_organization_id => r.ebs_organization_id,
                        x_return_status => l_return_status,
                        x_errorcode => l_error_code,
                        x_msg_count => l_msg_count,
                        x_msg_data => l_msg_data
                    );
                    l_api_message :=
                        fnc_get_api_messages
                        (
                            l_msg_count,
                            l_msg_data
                        );
                END IF;
                IF l_return_status = c_return_success THEN
                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_processed,
                        api_return_status = l_return_status,
                        api_message_count = NVL(l_msg_count, 0),
                        api_message_text = l_api_message,
                        api_processed_date = SYSDATE
                    WHERE  item_category_id = r.item_category_id;
                    l_success_count :=
                        l_success_count + 1;
                ELSE
                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_error,
                        api_return_status =
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
                        api_message_text = l_api_message,
                        api_processed_date = SYSDATE
                    WHERE  item_category_id = r.item_category_id;
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
                        dbms_utility.format_error_backtrace;
                    UPDATE ops.adre_inv_item_category
                    SET assignment_status = c_assignment_error,
                        api_return_status = c_return_unexpected,
                        api_message_count = 1,
                        api_message_text = TO_CLOB(l_error_text),
                        api_processed_date = SYSDATE
                    WHERE  item_category_id = r.item_category_id;
                    l_error_count :=
                        l_error_count + 1;
                    x_return_status :=
                        c_return_error;
                    pcd_write_log
                    (
                        'PCD_ASSIGN_CATEGORIES',
                        l_error_text
                    );
                    raise_application_error
                    (
                        -20625,
                        'Unexpected Error in pcd_assign_categories: ' || SQLERRM,
                        TRUE
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
                dbms_lob.createtemporary
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
            raise_application_error
            (
                -20630,
                'Unexpected Error in pcd_assign_categories: ' || SQLERRM,
                TRUE
            );
    END pcd_assign_categories;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_resolve_item_type
    -- Purpose    : Resolve the EBS item type from explicit configuration or consistent target
    --              templates.
    -- Parameters:
    --   p_item_type_id IN NUMBER - OPS item type identifier used to resolve EBS configuration.
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    -- Returns   : VARCHAR2 - Validated EBS item type lookup code.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_resolve_item_type
    (
        p_item_type_id IN NUMBER,
        p_item_request_id IN NUMBER DEFAULT NULL
    )
    RETURN VARCHAR2
    IS
        l_app_code      ops.adre_inv_item_type.item_type_code%TYPE;
        l_code          ops.adre_inv_item_type.ebs_item_type_code%TYPE;
        l_view_id       NUMBER;
        l_security_id   NUMBER;
        l_count         NUMBER;
        l_target_count  NUMBER := 0;
        l_template_code VARCHAR2(240);
        l_result        apps.fnd_lookup_values_vl.lookup_code%TYPE;
    BEGIN
        SELECT
            item_type_code,
            ebs_item_type_code,
            ebs_view_application_id,
            ebs_security_group_id
        INTO
            l_app_code,
            l_code,
            l_view_id,
            l_security_id
        FROM
            ops.adre_inv_item_type
        WHERE  item_type_id = p_item_type_id
          AND  active_flag  = 'Y';
        IF l_code IS NULL THEN
            IF p_item_request_id IS NULL THEN
                raise_application_error
                (
                    -20635,
                    'A request with resolved TARGET templates is required for ' || l_app_code
                );
            END IF;
            FOR r IN
            (
                SELECT
                    adinitreor.ebs_organization_id,
                    adinitreor.ebs_template_id
                FROM
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_request adinitre
                WHERE  adinitre.item_request_id     = p_item_request_id
                  AND  adinitre.item_type_id        = p_item_type_id
                  AND  adinitreor.item_request_id   = adinitre.item_request_id
                  AND  adinitreor.organization_role = 'TARGET'
            )
            LOOP
                l_target_count := l_target_count + 1;
                SELECT
                    COUNT(*),
                    MIN(TRIM(mtitteat.attribute_value))
                INTO
                    l_count,
                    l_template_code
                FROM
                    apps.mtl_item_templ_attributes mtitteat,
                    apps.mtl_item_templates mtitte
                WHERE  mtitte.template_id             = r.ebs_template_id
                  AND  mtitteat.template_id           = mtitte.template_id
                  AND  mtitteat.attribute_name        = 'MTL_SYSTEM_ITEMS.ITEM_TYPE'
                  AND  mtitteat.enabled_flag          = 'Y'
                  AND  TRIM(mtitteat.attribute_value) IS NOT NULL;
                IF l_count <> 1 THEN
                    raise_application_error
                    (
                        -20640,
                        'TARGET template must define exactly one active ITEM_TYPE. ORGANIZATION_ID=' || r.ebs_organization_id || ', TEMPLATE_ID=' || r.ebs_template_id
                    );
                END IF;
                IF l_code IS NOT NULL AND l_code <> l_template_code THEN
                    raise_application_error
                    (
                        -20645,
                        'Incompatible ITEM_TYPE values across TARGET templates: ' || l_code || ' / ' || l_template_code
                    );
                END IF;
                l_code := l_template_code;
            END LOOP;
            IF l_target_count = 0 THEN
                raise_application_error
                (
                    -20650,
                    'No TARGET templates are available to resolve ITEM_TYPE.'
                );
            END IF;
            SELECT
                fnlotyvl.view_application_id,
                fnlotyvl.security_group_id
            INTO
                l_view_id,
                l_security_id
            FROM
                apps.fnd_lookup_types_vl fnlotyvl,
                apps.fnd_application fndapp
            WHERE  fnlotyvl.lookup_type          = 'ITEM_TYPE'
              AND  fndapp.application_id         = fnlotyvl.application_id
              AND  fndapp.application_short_name = 'INV';
        ELSIF l_view_id IS NULL OR l_security_id IS NULL THEN
            raise_application_error
            (
                -20655,
                'Incomplete explicit EBS Item Type mapping for ' || l_app_code
            );
        END IF;
        SELECT
            COUNT(*),
            MIN(fnlovavl.lookup_code)
        INTO
            l_count,
            l_result
        FROM
            apps.fnd_lookup_values_vl fnlovavl,
            apps.fnd_lookup_types_vl fnlotyvl,
            apps.fnd_application fndapp
        WHERE  fnlovavl.lookup_type          = 'ITEM_TYPE'
          AND  fnlovavl.lookup_code          = l_code
          AND  fnlovavl.view_application_id  = l_view_id
          AND  fnlovavl.security_group_id    = l_security_id
          AND  fnlotyvl.lookup_type          = fnlovavl.lookup_type
          AND  fnlotyvl.view_application_id  = fnlovavl.view_application_id
          AND  fnlotyvl.security_group_id    = fnlovavl.security_group_id
          AND  fndapp.application_id         = fnlotyvl.application_id
          AND  fndapp.application_short_name = 'INV'
          AND  fnlovavl.enabled_flag         = 'Y'
          AND  (fnlovavl.start_date_active   IS NULL OR TRUNC(fnlovavl.start_date_active) <= TRUNC(SYSDATE))
          AND  (fnlovavl.end_date_active     IS NULL OR TRUNC(fnlovavl.end_date_active) >= TRUNC(SYSDATE));
        IF l_count <> 1 THEN
            raise_application_error
            (
                -20660,
                'Resolved EBS Item Type must match exactly one active lookup value: ' || l_code
            );
        END IF;
        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'F_RESOLVE_ITEM_TYPE',
                SQLERRM
            );
            raise_application_error
            (
                -20665,
                'Unexpected Error in fnc_resolve_item_type: ' || SQLERRM,
                TRUE
            );
    END fnc_resolve_item_type;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_apply_item_type
    -- Purpose    : Update the EBS item type if needed and verify the resulting item value.
    -- Parameters:
    --   p_inventory_item_id IN NUMBER - EBS inventory item identifier to inspect or update.
    --   p_organization_id IN NUMBER - EBS organization identifier to inspect or update.
    --   p_item_type IN VARCHAR2 - Resolved EBS item type code to apply to the item.
    --   x_message OUT NOCOPY CLOB - API response and before/after item type details.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_apply_item_type
    (
        p_inventory_item_id IN NUMBER,
        p_organization_id IN NUMBER,
        p_item_type IN VARCHAR2,
        x_message OUT NOCOPY CLOB
    )
    IS
        l_before      apps.mtl_system_items_b.item_type%TYPE;
        l_after       apps.mtl_system_items_b.item_type%TYPE;
        l_out_item_id NUMBER;
        l_out_org_id  NUMBER;
        l_status      VARCHAR2(1);
        l_msg_count   NUMBER;
        l_msg_data    VARCHAR2(4000);
    BEGIN
        x_message := NULL;
        IF p_item_type IS NULL THEN
            raise_application_error
            (
                -20670,
                'Resolved Item Type cannot be NULL.'
            );
        END IF;
        SELECT
            item_type
        INTO
            l_before
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = p_inventory_item_id
          AND  organization_id   = p_organization_id;
        IF l_before IS NULL OR l_before <> p_item_type THEN
            apps.ego_item_pub.process_item
            (
                p_api_version => 1.0,
                p_init_msg_list => c_api_true,
                p_commit => c_api_false,
                p_transaction_type => 'UPDATE',
                p_inventory_item_id => p_inventory_item_id,
                p_organization_id => p_organization_id,
                p_item_type => p_item_type,
                x_inventory_item_id => l_out_item_id,
                x_organization_id => l_out_org_id,
                x_return_status => l_status,
                x_msg_count => l_msg_count,
                x_msg_data => l_msg_data
            );
            x_message := fnc_get_api_messages(NVL(l_msg_count, 0));
            pcd_append_text
            (
                x_message,
                l_msg_data
            );
            IF NVL(l_status, c_return_error) <> c_return_success THEN
                raise_application_error(-20675, 'Item Type API failed in organization ' ||
                    p_organization_id || ': ' || dbms_lob.substr
                    (
                        x_message,
                        1500,
                        1)
                    );
            END IF;
        END IF;
        SELECT
            item_type
        INTO
            l_after
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = p_inventory_item_id
          AND  organization_id   = p_organization_id;
        IF l_after IS NULL OR l_after <> p_item_type THEN
            raise_application_error
            (
                -20680,
                'Item Type API postcondition failed in organization ' || p_organization_id
            );
        END IF;
        pcd_append_text(x_message, 'ITEM_ID=' || p_inventory_item_id || ', ORG_ID=' ||
            p_organization_id || ', BEFORE=' || NVL(l_before, 'NULL') || ', AFTER=' || l_after);
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'PCD_APPLY_ITEM_TYPE',
                SQLERRM
            );
            raise_application_error
            (
                -20685,
                'Unexpected Error in pcd_apply_item_type: ' || SQLERRM,
                TRUE
            );
    END pcd_apply_item_type;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_process_request
    -- Purpose    : Process a staged request through master creation, target assignments,
    --              attributes and categories.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_validate_only_flag IN VARCHAR2 - Requests validation without persisting item changes
    --     when set to Y.
    --   p_user_id IN NUMBER - EBS user identifier; NULL invokes the existing context fallback.
    --   p_resp_id IN NUMBER - EBS responsibility identifier; NULL invokes the existing context
    --     fallback.
    --   p_resp_appl_id IN NUMBER - EBS responsibility application identifier; NULL uses the
    --     existing fallback.
    --   p_commit_flag IN VARCHAR2 - Controls whether the routine commits successful changes.
    --   x_return_status OUT VARCHAR2 - Success, error or unexpected status returned to the caller.
    --   x_message OUT CLOB - Detailed result or diagnostic text returned to the caller.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_process_request
    (
        p_item_request_id IN NUMBER,
        p_validate_only_flag IN VARCHAR2 DEFAULT 'N',
        p_user_id IN NUMBER DEFAULT NULL,
        p_resp_id IN NUMBER DEFAULT NULL,
        p_resp_appl_id IN NUMBER DEFAULT NULL,
        p_commit_flag IN VARCHAR2 DEFAULT 'Y',
        x_return_status OUT VARCHAR2,
        x_message OUT CLOB
    )
    IS
        TYPE t_rule_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
        l_selected_rules                    t_rule_ids;
        l_division_set_id                   NUMBER;
        l_request                           ops.adre_inv_item_request%ROWTYPE;
        l_master_request_org_id             NUMBER;
        l_master_org_id                     NUMBER;
        l_master_org_code                   VARCHAR2(30);
        l_master_template_id                NUMBER;
        l_master_template_name              VARCHAR2(240);
        l_master_item_id                    NUMBER;
        l_master_status_code                VARCHAR2(30);
        l_master_exists                     BOOLEAN;
        l_master_return_status              VARCHAR2(1);
        l_master_msg_count                  NUMBER := 0;
        l_master_message                    CLOB;
        l_target_exists                     BOOLEAN;
        l_target_item_id                    NUMBER;
        l_target_status_code                VARCHAR2(30);
        l_target_return_status              VARCHAR2(1);
        l_target_msg_count                  NUMBER := 0;
        l_target_message                    CLOB;
        l_target_template_name              VARCHAR2(240);
        l_resolved_target_rule_id           NUMBER;
        l_resolved_target_template_id       NUMBER;
        l_resolved_target_template_name     VARCHAR2(240);
        l_resolved_target_rule_priority     NUMBER;
        l_mrp_mapping_count                 NUMBER;
        l_target_template_mrp_count         NUMBER;
        l_target_template_mrp_planning_code NUMBER;
        l_mrp_resolution_source             VARCHAR2(30);
        l_target_template_item_id           NUMBER;
        l_target_template_api_org_id        NUMBER;
        l_target_template_return_status     VARCHAR2(1);
        l_target_template_msg_count         NUMBER := 0;
        l_target_template_msg_data          VARCHAR2(4000);
        l_target_template_message           CLOB;
        l_target_combined_message           CLOB;
        l_master_mrp_planning_code          NUMBER;
        l_error_handler_message_list        apps.error_handler.error_tbl_type;
        l_ebs_item_number                   VARCHAR2(4000);
        l_item_segment1                     VARCHAR2(40);
        l_item_segment2                     VARCHAR2(40);
        l_item_segment3                     VARCHAR2(40);
        l_planning_method                   VARCHAR2(4000);
        l_item_type_code                    VARCHAR2(100);
        l_division_value                    VARCHAR2(240);
        l_division_count                    NUMBER;
        l_user_item_type_code               VARCHAR2(30);
        l_construction                      VARCHAR2(4000);
        l_staged_construction               VARCHAR2(4000);
        l_engineering_item_flag             VARCHAR2(4000);
        l_hims                              VARCHAR2(4000);
        l_price_per_uom                     NUMBER;
        l_lead_time_days                    NUMBER;
        l_pdr_number                        VARCHAR2(4000);
        l_percent_solids                    NUMBER;
        l_weight_per_gallon                 NUMBER;
        l_weight_uom_code                   VARCHAR2(30);
        l_batch_size                        VARCHAR2(4000);
        l_shelf_life_days                   NUMBER;
        l_planner                           VARCHAR2(4000);
        l_shippable_item_flag               VARCHAR2(4000);
        l_requested_mrp_planning_code       NUMBER;
        l_master_attr_item_id               NUMBER;
        l_master_attr_api_org_id            NUMBER;
        l_master_attr_return_status         VARCHAR2(1);
        l_master_attr_msg_count             NUMBER := 0;
        l_master_attr_msg_data              VARCHAR2(4000);
        l_master_attr_message               CLOB;
        l_outside_processing                VARCHAR2(4000);
        l_width                             NUMBER;
        l_width_uom                         VARCHAR2(30);
        l_target_length                     NUMBER;
        l_target_length_uom                 VARCHAR2(30);
        l_target_dimension_uom_code         VARCHAR2(30);
        l_target_unit_width                 NUMBER;
        l_target_unit_length                NUMBER;
        l_target_attr_value_count           NUMBER := 0;
        l_target_attr_item_id               NUMBER;
        l_target_attr_api_org_id            NUMBER;
        l_target_attr_return_status         VARCHAR2(1);
        l_target_attr_msg_count             NUMBER := 0;
        l_target_attr_msg_data              VARCHAR2(4000);
        l_target_attr_message               CLOB;
        l_category_return_status            VARCHAR2(1);
        l_category_message                  CLOB;
        l_context_user_id                   NUMBER;
        l_context_resp_id                   NUMBER;
        l_context_resp_appl_id              NUMBER;
        l_commit_flag                       VARCHAR2(1);
        l_validate_only_flag                VARCHAR2(1);
        l_execution_id                      VARCHAR2(100);
        l_error_text                        VARCHAR2(4000);
        l_actual_item_status_code           VARCHAR2(30);
        l_required_attribute_count          NUMBER;
        l_bom_enabled_flag                  VARCHAR2(1);
        l_engineering_status                VARCHAR2(4000);
        l_eng_item_flag                     VARCHAR2(1);
        l_master_api_org_id                 NUMBER;
        l_api_failure_status                VARCHAR2(1);
        l_api_failure_msg_count             NUMBER;
        l_api_failure_message               CLOB;
        l_api_failure_request_org_id        NUMBER;
        l_api_failure_api_name              VARCHAR2(240);
        l_api_failure_process_name          VARCHAR2(100);
        l_api_failure_entity_id             NUMBER;
        e_api_failure                       EXCEPTION;
        CURSOR c_targets
        IS
            SELECT
                request_org_id,
                ebs_organization_id,
                ebs_template_id,
                ebs_inventory_item_id,
                assignment_status
            FROM
                ops.adre_inv_item_request_org
            WHERE  item_request_id   = p_item_request_id
              AND  organization_role = 'TARGET'
            ORDER BY
                ebs_organization_id;
    BEGIN
        g_text_correction_flag := 'N';
        x_return_status := NULL;
        x_message := NULL;
        dbms_lob.createtemporary
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
        FROM
            ops.adre_inv_item_request
        WHERE  item_request_id = p_item_request_id FOR UPDATE;
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
            raise_application_error
            (
                -20690,
                'Item Request must be READY or ERROR before EBS processing. ' ||
                'Current status=' || l_request.request_status
            );
        END IF;
        IF l_validate_only_flag = 'Y' THEN
            x_return_status := c_return_error;
            pcd_append_text
            (
                x_message,
                'Validate-only execution is disabled because EBS APIs can run before rollback. No EBS API call was made. Use a controlled single-request execution for API diagnostics.'
            );
            ROLLBACK;
            RETURN;
        END IF;
        IF l_request.item_number IS NULL THEN
            raise_application_error
            (
                -20695,
                'ITEM_NUMBER is required.'
            );
        END IF;
        IF l_request.item_description IS NULL THEN
            raise_application_error
            (
                -20700,
                'ITEM_DESCRIPTION is required.'
            );
        END IF;
        IF l_request.primary_uom_code IS NULL THEN
            raise_application_error
            (
                -20705,
                'PRIMARY_UOM_CODE is required.'
            );
        END IF;
        IF l_request.item_status_code IS NULL THEN
            raise_application_error
            (
                -20710,
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
        FROM
            ops.adre_inv_item_request_org
        WHERE  item_request_id   = p_item_request_id
          AND  organization_role = 'MASTER';
        IF l_master_template_id IS NULL THEN
            raise_application_error
            (
                -20715,
                'The MASTER Request Organization does not contain EBS_TEMPLATE_ID.'
            );
        END IF;
        SELECT
            template_name
        INTO
            l_master_template_name
        FROM
            apps.mtl_item_templates
        WHERE  template_id = l_master_template_id;
        l_master_org_code :=
            fnc_get_org_code
            (
                l_master_org_id
            );
        SELECT
            inventory_item_status_code
        INTO
            l_actual_item_status_code
        FROM
            apps.mtl_item_status
        WHERE  UPPER(inventory_item_status_code) = UPPER(l_request.item_status_code)
          AND  ROWNUM                            = 1;
        SELECT
            UPPER(TRIM(adinitty.item_type_code))
        INTO
            l_item_type_code
        FROM
            ops.adre_inv_item_type adinitty
        WHERE  adinitty.item_type_id = l_request.item_type_id;
        l_division_set_id := fnc_category_role_id('DIVISION', l_master_org_id);
        SELECT
            COUNT(DISTINCT UPPER(TRIM(adinitca.category_value))),
            MIN(adinitca.category_value)
        INTO
            l_division_count,
            l_division_value
        FROM
            ops.adre_inv_item_category adinitca,
            ops.adre_inv_item_request_org adinitreor
        WHERE  adinitreor.request_org_id    = adinitca.request_org_id
          AND  adinitreor.item_request_id   = p_item_request_id
          AND  adinitca.assignment_status   = 'READY'
          AND  adinitca.ebs_category_set_id = l_division_set_id;
        IF l_division_count > 1 THEN
            raise_application_error
            (
                -20720,
                'More than one distinct DIVISION category value exists for the Item Request.'
            );
        END IF;
        pcd_validate_attribute_inputs(p_item_request_id);
        pcd_apply_auto_planner
        (
            p_item_request_id => p_item_request_id,
            io_message => x_message
        );
        pcd_validate_required_attributes
        (
            p_item_request_id
        );
        SELECT
            CASE WHEN COUNT(*) > 0 THEN 'Y' ELSE c_missing_char END
        INTO
            l_bom_enabled_flag
        FROM
            ops.adre_inv_item_bom adinitbo,
            ops.adre_inv_item_request_org adinitreor
        WHERE  adinitreor.request_org_id  = adinitbo.request_org_id
          AND  adinitreor.item_request_id = p_item_request_id;
        BEGIN
            SELECT
                av.attribute_value
            INTO
                l_engineering_item_flag
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat
            WHERE  adinitat.item_attribute_id = av.item_attribute_id
              AND  av.request_org_id          = l_master_request_org_id
              AND  adinitat.attribute_code    = 'ENGINEERING_ITEM_FLAG'
              AND  av.attribute_value    IS NOT NULL
              AND  ROWNUM                     = 1;
        EXCEPTION
            WHEN no_data_found THEN
                l_engineering_item_flag := NULL;
            WHEN OTHERS THEN
                raise_application_error
                (
                    -20725,
                    'Unexpected Error in pcd_process_request: ' || SQLERRM,
                    TRUE
                );
        END;
        IF l_engineering_item_flag IS NOT NULL THEN
            l_engineering_item_flag :=
                UPPER(TRIM(l_engineering_item_flag));
            IF l_engineering_item_flag NOT IN ('Y', 'N') THEN
                raise_application_error
                (
                    -20730,
                    'ENGINEERING_ITEM_FLAG must be Y or N. VALUE=' ||
                    l_engineering_item_flag
                );
            END IF;
            l_eng_item_flag := l_engineering_item_flag;
        ELSE
            BEGIN
                SELECT
                    adinitatva.attribute_value
                INTO
                    l_engineering_status
                FROM
                    ops.adre_inv_item_attr_value adinitatva,
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_attribute adinitat
                WHERE  adinitreor.request_org_id       = adinitatva.request_org_id
                  AND  adinitat.item_attribute_id      = adinitatva.item_attribute_id
                  AND  adinitreor.item_request_id      = p_item_request_id
                  AND  adinitat.attribute_code         = 'ENGINEERING_STATUS'
                  AND  adinitatva.attribute_value IS NOT NULL
                  AND  ROWNUM                          = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    l_engineering_status := NULL;
                WHEN OTHERS THEN
                    raise_application_error
                    (
                        -20735,
                        'Unexpected Error in pcd_process_request: ' || SQLERRM,
                        TRUE
                    );
            END;
            IF l_engineering_status IS NOT NULL THEN
                l_eng_item_flag := 'Y';
            ELSE
                l_eng_item_flag := c_missing_char;
            END IF;
        END IF;
        SELECT
            COUNT(*)
        INTO
            l_required_attribute_count
        FROM
            (
                SELECT
                    adinitatva.*
                FROM
                    ops.adre_inv_item_attr_value adinitatva,
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_request adinitre,
                    ops.adre_inv_item_type adinitty,
                    ops.adre_inv_item_attribute adinitat
                WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                  AND  adinitre.item_request_id    = adinitreor.item_request_id
                  AND  adinitty.item_type_id       = adinitre.item_type_id
                  AND  adinitty.active_flag        = 'Y'
                  AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                  AND  adinitat.active_flag        = 'Y'
                  AND  (adinitatva.value_status    = 'READY'
                        OR (g_text_correction_flag = 'Y'
                  AND  adinitatva.value_status     = 'PROCESSED'
                  AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                  AND  EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_type_attr adinittyat
                        WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                          AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                          AND  adinittyat.active_flag        = 'Y'
                          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                    )
            )
            av,
            ops.adre_inv_item_request_org adinitreor,
            ops.adre_inv_item_attribute adinitat
        WHERE  adinitreor.request_org_id  = av.request_org_id
          AND  adinitat.item_attribute_id = av.item_attribute_id
          AND  adinitreor.item_request_id = p_item_request_id
          AND  adinitat.attribute_code NOT IN ('PLANNING_METHOD', 'OUTSIDE_PROCESSING', 'WIDTH', 'TARGET_LENGTH', 'ENGINEERING_ITEM_FLAG', 'HIMS', 'EXPENSE_ITEM_FLAG', 'PRICE_PER_UOM', 'LEAD_TIME_DAYS', 'BATCH_SIZE', 'SHELF_LIFE_DAYS', 'SHELF_LIFE_CONTROL', 'PLANNER', 'SHIPPABLE_ITEM_FLAG', 'PDR_NUMBER', 'PERCENT_SOLIDS', 'WEIGHT_PER_GALLON', 'CONSTRUCTION')
          AND  (adinitat.ebs_attribute_group IS NULL OR adinitat.ebs_attribute_name IS NULL);
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
            'Resolved EBS User Item Type from explicit configuration, ITEM_TYPE=' ||
            l_item_type_code ||
            ': ' ||
            NVL(l_user_item_type_code, 'NOT SENT')
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
        DECLARE
            l_check NUMBER;
        BEGIN
            FOR ro IN (
                SELECT
                    request_org_id
                FROM
                    ops.adre_inv_item_request_org
                WHERE  item_request_id   = p_item_request_id
                  AND  organization_role = 'TARGET'
            )
            LOOP
                l_check := fnc_shelf_life_control(ro.request_org_id);
                FOR av IN (
                    SELECT
                        TO_NUMBER(v.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') val,
                        v.value_uom_code uom
                    FROM
                        (
                            SELECT
                                adinitatva.*
                            FROM
                                ops.adre_inv_item_attr_value adinitatva,
                                ops.adre_inv_item_request_org adinitreor,
                                ops.adre_inv_item_request adinitre,
                                ops.adre_inv_item_type adinitty,
                                ops.adre_inv_item_attribute adinitat
                            WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                              AND  adinitre.item_request_id    = adinitreor.item_request_id
                              AND  adinitty.item_type_id       = adinitre.item_type_id
                              AND  adinitty.active_flag        = 'Y'
                              AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinitat.active_flag        = 'Y'
                              AND  (adinitatva.value_status    = 'READY'
                                    OR (g_text_correction_flag = 'Y'
                              AND  adinitatva.value_status     = 'PROCESSED'
                              AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                              AND  EXISTS
                                (
                                    SELECT
                                        1
                                    FROM
                                        ops.adre_inv_item_type_attr adinittyat
                                    WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                                      AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                                      AND  adinittyat.active_flag        = 'Y'
                                      AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                                )
                        )
                        v,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitat.item_attribute_id = v.item_attribute_id
                      AND  v.request_org_id           = ro.request_org_id
                      AND  adinitat.attribute_code    IN ('WIDTH', 'TARGET_LENGTH')
                      AND  v.attribute_value IS NOT NULL
                )
                LOOP
                    l_check := fnc_convert_dimension
                    (
                        av.val,
                        av.uom,
                        'IN'
                    );
                END LOOP;
            END LOOP;
        END;
        FOR r_rule_target IN
        (
            SELECT
                request_org_id,
                ebs_organization_id
            FROM
                ops.adre_inv_item_request_org
            WHERE  item_request_id   = p_item_request_id
              AND  organization_role = 'TARGET'
            ORDER BY
                ebs_organization_id
        )
        LOOP
            l_resolved_target_rule_id := NULL;
            l_resolved_target_template_id := NULL;
            l_resolved_target_template_name := NULL;
            l_resolved_target_rule_priority := NULL;
            pcd_resolve_target_template_rule
            (
                p_item_request_id => p_item_request_id,
                p_item_type_id => l_request.item_type_id,
                p_target_organization_id => r_rule_target.ebs_organization_id,
                x_item_template_rule_id =>
                    l_resolved_target_rule_id,
                x_ebs_template_id =>
                    l_resolved_target_template_id,
                x_template_name =>
                    l_resolved_target_template_name,
                x_rule_priority =>
                    l_resolved_target_rule_priority
            );
            l_selected_rules(r_rule_target.request_org_id) := l_resolved_target_rule_id;
            UPDATE ops.adre_inv_item_request_org
            SET ebs_template_id = l_resolved_target_template_id,
                last_updated_by =
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
            WHERE  request_org_id = r_rule_target.request_org_id;
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
                p_execution_id => l_execution_id,
                p_item_request_id => p_item_request_id,
                p_request_org_id => r_rule_target.request_org_id,
                p_process_name => 'RESOLVE_TARGET_TEMPLATE',
                p_api_name => NULL,
                p_entity_type => 'TEMPLATE_RULE',
                p_entity_id => l_resolved_target_rule_id,
                p_log_level => 'INFO',
                p_process_status => 'SUCCESS',
                p_api_return_status => c_return_success,
                p_api_message_count => 0,
                p_message_text =>
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
        l_user_item_type_code := fnc_resolve_item_type
        (
            l_request.item_type_id,
            p_item_request_id
        );
        l_context_user_id :=
            p_user_id;
        l_context_resp_id :=
            p_resp_id;
        l_context_resp_appl_id :=
            p_resp_appl_id;
        pcd_initialize_ebs_context
        (
            p_user_id => l_context_user_id,
            p_resp_id => l_context_resp_id,
            p_resp_appl_id => l_context_resp_appl_id
        );
        pcd_validate_text_dff(p_item_request_id);
        UPDATE ops.adre_inv_item_request
        SET request_status = c_request_processing
        WHERE  item_request_id = p_item_request_id;
        UPDATE ops.adre_inv_item_request_org
        SET assignment_status = c_assignment_processing
        WHERE  item_request_id   = p_item_request_id
          AND  assignment_status IN
              (
                  c_assignment_ready,
                  c_assignment_error
              );
        l_master_exists :=
            fnc_item_exists
            (
                p_item_number => l_request.item_number,
                p_organization_id => l_master_org_id,
                x_inventory_item_id => l_master_item_id,
                x_item_status_code => l_master_status_code
            );
        IF l_master_exists THEN
            IF NVL(UPPER(TRIM(l_master_status_code)), '#NULL#') <>
               NVL(UPPER(TRIM(l_actual_item_status_code)), '#NULL#') THEN
                l_master_return_status := c_return_error;
                l_master_msg_count := 0;
                l_master_message :=
                    TO_CLOB
                    (
                        'MASTER item already exists in Oracle EBS with status ' ||
                        NVL(l_master_status_code, 'NULL') ||
                        ', but the request requires status ' ||
                        NVL(l_actual_item_status_code, 'NULL') ||
                        '. No update was performed.'
                    );
                pcd_write_log
                (
                    'CREATE_MASTER_ITEM',
                    'MASTER status mismatch. ITEM_NUMBER=' ||
                    l_request.item_number ||
                    ', ORGANIZATION_ID=' ||
                    l_master_org_id ||
                    ', EXISTING_STATUS=' ||
                    NVL(l_master_status_code, 'NULL') ||
                    ', REQUESTED_STATUS=' ||
                    NVL(l_actual_item_status_code, 'NULL') ||
                    '. No update was performed.'
                );
            ELSE
                l_master_return_status := c_return_success;
                l_master_msg_count := 0;
                l_master_message :=
                    TO_CLOB
                    (
                        'Master Item already exists in Oracle EBS with the requested status. Creation was skipped.'
                    );
            END IF;
        ELSE
            BEGIN
                apps.fnd_msg_pub.initialize;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error
                    (
                        -20740,
                        'Unexpected Error in pcd_process_request: ' || SQLERRM,
                        TRUE
                    );
            END;
            l_master_api_org_id := NULL;
            apps.ego_item_pub.process_item
            (
                p_api_version => 1.0,
                p_init_msg_list => c_api_true,
                p_commit => c_api_false,
                p_transaction_type => 'CREATE',
                p_template_name => l_master_template_name,
                p_item_number => l_request.item_number,
                p_segment1 => REGEXP_SUBSTR(l_request.item_number, '[^-]+', 1, 1),
                p_segment2 => REGEXP_SUBSTR(l_request.item_number, '[^-]+', 1, 2),
                p_segment3 => REGEXP_SUBSTR(l_request.item_number, '[^-]+', 1, 3),
                p_organization_id => l_master_org_id,
                p_organization_code => l_master_org_code,
                p_description => l_request.item_description,
                p_long_description =>
                    DBMS_LOB.SUBSTR(l_request.long_description, 4000, 1),
                p_primary_uom_code => l_request.primary_uom_code,
                p_inventory_item_status_code =>
                    fnc_optional_char
                    (
                        l_actual_item_status_code
                    ),
                p_bom_enabled_flag => l_bom_enabled_flag,
                p_eng_item_flag => l_eng_item_flag,
                x_inventory_item_id => l_master_item_id,
                x_organization_id => l_master_api_org_id,
                x_return_status => l_master_return_status,
                x_msg_count => l_master_msg_count
            );
            l_master_message :=
                fnc_get_api_messages
                (
                    l_master_msg_count
                );
            IF NVL(l_master_return_status, c_return_error) <> c_return_success THEN
                pcd_append_ego_error_messages(l_master_message);
            END IF;
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
                dbms_lob.substr(l_master_message, 1800, 1)
            );
        END IF;
        IF l_master_return_status <> c_return_success THEN
            l_api_failure_status := NVL(l_master_return_status, c_return_error);
            l_api_failure_msg_count := NVL(l_master_msg_count, 0);
            l_api_failure_request_org_id := l_master_request_org_id;
            l_api_failure_api_name := 'EGO_ITEM_PUB.PROCESS_ITEM';
            l_api_failure_process_name := 'CREATE_MASTER_ITEM';
            l_api_failure_entity_id := l_master_org_id;
            dbms_lob.createtemporary
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
            IF l_master_message IS NOT NULL THEN
                dbms_lob.append
                (
                    l_api_failure_message,
                    l_master_message
                );
            END IF;
            RAISE e_api_failure;
        END IF;
        UPDATE ops.adre_inv_item_request_org
        SET ebs_inventory_item_id = l_master_item_id,
            assignment_status = c_assignment_processed,
            api_return_status = l_master_return_status,
            api_message_count = NVL(l_master_msg_count, 0),
            api_message_text = l_master_message,
            api_processed_date = SYSDATE
        WHERE  request_org_id = l_master_request_org_id;
        pcd_insert_api_log
        (
            p_execution_id => l_execution_id,
            p_item_request_id => p_item_request_id,
            p_request_org_id => l_master_request_org_id,
            p_process_name => 'CREATE_MASTER_ITEM',
            p_api_name => 'EGO_ITEM_PUB.PROCESS_ITEM',
            p_entity_type => 'ORGANIZATION',
            p_entity_id => l_master_org_id,
            p_log_level => 'INFO',
            p_process_status => 'SUCCESS',
            p_api_return_status => l_master_return_status,
            p_api_message_count => l_master_msg_count,
            p_message_text => l_master_message
        );
        SELECT
            mtsyitkf.concatenated_segments,
            mtsyitb.segment1,
            mtsyitb.segment2,
            mtsyitb.segment3
        INTO
            l_ebs_item_number,
            l_item_segment1,
            l_item_segment2,
            l_item_segment3
        FROM
            apps.mtl_system_items_b mtsyitb,
            apps.mtl_system_items_kfv mtsyitkf
        WHERE  mtsyitkf.inventory_item_id = mtsyitb.inventory_item_id
          AND  mtsyitkf.organization_id   = mtsyitb.organization_id
          AND  mtsyitb.inventory_item_id  = l_master_item_id
          AND  mtsyitb.organization_id    = l_master_org_id;
        BEGIN
            SELECT
                av.attribute_value
            INTO
                l_planning_method
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat
            WHERE  adinitat.item_attribute_id = av.item_attribute_id
              AND  av.request_org_id          = l_master_request_org_id
              AND  adinitat.attribute_code    = 'PLANNING_METHOD'
              AND  av.attribute_value    IS NOT NULL
              AND  ROWNUM                     = 1;
        EXCEPTION
            WHEN no_data_found THEN
                l_planning_method := NULL;
            WHEN OTHERS THEN
                raise_application_error
                (
                    -20745,
                    'Unexpected Error in pcd_process_request: ' || SQLERRM,
                    TRUE
                );
        END;
        BEGIN
            SELECT
                av.attribute_value
            INTO
                l_hims
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat
            WHERE  adinitat.item_attribute_id = av.item_attribute_id
              AND  av.request_org_id          = l_master_request_org_id
              AND  adinitat.attribute_code    = 'HIMS'
              AND  av.attribute_value    IS NOT NULL
              AND  ROWNUM                     = 1;
        EXCEPTION
            WHEN no_data_found THEN
                l_hims := NULL;
            WHEN OTHERS THEN
                raise_application_error
                (
                    -20750,
                    'Unexpected Error in pcd_process_request: ' || SQLERRM,
                    TRUE
                );
        END;
        l_requested_mrp_planning_code := apps.fnd_api.g_miss_num;
        l_target_template_mrp_count := 0;
        l_target_template_mrp_planning_code := NULL;
        l_mrp_resolution_source := 'NOT SENT';
        SELECT
            COUNT(DISTINCT TO_NUMBER(TRIM(mtitteat.attribute_value))),
            MIN(TO_NUMBER(TRIM(mtitteat.attribute_value)))
        INTO
            l_target_template_mrp_count,
            l_target_template_mrp_planning_code
        FROM
            ops.adre_inv_item_request_org adinitreor,
            apps.mtl_item_templ_attributes mtitteat
        WHERE  mtitteat.template_id                 = adinitreor.ebs_template_id
          AND  adinitreor.item_request_id           = p_item_request_id
          AND  adinitreor.organization_role         = 'TARGET'
          AND  adinitreor.ebs_template_id           IS NOT NULL
          AND  UPPER(TRIM(mtitteat.attribute_name)) = 'MTL_SYSTEM_ITEMS.MRP_PLANNING_CODE'
          AND  mtitteat.enabled_flag                = 'Y'
          AND  mtitteat.attribute_value             IS NOT NULL;
        IF l_target_template_mrp_count > 1 THEN
            raise_application_error
            (
                -20755,
                'Selected TARGET Templates contain conflicting MASTER-controlled MRP_PLANNING_CODE values. ' ||
                'ITEM_REQUEST_ID=' ||
                p_item_request_id
            );
        END IF;
        IF l_planning_method IS NOT NULL THEN
            SELECT
                COUNT(DISTINCT TO_NUMBER(TRIM(mtitteat.attribute_value))),
                MIN(TO_NUMBER(TRIM(mtitteat.attribute_value)))
            INTO
                l_mrp_mapping_count,
                l_requested_mrp_planning_code
            FROM
                ops.adre_inv_item_request_org adinitreor,
                apps.mtl_item_templ_attributes mtitteat
            WHERE  mtitteat.template_id                    = adinitreor.ebs_template_id
              AND  adinitreor.item_request_id              = p_item_request_id
              AND  adinitreor.organization_role            = 'TARGET'
              AND  adinitreor.ebs_template_id              IS NOT NULL
              AND  UPPER(TRIM(mtitteat.attribute_name))    = 'MTL_SYSTEM_ITEMS.MRP_PLANNING_CODE'
              AND  mtitteat.enabled_flag                   = 'Y'
              AND  UPPER(TRIM(mtitteat.report_user_value)) = UPPER(TRIM(l_planning_method));
            IF l_mrp_mapping_count = 0
               OR l_requested_mrp_planning_code IS NULL
            THEN
                raise_application_error
                (
                    -20760,
                    'PLANNING_METHOD could not be resolved from the selected TARGET Template metadata. ' ||
                    'VALUE=' ||
                    l_planning_method
                );
            ELSIF l_mrp_mapping_count > 1 THEN
                raise_application_error
                (
                    -20765,
                    'PLANNING_METHOD resolves to more than one Oracle EBS MRP_PLANNING_CODE. ' ||
                    'VALUE=' ||
                    l_planning_method
                );
            END IF;
            l_mrp_resolution_source := 'PLANNING_METHOD';
        ELSIF l_target_template_mrp_count = 1 THEN
            l_requested_mrp_planning_code :=
                l_target_template_mrp_planning_code;
            l_mrp_resolution_source := 'TARGET_TEMPLATE';
        END IF;
        IF l_planning_method IS NOT NULL
           OR l_target_template_mrp_count = 1
           OR l_hims IS NOT NULL
           OR l_engineering_item_flag IS NOT NULL
        THEN
            BEGIN
                apps.fnd_msg_pub.initialize;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error
                    (
                        -20770,
                        'Unexpected Error in pcd_process_request: ' || SQLERRM,
                        TRUE
                    );
            END;
            l_master_attr_item_id := NULL;
            l_master_attr_api_org_id := NULL;
            l_master_attr_return_status := NULL;
            l_master_attr_msg_count := 0;
            l_master_attr_msg_data := NULL;
            l_master_attr_message := NULL;
            l_error_handler_message_list.delete;
            apps.ego_item_pub.process_item
            (
                p_api_version => 1.0,
                p_init_msg_list => c_api_true,
                p_commit => c_api_false,
                p_transaction_type => 'UPDATE',
                p_inventory_item_id => l_master_item_id,
                p_organization_id => l_master_org_id,
                p_mrp_planning_code => l_requested_mrp_planning_code,
                p_item_type =>
                    NVL
                    (
                        l_user_item_type_code,
                        apps.fnd_api.g_miss_char
                    ),
                p_long_description =>
                    DBMS_LOB.SUBSTR(l_request.long_description, 4000, 1),
                p_eng_item_flag => l_eng_item_flag,
                p_attribute14 => fnc_optional_char(l_hims),
                p_item_number => l_ebs_item_number,
                p_segment1 => l_item_segment1,
                p_segment2 => l_item_segment2,
                p_segment3 => l_item_segment3,
                x_inventory_item_id => l_master_attr_item_id,
                x_organization_id => l_master_attr_api_org_id,
                x_return_status => l_master_attr_return_status,
                x_msg_count => l_master_attr_msg_count,
                x_msg_data => l_master_attr_msg_data
            );
            l_master_attr_message :=
                fnc_get_api_messages
                (
                    l_master_attr_msg_count,
                    l_master_attr_msg_data
                );
            IF NVL(l_master_attr_return_status, c_return_error) <> c_return_success THEN
                BEGIN
                    l_error_handler_message_list.delete;
                    apps.error_handler.get_message_list
                    (
                        x_message_list => l_error_handler_message_list
                    );
                    IF l_error_handler_message_list.count > 0 THEN
                        FOR i IN 1 .. l_error_handler_message_list.count
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
                        raise_application_error
                        (
                            -20775,
                            'Unexpected Error in pcd_process_request: ' || SQLERRM,
                            TRUE
                        );
                END;
                l_api_failure_status :=
                    NVL(l_master_attr_return_status, c_return_error);
                l_api_failure_msg_count :=
                    NVL(l_master_attr_msg_count, 0);
                l_api_failure_request_org_id :=
                    l_master_request_org_id;
                l_api_failure_api_name :=
                    'EGO_ITEM_PUB.PROCESS_ITEM';
                l_api_failure_process_name :=
                    'APPLY_MASTER_ATTRIBUTES';
                l_api_failure_entity_id :=
                    l_master_org_id;
                dbms_lob.createtemporary
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
                        WHEN l_mrp_resolution_source = 'NOT SENT'
                            THEN 'NOT SENT'
                        ELSE TO_CHAR(l_requested_mrp_planning_code)
                    END ||
                    ', MRP_SOURCE=' ||
                    l_mrp_resolution_source ||
                    ', ENGINEERING_ITEM_FLAG=' ||
                    NVL(l_engineering_item_flag, 'NOT EXPLICITLY PROVIDED') ||
                    ', HIMS=' ||
                    NVL(l_hims, 'NOT SENT')
                );
                pcd_append_text
                (
                    l_api_failure_message,
                    dbms_lob.substr
                    (
                        l_master_attr_message,
                        3000,
                        1
                    )
                );
                RAISE e_api_failure;
            END IF;
            pcd_verify_attributes
            (
                l_master_request_org_id,
                l_master_item_id,
                l_master_org_id,
                'MASTER',
                l_requested_mrp_planning_code
            );
            pcd_insert_api_log
            (
                p_execution_id => l_execution_id,
                p_item_request_id => p_item_request_id,
                p_request_org_id => l_master_request_org_id,
                p_process_name => 'APPLY_MASTER_ATTRIBUTES',
                p_api_name => 'EGO_ITEM_PUB.PROCESS_ITEM',
                p_entity_type => 'ORGANIZATION',
                p_entity_id => l_master_org_id,
                p_log_level => 'INFO',
                p_process_status => 'SUCCESS',
                p_api_return_status => l_master_attr_return_status,
                p_api_message_count => l_master_attr_msg_count,
                p_message_text => l_master_attr_message
            );
            pcd_append_text
            (
                x_message,
                'MASTER application Attributes applied: PLANNING_METHOD=' ||
                NVL(l_planning_method, 'NOT SENT') ||
                ', MRP_PLANNING_CODE=' ||
                CASE
                    WHEN l_mrp_resolution_source = 'NOT SENT'
                        THEN 'NOT SENT'
                    ELSE TO_CHAR(l_requested_mrp_planning_code)
                END ||
                ', MRP_SOURCE=' ||
                l_mrp_resolution_source ||
                ', ENGINEERING_ITEM_FLAG=' ||
                CASE
                    WHEN l_eng_item_flag = c_missing_char THEN 'NOT SENT'
                    ELSE l_eng_item_flag
                END ||
                ', HIMS=' ||
                NVL(l_hims, 'NOT SENT')
            );
        END IF;
        pcd_apply_item_type(l_master_item_id, l_master_org_id,
                            l_user_item_type_code, l_master_attr_message);
        pcd_append_text
        (
            x_message,
            dbms_lob.substr(l_master_attr_message, 3000, 1)
        );
        SELECT
            mtsyitb.mrp_planning_code
        INTO
            l_master_mrp_planning_code
        FROM
            apps.mtl_system_items_b mtsyitb
        WHERE  mtsyitb.inventory_item_id = l_master_item_id
          AND  mtsyitb.organization_id   = l_master_org_id;
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
        FOR r_target IN c_targets
        LOOP
            l_target_item_id := NULL;
            l_target_status_code := NULL;
            l_target_return_status := NULL;
            l_target_msg_count := 0;
            l_target_message := NULL;
            l_target_template_name := NULL;
            l_target_template_item_id := NULL;
            l_target_template_api_org_id := NULL;
            l_target_template_return_status := NULL;
            l_target_template_msg_count := 0;
            l_target_template_msg_data := NULL;
            l_target_template_message := NULL;
            l_target_combined_message := NULL;
            l_target_attr_value_count := 0;
            l_target_attr_item_id := NULL;
            l_target_attr_api_org_id := NULL;
            l_target_attr_return_status := NULL;
            l_target_attr_msg_count := 0;
            l_target_attr_msg_data := NULL;
            l_target_attr_message := NULL;
            l_outside_processing := NULL;
            l_width := NULL;
            l_width_uom := NULL;
            l_target_length := NULL;
            l_target_length_uom := NULL;
            l_price_per_uom := NULL;
            l_lead_time_days := NULL;
            l_pdr_number := NULL;
            l_percent_solids := NULL;
            l_weight_per_gallon := NULL;
            l_weight_uom_code := NULL;
            l_staged_construction := NULL;
            l_construction := NULL;
            l_batch_size := NULL;
            l_shelf_life_days := NULL;
            l_planner := NULL;
            l_shippable_item_flag := NULL;
            l_target_dimension_uom_code := apps.fnd_api.g_miss_char;
            l_target_unit_width := apps.fnd_api.g_miss_num;
            l_target_unit_length := apps.fnd_api.g_miss_num;
            l_error_handler_message_list.delete;
            l_target_exists :=
                fnc_item_exists
                (
                    p_item_number => l_request.item_number,
                    p_organization_id => r_target.ebs_organization_id,
                    x_inventory_item_id => l_target_item_id,
                    x_item_status_code => l_target_status_code
                );
            IF l_target_exists THEN
                l_target_return_status := c_return_success;
                l_target_msg_count := 0;
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
                        raise_application_error
                        (
                            -20780,
                            'Unexpected Error in pcd_process_request: ' || SQLERRM,
                            TRUE
                        );
                END;
                apps.ego_item_pub.assign_item_to_org
                (
                    p_api_version => 1.0,
                    p_init_msg_list => c_api_true,
                    p_commit => c_api_false,
                    p_inventory_item_id => l_master_item_id,
                    p_item_number => l_request.item_number,
                    p_organization_id => r_target.ebs_organization_id,
                    p_organization_code =>
                        fnc_get_org_code
                        (
                            r_target.ebs_organization_id
                        ),
                    p_primary_uom_code => l_request.primary_uom_code,
                    x_return_status => l_target_return_status,
                    x_msg_count => l_target_msg_count
                );
                l_target_message :=
                    fnc_get_api_messages
                    (
                        l_target_msg_count
                    );
                IF l_target_return_status = c_return_success THEN
                    l_target_exists :=
                        fnc_item_exists
                        (
                            p_item_number => l_request.item_number,
                            p_organization_id => r_target.ebs_organization_id,
                            x_inventory_item_id => l_target_item_id,
                            x_item_status_code => l_target_status_code
                        );
                END IF;
            END IF;
            IF l_target_return_status <> c_return_success THEN
                l_api_failure_status := NVL(l_target_return_status, c_return_error);
                l_api_failure_msg_count := NVL(l_target_msg_count, 0);
                l_api_failure_request_org_id := r_target.request_org_id;
                l_api_failure_api_name := 'EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG';
                l_api_failure_process_name := 'ASSIGN_TARGET_ORG';
                l_api_failure_entity_id := r_target.ebs_organization_id;
                dbms_lob.createtemporary
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
                    dbms_lob.substr
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
                p_execution_id => l_execution_id,
                p_item_request_id => p_item_request_id,
                p_request_org_id => r_target.request_org_id,
                p_process_name => 'ASSIGN_TARGET_ORG',
                p_api_name => 'EGO_ITEM_PUB.ASSIGN_ITEM_TO_ORG',
                p_entity_type => 'ORGANIZATION',
                p_entity_id => r_target.ebs_organization_id,
                p_log_level => 'INFO',
                p_process_status => 'SUCCESS',
                p_api_return_status => l_target_return_status,
                p_api_message_count => l_target_msg_count,
                p_message_text => l_target_message
            );
            pcd_append_text
            (
                l_target_combined_message,
                'Organization assignment result:'
            );
            pcd_append_text
            (
                l_target_combined_message,
                dbms_lob.substr
                (
                    l_target_message,
                    3000,
                    1
                )
            );
            SELECT
                MAX(CASE WHEN adinitat.attribute_code = 'SHELF_LIFE_DAYS' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'PLANNER' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'SHIPPABLE_ITEM_FLAG' THEN av.attribute_value END)
            INTO
                l_shelf_life_days,
                l_planner,
                l_shippable_item_flag
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat
            WHERE  adinitat.item_attribute_id = av.item_attribute_id
              AND  av.request_org_id          = r_target.request_org_id
              AND  adinitat.attribute_code    IN ('SHELF_LIFE_DAYS', 'SHELF_LIFE_CONTROL', 'PLANNER', 'SHIPPABLE_ITEM_FLAG', 'PDR_NUMBER', 'PERCENT_SOLIDS', 'WEIGHT_PER_GALLON', 'CONSTRUCTION');
            IF l_shelf_life_days IS NOT NULL
                AND l_shelf_life_days <= 0
            THEN
                raise_application_error
                (
                    -20785,
                    'SHELF_LIFE_DAYS must be greater than zero. VALUE=' ||
                    TO_CHAR(l_shelf_life_days)
                );
            END IF;
            l_planner :=
                NULLIF(TRIM(l_planner), '');
            IF l_shippable_item_flag IS NOT NULL THEN
                l_shippable_item_flag :=
                    UPPER(TRIM(l_shippable_item_flag));
                IF l_shippable_item_flag NOT IN ('Y', 'N') THEN
                    raise_application_error
                    (
                        -20790,
                        'SHIPPABLE_ITEM_FLAG must be Y or N. VALUE=' ||
                        l_shippable_item_flag
                    );
                END IF;
            END IF;
            IF r_target.ebs_template_id IS NOT NULL THEN
                SELECT
                    template_name
                INTO
                    l_target_template_name
                FROM
                    apps.mtl_item_templates
                WHERE  template_id = r_target.ebs_template_id;
                BEGIN
                    apps.fnd_msg_pub.initialize;
                EXCEPTION
                    WHEN OTHERS THEN
                        raise_application_error
                        (
                            -20795,
                            'Unexpected Error in pcd_process_request: ' || SQLERRM,
                            TRUE
                        );
                END;
                l_target_template_msg_data :=
                    NULL;
                apps.ego_item_pub.process_item
                (
                    p_api_version => 1.0,
                    p_init_msg_list => c_api_true,
                    p_commit => c_api_false,
                    p_transaction_type => 'UPDATE',
                    p_template_id => r_target.ebs_template_id,
                    p_eng_item_flag => l_eng_item_flag,
                    p_template_name => l_target_template_name,
                    p_inventory_item_id =>
                        NVL
                        (
                            l_target_item_id,
                            l_master_item_id
                        ),
                    p_organization_id =>
                        r_target.ebs_organization_id,
                    p_mrp_planning_code =>
                        l_master_mrp_planning_code,
                    p_item_type =>
                        NVL
                        (
                            l_user_item_type_code,
                            apps.fnd_api.g_miss_char
                        ),
                    p_long_description =>
                        DBMS_LOB.SUBSTR(l_request.long_description, 4000, 1),
                    p_shelf_life_code => fnc_shelf_life_control(r_target.request_org_id),
                    p_shelf_life_days =>
                        NVL
                        (
                            l_shelf_life_days,
                            apps.fnd_api.g_miss_num
                        ),
                    p_planner_code =>
                        NVL
                        (
                            l_planner,
                            apps.fnd_api.g_miss_char
                        ),
                    p_shippable_item_flag =>
                        NVL
                        (
                            l_shippable_item_flag,
                            apps.fnd_api.g_miss_char
                        ),
                    p_item_number =>
                        l_ebs_item_number,
                    p_segment1 =>
                        l_item_segment1,
                    p_segment2 =>
                        l_item_segment2,
                    p_segment3 =>
                        l_item_segment3,
                    x_inventory_item_id =>
                        l_target_template_item_id,
                    x_organization_id =>
                        l_target_template_api_org_id,
                    x_return_status =>
                        l_target_template_return_status,
                    x_msg_count =>
                        l_target_template_msg_count,
                    x_msg_data =>
                        l_target_template_msg_data
                );
                l_target_template_message :=
                    fnc_get_api_messages
                    (
                        l_target_template_msg_count,
                        l_target_template_msg_data
                    );
                IF l_target_template_return_status <> c_return_success THEN
                    BEGIN
                        l_error_handler_message_list.delete;
                        apps.error_handler.get_message_list
                        (
                            x_message_list =>
                                l_error_handler_message_list
                        );
                        IF l_error_handler_message_list.count > 0 THEN
                            FOR i IN 1 .. l_error_handler_message_list.count
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
                            raise_application_error
                            (
                                -20800,
                                'Unexpected Error in pcd_process_request: ' || SQLERRM,
                                TRUE
                            );
                    END;
                END IF;
                IF l_target_template_return_status <> c_return_success THEN
                    l_api_failure_status :=
                        NVL
                        (
                            l_target_template_return_status,
                            c_return_error
                        );
                    l_api_failure_msg_count :=
                        NVL
                        (
                            l_target_template_msg_count,
                            0
                        );
                    l_api_failure_request_org_id :=
                        r_target.request_org_id;
                    l_api_failure_api_name :=
                        'EGO_ITEM_PUB.PROCESS_ITEM';
                    l_api_failure_process_name :=
                        'APPLY_TARGET_TEMPLATE';
                    l_api_failure_entity_id :=
                        r_target.ebs_organization_id;
                    dbms_lob.createtemporary
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
                        dbms_lob.substr
                        (
                            l_target_template_message,
                            3000,
                            1
                        )
                    );
                    RAISE e_api_failure;
                END IF;
                l_target_exists :=
                    fnc_item_exists
                    (
                        p_item_number => l_request.item_number,
                        p_organization_id => r_target.ebs_organization_id,
                        x_inventory_item_id => l_target_item_id,
                        x_item_status_code => l_target_status_code
                    );
                pcd_insert_api_log
                (
                    p_execution_id => l_execution_id,
                    p_item_request_id => p_item_request_id,
                    p_request_org_id => r_target.request_org_id,
                    p_process_name => 'APPLY_TARGET_TEMPLATE',
                    p_api_name => 'EGO_ITEM_PUB.PROCESS_ITEM',
                    p_entity_type => 'ORGANIZATION',
                    p_entity_id => r_target.ebs_organization_id,
                    p_log_level => 'INFO',
                    p_process_status => 'SUCCESS',
                    p_api_return_status => l_target_template_return_status,
                    p_api_message_count => l_target_template_msg_count,
                    p_message_text => l_target_template_message
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
                    dbms_lob.substr
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
                    r_target.ebs_template_id ||
                    ', SHELF_LIFE_DAYS=' ||
                    CASE
                        WHEN l_shelf_life_days IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_shelf_life_days)
                    END ||
                    ', PLANNER=' ||
                    NVL(l_planner, 'NOT SENT') ||
                    ', SHIPPABLE_ITEM_FLAG=' ||
                    NVL(l_shippable_item_flag, 'NOT SENT')
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
            SELECT
                MAX(CASE WHEN adinitat.attribute_code = 'OUTSIDE_PROCESSING' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'WIDTH' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'WIDTH' THEN av.value_uom_code END),
                MAX(CASE WHEN adinitat.attribute_code = 'TARGET_LENGTH' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'TARGET_LENGTH' THEN av.value_uom_code END),
                MAX(CASE WHEN adinitat.attribute_code = 'PRICE_PER_UOM' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'LEAD_TIME_DAYS' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'BATCH_SIZE' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'SHELF_LIFE_DAYS' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'PLANNER' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'SHIPPABLE_ITEM_FLAG' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'PDR_NUMBER' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'CONSTRUCTION' THEN av.attribute_value END),
                MAX(CASE WHEN adinitat.attribute_code = 'PERCENT_SOLIDS' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'WEIGHT_PER_GALLON' THEN TO_NUMBER(av.attribute_value, c_number_format, 'NLS_NUMERIC_CHARACTERS=''.,''') END),
                MAX(CASE WHEN adinitat.attribute_code = 'WEIGHT_PER_GALLON' THEN av.value_uom_code END)
            INTO
                l_outside_processing,
                l_width,
                l_width_uom,
                l_target_length,
                l_target_length_uom,
                l_price_per_uom,
                l_lead_time_days,
                l_batch_size,
                l_shelf_life_days,
                l_planner,
                l_shippable_item_flag,
                l_pdr_number,
                l_staged_construction,
                l_percent_solids,
                l_weight_per_gallon,
                l_weight_uom_code
            FROM
                (
                    SELECT
                        adinitatva.*
                    FROM
                        ops.adre_inv_item_attr_value adinitatva,
                        ops.adre_inv_item_request_org adinitreor,
                        ops.adre_inv_item_request adinitre,
                        ops.adre_inv_item_type adinitty,
                        ops.adre_inv_item_attribute adinitat
                    WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                      AND  adinitre.item_request_id    = adinitreor.item_request_id
                      AND  adinitty.item_type_id       = adinitre.item_type_id
                      AND  adinitty.active_flag        = 'Y'
                      AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                      AND  adinitat.active_flag        = 'Y'
                      AND  (adinitatva.value_status    = 'READY'
                            OR (g_text_correction_flag = 'Y'
                      AND  adinitatva.value_status     = 'PROCESSED'
                      AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                      AND  EXISTS
                        (
                            SELECT
                                1
                            FROM
                                ops.adre_inv_item_type_attr adinittyat
                            WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                              AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                              AND  adinittyat.active_flag        = 'Y'
                              AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                        )
                )
                av,
                ops.adre_inv_item_attribute adinitat
            WHERE  adinitat.item_attribute_id = av.item_attribute_id
              AND  av.request_org_id          = r_target.request_org_id
              AND  adinitat.attribute_code    IN ('OUTSIDE_PROCESSING', 'WIDTH', 'TARGET_LENGTH', 'PRICE_PER_UOM', 'LEAD_TIME_DAYS', 'BATCH_SIZE', 'SHELF_LIFE_DAYS', 'SHELF_LIFE_CONTROL', 'PLANNER', 'SHIPPABLE_ITEM_FLAG', 'PDR_NUMBER', 'PERCENT_SOLIDS', 'WEIGHT_PER_GALLON', 'CONSTRUCTION');
            l_target_attr_value_count :=
                  CASE WHEN l_outside_processing IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_width IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_target_length IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_price_per_uom IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_lead_time_days IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_batch_size IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_shelf_life_days IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_planner IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_shippable_item_flag IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_pdr_number IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_staged_construction IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_percent_solids IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_weight_per_gallon IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN l_request.initiator IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN fnc_shelf_life_control(r_target.request_org_id) <> apps.fnd_api.g_miss_num THEN 1 ELSE 0 END;
            IF l_target_attr_value_count > 0 THEN
                IF l_outside_processing IS NOT NULL THEN
                    l_outside_processing :=
                        UPPER(TRIM(l_outside_processing));
                    IF l_outside_processing NOT IN ('Y', 'N') THEN
                        raise_application_error
                        (
                            -20805,
                            'OUTSIDE_PROCESSING must be Y or N. VALUE=' ||
                            l_outside_processing
                        );
                    END IF;
                ELSE
                    l_outside_processing := apps.fnd_api.g_miss_char;
                END IF;
                l_batch_size := TRIM(l_batch_size);
                l_planner := NULLIF(TRIM(l_planner), '');
                IF l_shippable_item_flag IS NOT NULL THEN
                    l_shippable_item_flag :=
                        UPPER(TRIM(l_shippable_item_flag));
                    IF l_shippable_item_flag NOT IN ('Y', 'N') THEN
                        raise_application_error
                        (
                            -20810,
                            'SHIPPABLE_ITEM_FLAG must be Y or N. VALUE=' ||
                            l_shippable_item_flag
                        );
                    END IF;
                END IF;
                l_pdr_number := NULLIF(TRIM(l_pdr_number), '');
                l_weight_uom_code := NULLIF(UPPER(TRIM(l_weight_uom_code)), '');
                l_staged_construction := NULLIF(TRIM(l_staged_construction), '');
                IF l_weight_per_gallon IS NOT NULL
                AND l_weight_per_gallon <= 0
                THEN
                    raise_application_error
                    (
                        -20815,
                        'WEIGHT_PER_GALLON must be greater than zero. VALUE=' ||
                        TO_CHAR(l_weight_per_gallon)
                    );
                END IF;
                l_construction := l_staged_construction;
                IF l_construction IS NULL THEN
                    IF l_percent_solids IS NOT NULL THEN
                        l_construction :=
                            TO_CHAR
                            (
                                l_percent_solids,
                                'TM9',
                                'NLS_NUMERIC_CHARACTERS=''.,'''
                            ) ||
                            ' % SOLIDS';
                    END IF;
                    IF l_weight_per_gallon IS NOT NULL THEN
                        l_construction :=
                            CASE
                                WHEN l_construction IS NULL THEN NULL
                                ELSE l_construction || '; '
                            END ||
                            TO_CHAR
                            (
                                l_weight_per_gallon,
                                'TM9',
                                'NLS_NUMERIC_CHARACTERS=''.,'''
                            ) ||
                            ' LBS/GAL';
                    END IF;
                END IF;
                IF l_width IS NOT NULL OR l_target_length IS NOT NULL THEN
                    SELECT
                        dimension_uom_code
                    INTO
                        l_target_dimension_uom_code
                    FROM
                        apps.mtl_system_items_b
                    WHERE  inventory_item_id = NVL(l_target_item_id, l_master_item_id)
                      AND  organization_id   = r_target.ebs_organization_id;
                    l_target_dimension_uom_code := NVL(l_target_dimension_uom_code, 'IN');
                    IF l_width IS NOT NULL THEN
                        l_target_unit_width := fnc_convert_dimension
                        (
                            l_width,
                            l_width_uom,
                            l_target_dimension_uom_code
                        );
                    END IF;
                    IF l_target_length IS NOT NULL THEN
                        l_target_unit_length := fnc_convert_dimension
                        (
                            l_target_length,
                            l_target_length_uom,
                            l_target_dimension_uom_code
                        );
                    END IF;
                END IF;
                BEGIN
                    apps.fnd_msg_pub.initialize;
                EXCEPTION
                    WHEN OTHERS THEN
                        raise_application_error
                        (
                            -20820,
                            'Unexpected Error in pcd_process_request: ' || SQLERRM,
                            TRUE
                        );
                END;
                l_target_attr_item_id := NULL;
                l_target_attr_api_org_id := NULL;
                l_target_attr_return_status := NULL;
                l_target_attr_msg_count := 0;
                l_target_attr_msg_data := NULL;
                l_target_attr_message := NULL;
                l_error_handler_message_list.delete;
                apps.ego_item_pub.process_item
                (
                    p_api_version => 1.0,
                    p_init_msg_list => c_api_true,
                    p_commit => c_api_false,
                    p_transaction_type => 'UPDATE',
                    p_inventory_item_id =>
                        NVL(l_target_item_id, l_master_item_id),
                    p_organization_id =>
                        r_target.ebs_organization_id,
                    p_eng_item_flag => l_eng_item_flag,
                    p_outside_operation_flag =>
                        l_outside_processing,
                    p_dimension_uom_code =>
                        l_target_dimension_uom_code,
                    p_unit_width =>
                        l_target_unit_width,
                    p_unit_length =>
                        l_target_unit_length,
                    p_list_price_per_unit =>
                        NVL
                        (
                            l_price_per_uom,
                            apps.fnd_api.g_miss_num
                        ),
                    p_attribute1 =>
                        NVL
                        (
                            l_pdr_number,
                            apps.fnd_api.g_miss_char
                        ),
                    p_attribute16 =>
                        CASE
                            WHEN l_percent_solids IS NULL
                                THEN apps.fnd_api.g_miss_char
                            ELSE
                                TO_CHAR
                                (
                                    l_percent_solids,
                                    'TM9',
                                    'NLS_NUMERIC_CHARACTERS=''.,'''
                                )
                        END,
                    p_attribute3 =>
                        NVL
                        (
                            l_construction,
                            apps.fnd_api.g_miss_char
                        ),
                    p_attribute7 =>
                        NVL
                        (
                            l_request.initiator,
                            apps.fnd_api.g_miss_char
                        ),
                    p_weight_uom_code =>
                        CASE
                            WHEN l_weight_per_gallon IS NOT NULL
                                THEN NULL
                            ELSE apps.fnd_api.g_miss_char
                        END,
                    p_unit_weight =>
                        CASE
                            WHEN l_weight_per_gallon IS NOT NULL
                                THEN NULL
                            ELSE apps.fnd_api.g_miss_num
                        END,
                    p_item_type =>
                        NVL
                        (
                            l_user_item_type_code,
                            apps.fnd_api.g_miss_char
                        ),
                    p_attribute15 =>
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
                    p_attribute9 =>
                        NVL
                        (
                            l_batch_size,
                            apps.fnd_api.g_miss_char
                        ),
                    p_shelf_life_code => fnc_shelf_life_control(r_target.request_org_id),
                    p_shelf_life_days =>
                        NVL
                        (
                            l_shelf_life_days,
                            apps.fnd_api.g_miss_num
                        ),
                    p_planner_code =>
                        NVL
                        (
                            l_planner,
                            apps.fnd_api.g_miss_char
                        ),
                    p_shippable_item_flag =>
                        NVL
                        (
                            l_shippable_item_flag,
                            apps.fnd_api.g_miss_char
                        ),
                    p_full_lead_time =>
                        CASE
                            WHEN l_item_type_code = 'RAW_MATERIAL_ITEM'
                            THEN
                                NVL
                                (
                                    l_lead_time_days,
                                    apps.fnd_api.g_miss_num
                                )
                            WHEN l_lead_time_days IS NOT NULL
                            THEN
                                NULL
                            ELSE
                                apps.fnd_api.g_miss_num
                        END,
                    p_item_number =>
                        l_ebs_item_number,
                    p_segment1 =>
                        l_item_segment1,
                    p_segment2 =>
                        l_item_segment2,
                    p_segment3 =>
                        l_item_segment3,
                    x_inventory_item_id =>
                        l_target_attr_item_id,
                    x_organization_id =>
                        l_target_attr_api_org_id,
                    x_return_status =>
                        l_target_attr_return_status,
                    x_msg_count =>
                        l_target_attr_msg_count,
                    x_msg_data =>
                        l_target_attr_msg_data
                );
                l_target_attr_message :=
                    fnc_get_api_messages
                    (
                        l_target_attr_msg_count,
                        l_target_attr_msg_data
                    );
                IF NVL(l_target_attr_return_status, c_return_error) <> c_return_success THEN
                    BEGIN
                        l_error_handler_message_list.delete;
                        apps.error_handler.get_message_list
                        (
                            x_message_list =>
                                l_error_handler_message_list
                        );
                        IF l_error_handler_message_list.count > 0 THEN
                            FOR i IN 1 .. l_error_handler_message_list.count
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
                            raise_application_error
                            (
                                -20825,
                                'Unexpected Error in pcd_process_request: ' || SQLERRM,
                                TRUE
                            );
                    END;
                    l_api_failure_status :=
                        NVL(l_target_attr_return_status, c_return_error);
                    l_api_failure_msg_count :=
                        NVL(l_target_attr_msg_count, 0);
                    l_api_failure_request_org_id :=
                        r_target.request_org_id;
                    l_api_failure_api_name :=
                        'EGO_ITEM_PUB.PROCESS_ITEM';
                    l_api_failure_process_name :=
                        'APPLY_TARGET_ATTRIBUTES';
                    l_api_failure_entity_id :=
                        r_target.ebs_organization_id;
                    dbms_lob.createtemporary
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
                        dbms_lob.substr
                        (
                            l_target_attr_message,
                            3000,
                            1
                        )
                    );
                    RAISE e_api_failure;
                END IF;
                pcd_insert_api_log
                (
                    p_execution_id => l_execution_id,
                    p_item_request_id => p_item_request_id,
                    p_request_org_id => r_target.request_org_id,
                    p_process_name => 'APPLY_TARGET_ATTRIBUTES',
                    p_api_name => 'EGO_ITEM_PUB.PROCESS_ITEM',
                    p_entity_type => 'ORGANIZATION',
                    p_entity_id => r_target.ebs_organization_id,
                    p_log_level => 'INFO',
                    p_process_status => 'SUCCESS',
                    p_api_return_status => l_target_attr_return_status,
                    p_api_message_count => l_target_attr_msg_count,
                    p_message_text => l_target_attr_message
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
                        ELSE TO_CHAR(l_target_unit_width) || ' ' || l_target_dimension_uom_code
                    END ||
                    ', TARGET_LENGTH=' ||
                    CASE
                        WHEN l_target_length IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_target_unit_length) || ' ' || l_target_dimension_uom_code
                    END ||
                    ', PRICE_PER_UOM=' ||
                    CASE
                        WHEN l_price_per_uom IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_price_per_uom)
                    END ||
                    ', LEAD_TIME_DAYS=' ||
                    CASE
                        WHEN l_lead_time_days IS NULL THEN 'NOT SENT'
                        WHEN l_item_type_code = 'RAW_MATERIAL_ITEM'
                            THEN TO_CHAR(l_lead_time_days) ||
                                 ' (ATTRIBUTE15 + FULL_LEAD_TIME)'
                        ELSE TO_CHAR(l_lead_time_days) ||
                             ' (ATTRIBUTE15 ONLY; FULL_LEAD_TIME CLEARED)'
                    END ||
                    ', BATCH_SIZE=' ||
                    CASE
                        WHEN l_batch_size IS NULL THEN 'NOT SENT'
                        ELSE l_batch_size ||
                             ' (ATTRIBUTE9 / AVERAGE CONTAINER SIZE)'
                    END ||
                    ', SHELF_LIFE_DAYS=' ||
                    CASE
                        WHEN l_shelf_life_days IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_shelf_life_days)
                    END ||
                    ', PLANNER=' ||
                    NVL(l_planner, 'NOT SENT') ||
                    ', SHIPPABLE_ITEM_FLAG=' ||
                    NVL(l_shippable_item_flag, 'NOT SENT') ||
                    ', PDR_NUMBER=' ||
                    NVL(l_pdr_number, 'NOT SENT') ||
                    ', PERCENT_SOLIDS=' ||
                    CASE
                        WHEN l_percent_solids IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_percent_solids)
                    END ||
                    ', CONSTRUCTION=' ||
                    NVL(l_construction, 'NOT SENT') ||
                    CASE
                        WHEN l_staged_construction IS NOT NULL
                            THEN ' (DIRECT STAGED VALUE)'
                        WHEN l_construction IS NOT NULL
                            THEN ' (DERIVED)'
                        ELSE NULL
                    END ||
                    ', INITIATOR=' ||
                    NVL(l_request.initiator, 'NOT SENT') ||
                    ', WEIGHT_PER_GALLON=' ||
                    CASE
                        WHEN l_weight_per_gallon IS NULL THEN 'NOT SENT'
                        ELSE TO_CHAR(l_weight_per_gallon) ||
                             ' (CONSTRUCTION DFF; PHYSICAL WEIGHT CLEARED)'
                    END
                );
            END IF;
            pcd_verify_attributes
            (
                r_target.request_org_id,
                NVL(l_target_item_id, l_master_item_id),
                r_target.ebs_organization_id,
                'TARGET',
                NULL,
                l_construction,
                l_selected_rules(r_target.request_org_id)
            );
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
            WHERE  request_org_id = 
                  r_target.request_org_id;
        END LOOP;
        pcd_apply_request_text_dff
        (
            p_item_request_id,
            x_message
        );
        FOR type_check IN (
            SELECT
                adinitreor.ebs_organization_id,
                mtsyitb.item_type
            FROM
                ops.adre_inv_item_request_org adinitreor,
                apps.mtl_system_items_kfv mtsyitkf,
                apps.mtl_system_items_b mtsyitb
            WHERE  mtsyitkf.organization_id(+)                    = adinitreor.ebs_organization_id
              AND  UPPER(TRIM(mtsyitkf.concatenated_segments(+))) = UPPER(TRIM(l_request.item_number))
              AND  mtsyitb.inventory_item_id(+)                   = mtsyitkf.inventory_item_id
              AND  mtsyitb.organization_id(+)                     = mtsyitkf.organization_id
              AND  adinitreor.item_request_id                     = p_item_request_id
        )
        LOOP
            IF type_check.item_type IS NULL OR type_check.item_type <> l_user_item_type_code THEN
                raise_application_error(-20830, 'Final Item Type differs from explicit configuration in organization ' ||
                    type_check.ebs_organization_id);
            END IF;
        END LOOP;
        pcd_assign_categories
        (
            p_item_request_id => p_item_request_id,
            p_user_id => l_context_user_id,
            p_resp_id => l_context_resp_id,
            p_resp_appl_id => l_context_resp_appl_id,
            p_commit_flag => 'N',
            x_return_status => l_category_return_status,
            x_message => l_category_message
        );
        pcd_append_text
        (
            x_message,
            dbms_lob.substr
            (
                l_category_message,
                3000,
                1
            )
        );
        IF l_category_return_status <> c_return_success THEN
            l_api_failure_status := NVL(l_category_return_status, c_return_error);
            l_api_failure_msg_count := 1;
            l_api_failure_request_org_id := NULL;
            l_api_failure_api_name := 'INV_ITEM_CATEGORY_PUB';
            l_api_failure_process_name := 'ASSIGN_CATEGORIES';
            l_api_failure_entity_id := p_item_request_id;
            dbms_lob.createtemporary
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
                dbms_lob.substr
                (
                    l_category_message,
                    3000,
                    1
                )
            );
            RAISE e_api_failure;
        END IF;
        x_return_status := c_return_success;
        UPDATE ops.adre_inv_item_request
        SET request_status = c_request_processed,
            ebs_submit_date = NVL
                                   (
                                       ebs_submit_date,
                                       SYSDATE
                                   ),
            api_return_status = c_return_success,
            api_message_count =
                NVL
                (
                    l_master_msg_count,
                    0
                ),
            api_message_text = x_message,
            api_processed_date = SYSDATE
        WHERE  item_request_id = p_item_request_id;
        pcd_append_text
        (
            x_message,
            'Item Request completed successfully.'
        );
        pcd_insert_api_log
        (
            p_execution_id => l_execution_id,
            p_item_request_id => p_item_request_id,
            p_request_org_id => NULL,
            p_process_name => 'SEND_TO_EBS',
            p_api_name => NULL,
            p_entity_type => 'ITEM_REQUEST',
            p_entity_id => p_item_request_id,
            p_log_level => 'INFO',
            p_process_status => 'SUCCESS',
            p_api_return_status => c_return_success,
            p_api_message_count => 0,
            p_message_text => x_message
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
                SET request_status = c_request_error,
                    api_return_status = x_return_status,
                    api_message_count = NVL(l_api_failure_msg_count, 1),
                    api_message_text = x_message,
                    api_processed_date = SYSDATE
                WHERE  item_request_id = p_item_request_id;
                IF l_api_failure_request_org_id IS NOT NULL THEN
                    UPDATE ops.adre_inv_item_request_org
                    SET assignment_status = c_assignment_error,
                        api_return_status = x_return_status,
                        api_message_count = NVL(l_api_failure_msg_count, 1),
                        api_message_text = x_message,
                        api_processed_date = SYSDATE
                    WHERE  request_org_id = l_api_failure_request_org_id;
                END IF;
                pcd_insert_api_log
                (
                    p_execution_id => l_execution_id,
                    p_item_request_id => p_item_request_id,
                    p_request_org_id => l_api_failure_request_org_id,
                    p_process_name => NVL(l_api_failure_process_name, 'SEND_TO_EBS'),
                    p_api_name => l_api_failure_api_name,
                    p_entity_type =>
                        CASE
                            WHEN l_api_failure_request_org_id IS NULL
                                THEN 'ITEM_REQUEST'
                            ELSE 'ORGANIZATION'
                        END,
                    p_entity_id => NVL(l_api_failure_entity_id, p_item_request_id),
                    p_log_level => 'ERROR',
                    p_process_status => 'ERROR',
                    p_api_return_status => x_return_status,
                    p_api_message_count => NVL(l_api_failure_msg_count, 1),
                    p_message_text => x_message
                );
                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error
                    (
                        -20835,
                        'Unexpected Error in pcd_process_request: ' || SQLERRM,
                        TRUE
                    );
            END;
        WHEN no_data_found THEN
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
                SET request_status = c_request_error,
                    api_return_status = c_return_error,
                    api_message_count = 1,
                    api_message_text = x_message,
                    api_processed_date = SYSDATE
                WHERE  item_request_id = p_item_request_id;
                pcd_insert_api_log
                (
                    p_execution_id => l_execution_id,
                    p_item_request_id => p_item_request_id,
                    p_request_org_id => NULL,
                    p_process_name => 'SEND_TO_EBS',
                    p_api_name => NULL,
                    p_entity_type => 'ITEM_REQUEST',
                    p_entity_id => p_item_request_id,
                    p_log_level => 'ERROR',
                    p_process_status => 'ERROR',
                    p_api_return_status => c_return_error,
                    p_api_message_count => 1,
                    p_message_text => x_message
                );
                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error
                    (
                        -20840,
                        'Unexpected Error in pcd_process_request: ' || SQLERRM,
                        TRUE
                    );
            END;
        WHEN OTHERS THEN
            l_error_text :=
                'Unexpected Item Request processing error. ITEM_REQUEST_ID=' ||
                p_item_request_id ||
                ', SQLERRM=' ||
                SQLERRM ||
                ', BACKTRACE=' ||
                dbms_utility.format_error_backtrace;
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
                SET request_status = c_request_error,
                    api_return_status = c_return_unexpected,
                    api_message_count = 1,
                    api_message_text = x_message,
                    api_processed_date = SYSDATE
                WHERE  item_request_id = p_item_request_id;
                pcd_insert_api_log
                (
                    p_execution_id => l_execution_id,
                    p_item_request_id => p_item_request_id,
                    p_request_org_id => NULL,
                    p_process_name => 'SEND_TO_EBS',
                    p_api_name => NULL,
                    p_entity_type => 'ITEM_REQUEST',
                    p_entity_id => p_item_request_id,
                    p_log_level => 'ERROR',
                    p_process_status => 'ERROR',
                    p_api_return_status => c_return_unexpected,
                    p_api_message_count => 1,
                    p_message_text => x_message
                );
                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error
                    (
                        -20845,
                        'Unexpected Error in pcd_process_request: ' || SQLERRM,
                        TRUE
                    );
            END;
            raise_application_error
            (
                -20850,
                'Unexpected Error in pcd_process_request: ' || SQLERRM,
                TRUE
            );
    END pcd_process_request;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_configure_item_type
    -- Purpose    : Configure or validate an EBS item type lookup for an application item type.
    -- Parameters:
    --   p_item_type_code IN VARCHAR2 - Application item type code to configure.
    --   p_ebs_meaning IN VARCHAR2 - EBS lookup meaning associated with the item type.
    --   p_create_missing_flag IN VARCHAR2 - Allows creation of the EBS lookup when configured to
    --     Y.
    --   p_user_id IN NUMBER - EBS user identifier; NULL invokes the existing context fallback.
    --   p_resp_id IN NUMBER - EBS responsibility identifier; NULL invokes the existing context
    --     fallback.
    --   p_resp_appl_id IN NUMBER - EBS responsibility application identifier; NULL uses the
    --     existing fallback.
    --   p_commit_flag IN VARCHAR2 - Controls whether the routine commits successful changes.
    --   x_return_status OUT VARCHAR2 - Success, error or unexpected status returned to the caller.
    --   x_message OUT CLOB - Detailed result or diagnostic text returned to the caller.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_configure_item_type
    (
        p_item_type_code IN VARCHAR2,
        p_ebs_meaning IN VARCHAR2,
        p_create_missing_flag IN VARCHAR2 DEFAULT 'N',
        p_user_id IN NUMBER DEFAULT NULL,
        p_resp_id IN NUMBER DEFAULT NULL,
        p_resp_appl_id IN NUMBER DEFAULT NULL,
        p_commit_flag IN VARCHAR2 DEFAULT 'N',
        x_return_status OUT VARCHAR2,
        x_message OUT CLOB
    )
    IS
        l_type_id        ops.adre_inv_item_type.item_type_id%TYPE;
        l_app_code       ops.adre_inv_item_type.item_type_code%TYPE;
        l_old_code       ops.adre_inv_item_type.ebs_item_type_code%TYPE;
        l_old_view       ops.adre_inv_item_type.ebs_view_application_id%TYPE;
        l_old_security   ops.adre_inv_item_type.ebs_security_group_id%TYPE;
        l_code           apps.fnd_lookup_values_vl.lookup_code%TYPE;
        l_meaning        apps.fnd_lookup_values_vl.meaning%TYPE;
        l_view_id        NUMBER;
        l_security_id    NUMBER;
        l_customization  VARCHAR2(1);
        l_count          PLS_INTEGER;
        l_rowid          VARCHAR2(100);
        l_user_id        NUMBER;
        l_application_id NUMBER;
        l_commit         VARCHAR2(1) := UPPER(NVL(p_commit_flag, 'N'));
        l_create         VARCHAR2(1) := UPPER(NVL(p_create_missing_flag, 'N'));
    BEGIN
        g_text_correction_flag := 'N';
        x_return_status := c_return_error;
        x_message := NULL;
        IF l_commit NOT IN ('Y', 'N') OR l_create NOT IN ('Y', 'N') THEN
            raise_application_error
            (
                -20855,
                'Commit/create flags must be Y or N.'
            );
        END IF;
        IF TRIM(p_ebs_meaning) IS NULL THEN
            raise_application_error
            (
                -20860,
                'EBS Item Type meaning is required.'
            );
        END IF;
        SELECT
            item_type_id,
            item_type_code,
            ebs_item_type_code,
            ebs_view_application_id,
            ebs_security_group_id
        INTO
            l_type_id,
            l_app_code,
            l_old_code,
            l_old_view,
            l_old_security
        FROM
            ops.adre_inv_item_type
        WHERE  item_type_code = UPPER(TRIM(p_item_type_code))
          AND  active_flag    = 'Y' FOR UPDATE NOWAIT;
        l_user_id := p_user_id;
        l_application_id := p_resp_appl_id;
        pcd_initialize_ebs_context
        (
            l_user_id,
            p_resp_id,
            l_application_id
        );
        SELECT
            view_application_id,
            security_group_id,
            customization_level
        INTO
            l_view_id,
            l_security_id,
            l_customization
        FROM
            apps.fnd_lookup_types_vl
        WHERE  lookup_type    = 'ITEM_TYPE'
          AND  application_id = g_inventory_application_id;
        SELECT
            COUNT(*),
            MIN(lookup_code),
            MIN(meaning)
        INTO
            l_count,
            l_code,
            l_meaning
        FROM
            apps.fnd_lookup_values_vl
        WHERE  lookup_type          = 'ITEM_TYPE'
          AND  view_application_id  = l_view_id
          AND  security_group_id    = l_security_id
          AND  UPPER(TRIM(meaning)) = UPPER(TRIM(p_ebs_meaning));
        IF l_count > 1 THEN
            raise_application_error
            (
                -20865,
                'Multiple EBS values have the requested Item Type meaning.'
            );
        ELSIF l_count = 0 THEN
            IF l_create <> 'Y' THEN
                raise_application_error
                (
                    -20870,
                    'Requested EBS Item Type is absent; creation was not enabled.'
                );
            END IF;
            IF l_customization IS NULL OR l_customization <> 'U' THEN
                raise_application_error
                (
                    -20875,
                    'Lookup is not user-maintainable; no lookup value was inserted.'
                );
            END IF;
            IF LENGTHB(l_app_code) > 30 THEN
                raise_application_error
                (
                    -20880,
                    'Application type code is too long for an EBS lookup code.'
                );
            END IF;
            l_code := l_app_code;
            l_meaning := TRIM(p_ebs_meaning);
            SELECT
                COUNT(*)
            INTO
                l_count
            FROM
                apps.fnd_lookup_values_vl
            WHERE  lookup_type         = 'ITEM_TYPE'
              AND  view_application_id = l_view_id
              AND  security_group_id   = l_security_id
              AND  lookup_code         = l_code;
            IF l_count <> 0 THEN
                raise_application_error
                (
                    -20885,
                    'Generated lookup code already has a different meaning.'
                );
            END IF;
            apps.fnd_lookup_values_pkg.insert_row
            (
                x_rowid => l_rowid,
                x_lookup_type => 'ITEM_TYPE',
                x_security_group_id => l_security_id,
                x_view_application_id => l_view_id,
                x_lookup_code => l_code,
                x_tag => NULL,
                x_attribute_category => NULL,
                x_attribute1 => NULL,
                x_attribute2 => NULL,
                x_attribute3 => NULL,
                x_attribute4 => NULL,
                x_enabled_flag => 'Y',
                x_start_date_active => TRUNC(SYSDATE),
                x_end_date_active => NULL,
                x_territory_code => NULL,
                x_attribute5 => NULL,
                x_attribute6 => NULL,
                x_attribute7 => NULL,
                x_attribute8 => NULL,
                x_attribute9 => NULL,
                x_attribute10 => NULL,
                x_attribute11 => NULL,
                x_attribute12 => NULL,
                x_attribute13 => NULL,
                x_attribute14 => NULL,
                x_attribute15 => NULL,
                x_meaning => l_meaning,
                x_description => l_meaning,
                x_creation_date => SYSDATE,
                x_created_by => l_user_id,
                x_last_update_date => SYSDATE,
                x_last_updated_by => l_user_id,
                x_last_update_login => apps.fnd_global.login_id
            );
            pcd_append_text
            (
                x_message,
                'EBS lookup value created: ' || l_code || ' / ' || l_meaning
            );
        ELSE
            pcd_append_text
            (
                x_message,
                'Existing EBS lookup value found: ' || l_code || ' / ' || l_meaning
            );
        END IF;
        IF l_old_code IS NOT NULL OR l_old_view IS NOT NULL OR l_old_security IS NOT NULL THEN
            IF l_old_code IS NULL OR l_old_view IS NULL OR l_old_security IS NULL
               OR l_old_code <> l_code OR l_old_view <> l_view_id OR l_old_security <> l_security_id THEN
                raise_application_error
                (
                    -20890,
                    'Existing application mapping differs; no automatic replacement.'
                );
            END IF;
        ELSE
            UPDATE ops.adre_inv_item_type
            SET ebs_item_type_code = l_code,
                ebs_view_application_id = l_view_id,
                ebs_security_group_id = l_security_id,
                last_updated_by = SUBSTR(NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), 1, 100),
                last_update_date = SYSDATE,
                record_version_number = NVL(record_version_number, 0) + 1
            WHERE  item_type_id = l_type_id;
        END IF;
        l_code := fnc_resolve_item_type
        (
            l_type_id
        );
        pcd_append_text(x_message, 'Mapping verified: ' || l_app_code || ' -> ' || l_code ||
            ', VIEW_APPLICATION_ID=' || l_view_id || ', SECURITY_GROUP_ID=' || l_security_id);
        x_return_status := c_return_success;
        IF l_commit = 'Y' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        ROLLBACK;
        x_return_status := c_return_error;
        pcd_append_text
        (
            x_message,
            'Configuration rolled back: ' || SQLERRM
        );
            raise_application_error
            (
                -20895,
                'Unexpected Error in pcd_configure_item_type: ' || SQLERRM,
                TRUE
            );
    END pcd_configure_item_type;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_correct_item_type
    -- Purpose    : Correct and verify the EBS item type for an already staged request.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_user_id IN NUMBER - EBS user identifier; NULL invokes the existing context fallback.
    --   p_resp_id IN NUMBER - EBS responsibility identifier; NULL invokes the existing context
    --     fallback.
    --   p_resp_appl_id IN NUMBER - EBS responsibility application identifier; NULL uses the
    --     existing fallback.
    --   p_commit_flag IN VARCHAR2 - Controls whether the routine commits successful changes.
    --   x_return_status OUT VARCHAR2 - Success, error or unexpected status returned to the caller.
    --   x_message OUT CLOB - Detailed result or diagnostic text returned to the caller.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_correct_item_type
    (
        p_item_request_id IN NUMBER,
        p_user_id IN NUMBER DEFAULT NULL,
        p_resp_id IN NUMBER DEFAULT NULL,
        p_resp_appl_id IN NUMBER DEFAULT NULL,
        p_commit_flag IN VARCHAR2 DEFAULT 'N',
        x_return_status OUT VARCHAR2,
        x_message OUT CLOB
    )
    IS
        l_item_number    ops.adre_inv_item_request.item_number%TYPE;
        l_type_id        ops.adre_inv_item_type.item_type_id%TYPE;
        l_request_status ops.adre_inv_item_request.request_status%TYPE;
        l_code           apps.mtl_system_items_b.item_type%TYPE;
        l_item_id        NUMBER;
        l_shared_item_id NUMBER;
        l_status         VARCHAR2(30);
        l_before_type    apps.mtl_system_items_b.item_type%TYPE;
        l_after_type     apps.mtl_system_items_b.item_type%TYPE;
        l_api_message    CLOB;
        l_execution_id   VARCHAR2(100) := 'ADRE-TYPE-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') || '-' || p_item_request_id;
        l_count          PLS_INTEGER;
        l_org_count      PLS_INTEGER;
        l_master_count   PLS_INTEGER;
        l_commit         VARCHAR2(1) := UPPER(NVL(p_commit_flag, 'N'));
        l_known_request  BOOLEAN := FALSE;
    BEGIN
        g_text_correction_flag := 'N';
        x_return_status := c_return_error;
        x_message := NULL;
        IF l_commit NOT IN ('Y', 'N') THEN
            raise_application_error
            (
                -20900,
                'Commit flag must be Y or N.'
            );
        END IF;
        SELECT
            item_number,
            item_type_id,
            request_status
        INTO
            l_item_number,
            l_type_id,
            l_request_status
        FROM
            ops.adre_inv_item_request
        WHERE  item_request_id = p_item_request_id FOR UPDATE NOWAIT;
        l_known_request := TRUE;
        IF l_request_status IS NULL OR l_request_status <> c_request_processed THEN
            raise_application_error
            (
                -20905,
                'Item Type correction requires a PROCESSED request.'
            );
        END IF;
        l_code := fnc_resolve_item_type
        (
            l_type_id,
            p_item_request_id
        );
        SELECT
            COUNT(*),
            COUNT(DISTINCT ebs_organization_id),
            SUM(CASE WHEN organization_role = 'MASTER' THEN 1 ELSE 0 END)
        INTO
            l_org_count,
            l_count,
            l_master_count
        FROM
            ops.adre_inv_item_request_org
        WHERE  item_request_id = p_item_request_id;
        IF l_org_count = 0 OR l_count <> l_org_count OR NVL(l_master_count, 0) <> 1 THEN
            raise_application_error
            (
                -20910,
                'Request organizations are missing, duplicated, or have no unique MASTER.'
            );
        END IF;
        FOR r IN (
            SELECT
                ebs_organization_id,
                organization_role,
                assignment_status
            FROM
                ops.adre_inv_item_request_org
            WHERE  item_request_id = p_item_request_id
        )
        LOOP
            IF r.organization_role IS NULL OR r.organization_role NOT IN ('MASTER', 'TARGET')
               OR r.assignment_status IS NULL OR r.assignment_status <> c_assignment_processed THEN
                raise_application_error
                (
                    -20915,
                    'Only PROCESSED MASTER/TARGET organizations can be corrected.'
                );
            END IF;
            IF NOT fnc_item_exists(l_item_number, r.ebs_organization_id, l_item_id, l_status) THEN
                raise_application_error
                (
                    -20920,
                    'Existing EBS item is missing in a request organization.'
                );
            END IF;
            IF l_shared_item_id IS NOT NULL AND l_shared_item_id <> l_item_id THEN
                raise_application_error
                (
                    -20925,
                    'Organizations do not share the same EBS inventory item ID.'
                );
            END IF;
            l_shared_item_id := l_item_id;
        END LOOP;
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = l_shared_item_id;
        IF l_count <> l_org_count THEN
            raise_application_error
            (
                -20930,
                'Item has additional EBS organizations; inspect before correcting.'
            );
        END IF;
        pcd_initialize_ebs_context(p_user_id, p_resp_id,
                                  p_resp_appl_id);
        FOR r IN (
            SELECT
                adinitreor.request_org_id,
                adinitreor.ebs_organization_id,
                adinitreor.organization_role,
                mtlpar.organization_code
            FROM
                ops.adre_inv_item_request_org adinitreor,
                apps.mtl_parameters mtlpar
            WHERE  mtlpar.organization_id     = adinitreor.ebs_organization_id
              AND  adinitreor.item_request_id = p_item_request_id
            ORDER BY
                CASE adinitreor.organization_role WHEN 'MASTER' THEN 0 ELSE 1 END,
                mtlpar.organization_code
        )
        LOOP
            SELECT
                item_type
            INTO
                l_before_type
            FROM
                apps.mtl_system_items_b
            WHERE  inventory_item_id = l_shared_item_id
              AND  organization_id   = r.ebs_organization_id;
            pcd_apply_item_type
            (
                l_shared_item_id,
                r.ebs_organization_id,
                l_code,
                l_api_message
            );
            pcd_append_text
            (
                x_message,
                dbms_lob.substr(l_api_message, 3000, 1)
            );
            SELECT
                item_type
            INTO
                l_after_type
            FROM
                apps.mtl_system_items_b
            WHERE  inventory_item_id = l_shared_item_id
              AND  organization_id   = r.ebs_organization_id;
            IF l_after_type IS NULL OR l_after_type <> l_code THEN
                raise_application_error
                (
                    -20935,
                    'EBS Item Type postcondition failed in ' || r.organization_code
                );
            END IF;
            l_api_message := TO_CLOB('ITEM=' || l_item_number || ', ORG=' || r.organization_code ||
                ', BEFORE=' || NVL(l_before_type, 'NULL') || ', AFTER=' || l_after_type);
            pcd_append_text
            (
                x_message,
                dbms_lob.substr(l_api_message, 2000, 1)
            );
            pcd_insert_api_log(l_execution_id, p_item_request_id, r.request_org_id,
                'CORRECT_ITEM_TYPE', 'EGO_ITEM_PUB.PROCESS_ITEM', 'ORGANIZATION',
                r.ebs_organization_id, 'INFO', 'SUCCESS', c_return_success, 0, l_api_message);
        END LOOP;
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            apps.mtl_system_items_b
        WHERE  inventory_item_id = l_shared_item_id
          AND  item_type         = l_code;
        IF l_count <> l_org_count THEN
            raise_application_error
            (
                -20940,
                'Final Item Type verification failed across organizations.'
            );
        END IF;
        x_return_status := c_return_success;
        pcd_append_text
        (
            x_message,
            'Item Type correction verified. No other business attributes were explicitly submitted.'
        );
        IF l_commit = 'Y' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        pcd_append_text
        (
            x_message,
            'Correction rolled back: ' || SQLERRM
        );
        ROLLBACK;
        x_return_status := c_return_error;
        IF l_known_request AND l_commit = 'Y' THEN
            BEGIN
                pcd_insert_api_log(l_execution_id, p_item_request_id, NULL,
                    'CORRECT_ITEM_TYPE', 'EGO_ITEM_PUB.PROCESS_ITEM', 'ITEM_REQUEST',
                    p_item_request_id, 'ERROR', 'ERROR', c_return_error, 0, x_message);
                COMMIT;
            EXCEPTION
                WHEN OTHERS THEN
                pcd_append_text
                (
                    x_message,
                    'Error log could not be persisted: ' || SQLERRM
                );
                    raise_application_error
                    (
                        -20945,
                        'Unexpected Error in pcd_correct_item_type: ' || SQLERRM,
                        TRUE
                    );
            END;
        END IF;
            raise_application_error
            (
                -20950,
                'Unexpected Error in pcd_correct_item_type: ' || SQLERRM,
                TRUE
            );
    END pcd_correct_item_type;

    -- ---------------------------------------------------------------------
    -- Routine    : pcd_correct_text_dff
    -- Purpose    : Reapply and verify staged text flexfield values for a request.
    -- Parameters:
    --   p_item_request_id IN NUMBER - OPS staged request being processed or validated.
    --   p_user_id IN NUMBER - EBS user identifier; NULL invokes the existing context fallback.
    --   p_resp_id IN NUMBER - EBS responsibility identifier; NULL invokes the existing context
    --     fallback.
    --   p_resp_appl_id IN NUMBER - EBS responsibility application identifier; NULL uses the
    --     existing fallback.
    --   p_commit_flag IN VARCHAR2 - Controls whether the routine commits successful changes.
    --   x_return_status OUT VARCHAR2 - Success, error or unexpected status returned to the caller.
    --   x_message OUT CLOB - Detailed result or diagnostic text returned to the caller.
    -- ---------------------------------------------------------------------
    PROCEDURE pcd_correct_text_dff
    (
        p_item_request_id IN NUMBER,
        p_user_id IN NUMBER DEFAULT NULL,
        p_resp_id IN NUMBER DEFAULT NULL,
        p_resp_appl_id IN NUMBER DEFAULT NULL,
        p_commit_flag IN VARCHAR2 DEFAULT 'N',
        x_return_status OUT VARCHAR2,
        x_message OUT CLOB
    )
    IS
        l_status ops.adre_inv_item_request.request_status%TYPE;
        l_commit VARCHAR2(1) := UPPER(NVL(p_commit_flag, 'N'));
        l_count  PLS_INTEGER;
    BEGIN
        g_text_correction_flag := 'Y';
        x_return_status := c_return_error;
        x_message := NULL;
        IF l_commit NOT IN ('Y', 'N') THEN
            raise_application_error
            (
                -20955,
                'Commit flag must be Y or N.'
            );
        END IF;
        SELECT
            request_status
        INTO
            l_status
        FROM
            ops.adre_inv_item_request
        WHERE  item_request_id = p_item_request_id FOR UPDATE NOWAIT;
        IF NVL(l_status, '?') <> c_request_processed THEN
            raise_application_error
            (
                -20960,
                'Text correction requires a PROCESSED request.'
            );
        END IF;
        SELECT
            COUNT(*)
        INTO
            l_count
        FROM
            (
                SELECT
                    adinitatva.*
                FROM
                    ops.adre_inv_item_attr_value adinitatva,
                    ops.adre_inv_item_request_org adinitreor,
                    ops.adre_inv_item_request adinitre,
                    ops.adre_inv_item_type adinitty,
                    ops.adre_inv_item_attribute adinitat
                WHERE  adinitreor.request_org_id   = adinitatva.request_org_id
                  AND  adinitre.item_request_id    = adinitreor.item_request_id
                  AND  adinitty.item_type_id       = adinitre.item_type_id
                  AND  adinitty.active_flag        = 'Y'
                  AND  adinitat.item_attribute_id  = adinitatva.item_attribute_id
                  AND  adinitat.active_flag        = 'Y'
                  AND  (adinitatva.value_status    = 'READY'
                        OR (g_text_correction_flag = 'Y'
                  AND  adinitatva.value_status     = 'PROCESSED'
                  AND  adinitat.attribute_code     IN ('TSR_NUMBER', 'CUSTOMER')))
                  AND  EXISTS
                    (
                        SELECT
                            1
                        FROM
                            ops.adre_inv_item_type_attr adinittyat
                        WHERE  adinittyat.item_type_id       = adinitre.item_type_id
                          AND  adinittyat.item_attribute_id  = adinitatva.item_attribute_id
                          AND  adinittyat.active_flag        = 'Y'
                          AND  adinittyat.organization_scope IN (adinitreor.organization_role, 'BOTH')
                    )
            )
            av,
            ops.adre_inv_item_attribute adinitat,
            ops.adre_inv_item_request_org adinitreor
        WHERE  adinitat.item_attribute_id = av.item_attribute_id
          AND  adinitreor.request_org_id  = av.request_org_id
          AND  adinitreor.item_request_id = p_item_request_id
          AND  adinitat.attribute_code    IN ('TSR_NUMBER', 'CUSTOMER')
          AND  av.attribute_value    IS NOT NULL;
        IF l_count = 0 THEN
            raise_application_error
            (
                -20965,
                'No explicit TSR/Customer input to correct.'
            );
        END IF;
        pcd_initialize_ebs_context(p_user_id, p_resp_id,
                                  p_resp_appl_id);
        pcd_validate_attribute_inputs(p_item_request_id);
        pcd_apply_request_text_dff
        (
            p_item_request_id,
            x_message
        );
        g_text_correction_flag := 'N';
        x_return_status := c_return_success;
        pcd_append_text
        (
            x_message,
            'Explicit TSR/Customer inputs verified in EBS. No item was recreated.'
        );
        IF l_commit = 'Y' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        g_text_correction_flag := 'N';
        pcd_append_text
        (
            x_message,
            'Text correction rolled back: ' || SQLERRM
        );
        ROLLBACK;
        x_return_status := c_return_error;
            raise_application_error
            (
                -20970,
                'Unexpected Error in pcd_correct_text_dff: ' || SQLERRM,
                TRUE
            );
    END pcd_correct_text_dff;

    -- ---------------------------------------------------------------------
    -- Routine    : fnc_release_version
    -- Purpose    : Report the release identifier of this package body.
    -- Parameters:
    --   None.
    -- Returns   : VARCHAR2 - Package release identifier.
    -- ---------------------------------------------------------------------
    FUNCTION fnc_release_version
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN 'V34';
    EXCEPTION
        WHEN OTHERS THEN
            pcd_write_log
            (
                'F_RELEASE_VERSION',
                SQLERRM
            );
            raise_application_error
            (
                -20975,
                'Unexpected Error in fnc_release_version: ' || SQLERRM,
                TRUE
            );
    END fnc_release_version;

    -- ---------------------------------------------------------------------
    -- Routine    : f_release_version
    -- Purpose    : Provide the legacy wrapper for the release identifier function.
    -- Parameters:
    --   None.
    -- Returns   : VARCHAR2 - Package release identifier from the wrapper.
    -- ---------------------------------------------------------------------
    FUNCTION f_release_version
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN fnc_release_version;
    END f_release_version;


END adre_create_inv_item;
/
