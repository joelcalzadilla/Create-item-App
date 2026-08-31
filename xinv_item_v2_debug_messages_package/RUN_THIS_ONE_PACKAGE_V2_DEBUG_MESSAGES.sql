/* ============================================================
   AR Global - XINV_ITEM_API_PKG_V2
   Purpose:
   - V2 package. One APEX staging row can process one item.
   - This package contains the TWO EBS item API operations in one package file:
       CALL #1: create/verify the Master Item in MASTER_ORG_CODE, for example MAS
       CALL #2: create/verify the same item in TARGET_ORG_CODE, for example GRI
   - It uses different templates:
       MASTER_TEMPLATE_NAME for MAS, optional
       TARGET_TEMPLATE_NAME for GRI
   - DEBUG_MESSAGES version captures x_msg_data and FND message stack

   Compile owner: APPS
   Custom table owner expected by this script: OPS
   ============================================================ */

CREATE OR REPLACE PACKAGE apps.xinv_item_api_pkg_v2 AS
/******************************************************************************
AR Global.
NAME:     xinv_item_api_pkg_v2
PURPOSE:  V2 package used by the AR Global APEX item creation process.
          One staging row in OPS.XINV_ITEM_CREATION_STG_V2 performs both steps:
          1) create or verify the item in the master organization
          2) create or verify the same item in the target organization, normally GRI

REVIEWS:
Version        Date        Author           Description
---------  ----------  ---------------  ------------------------------------
1.0        21.07.2026  JCALZADILLA      First version
******************************************************************************/

    PROCEDURE pcd_call_item_api (
        p_item_creation_stg_id IN  NUMBER,
        p_validate_only_flag   IN  VARCHAR2 DEFAULT NULL,
        p_user_id              IN  NUMBER   DEFAULT NULL,
        p_resp_id              IN  NUMBER   DEFAULT NULL,
        p_resp_appl_id         IN  NUMBER   DEFAULT NULL,
        p_commit_flag          IN  VARCHAR2 DEFAULT 'Y',
        x_return_status        OUT VARCHAR2,
        x_message              OUT CLOB
    );

    PROCEDURE pcd_process_staging (
        p_request_status        IN  VARCHAR2 DEFAULT 'SUBMITTED',
        p_request_number        IN  VARCHAR2 DEFAULT NULL,
        p_max_rows              IN  NUMBER   DEFAULT NULL,
        p_validate_only_flag    IN  VARCHAR2 DEFAULT NULL,
        p_user_id               IN  NUMBER   DEFAULT NULL,
        p_resp_id               IN  NUMBER   DEFAULT NULL,
        p_resp_appl_id          IN  NUMBER   DEFAULT NULL,
        p_commit_each_row_flag  IN  VARCHAR2 DEFAULT 'Y',
        x_total_count           OUT NUMBER,
        x_success_count         OUT NUMBER,
        x_error_count           OUT NUMBER,
        x_message               OUT CLOB
    );

END xinv_item_api_pkg_v2;
/
SHOW ERRORS PACKAGE apps.xinv_item_api_pkg_v2

CREATE OR REPLACE PACKAGE BODY apps.xinv_item_api_pkg_v2 AS
/******************************************************************************
AR Global.
NAME:     xinv_item_api_pkg_v2
PURPOSE:  Package body for the AR Global APEX item creation process.
          The key procedure, PCD_CALL_ITEM_API, contains the two required calls:
          CALL #1 creates/verifies the item in MAS using optional MASTER_TEMPLATE_NAME.
          CALL #2 creates/verifies the same item in GRI using TARGET_TEMPLATE_NAME.

REVIEWS:
Version        Date        Author           Description
---------  ----------  ---------------  ------------------------------------
1.0        21.07.2026  JCALZADILLA      First version
******************************************************************************/

    c_application_code   CONSTANT VARCHAR2(30) := 'XINV';

    c_status_draft       CONSTANT VARCHAR2(30) := 'DRAFT';
    c_status_validated   CONSTANT VARCHAR2(30) := 'VALIDATED';
    c_status_submitted   CONSTANT VARCHAR2(30) := 'SUBMITTED';
    c_status_processed   CONSTANT VARCHAR2(30) := 'PROCESSED';
    c_status_error       CONSTANT VARCHAR2(30) := 'ERROR';

    c_api_true           CONSTANT VARCHAR2(1)  := 'T';
    c_api_false          CONSTANT VARCHAR2(1)  := 'F';
    c_return_success     CONSTANT VARCHAR2(1)  := 'S';
    c_return_error       CONSTANT VARCHAR2(1)  := 'E';
    c_return_unexpected  CONSTANT VARCHAR2(1)  := 'U';
    c_missing_char       CONSTANT VARCHAR2(1)  := CHR(0);
    c_transaction_create CONSTANT VARCHAR2(20) := 'CREATE';
    c_transaction_update CONSTANT VARCHAR2(20) := 'UPDATE';

    g_user_name          VARCHAR2(100) := 'CWILLS';
    g_application_name   VARCHAR2(100) := 'Inventory';
    g_responsibility_key VARCHAR2(100) := 'INVENTORY';
    g_user_id            NUMBER := NULL;
    g_resp_id            NUMBER := NULL;
    g_application_id     NUMBER := NULL;

    PROCEDURE set_env IS
    BEGIN
        BEGIN
            SELECT user_id
              INTO g_user_id
              FROM apps.fnd_user
             WHERE user_name = g_user_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                g_user_id := NULL;
        END;

        BEGIN
            SELECT application_id
              INTO g_application_id
              FROM apps.fnd_application_vl
             WHERE application_name = g_application_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                g_application_id := NULL;
        END;

        BEGIN
            SELECT responsibility_id
              INTO g_resp_id
              FROM apps.fnd_responsibility_vl
             WHERE responsibility_key = g_responsibility_key;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                g_resp_id := NULL;
        END;
    END set_env;

    PROCEDURE pcd_write_log (
        p_business_process IN VARCHAR2,
        p_message          IN VARCHAR2
    ) IS
    BEGIN
        EXECUTE IMMEDIATE
            'BEGIN ops.pkg_log.sp_insert_message(' ||
            'p_co_aplication => :1, ' ||
            'p_tx_business_process => :2, ' ||
            'p_tx_message => :3); END;'
        USING c_application_code,
              SUBSTR(p_business_process, 1, 240),
              SUBSTR(p_message, 1, 3900);
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END pcd_write_log;

    PROCEDURE pcd_append_text (
        io_clob IN OUT NOCOPY CLOB,
        p_text  IN            VARCHAR2
    ) IS
    BEGIN
        IF io_clob IS NULL THEN
            DBMS_LOB.CREATETEMPORARY(io_clob, TRUE);
        END IF;

        DBMS_LOB.APPEND(io_clob, TO_CLOB(NVL(p_text, '') || CHR(10)));
    END pcd_append_text;

    FUNCTION f_get_session_user
        RETURN VARCHAR2
    IS
    BEGIN
        RETURN NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);
    END f_get_session_user;

    FUNCTION f_optional_char (
        p_value IN VARCHAR2
    ) RETURN VARCHAR2
    IS
    BEGIN
        RETURN NVL(p_value, c_missing_char);
    END f_optional_char;

    FUNCTION f_yes_no (
        p_value IN VARCHAR2
    ) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN c_missing_char;
        END IF;

        IF UPPER(TRIM(p_value)) IN ('Y', 'YES', 'TRUE', '1') THEN
            RETURN 'Y';
        ELSIF UPPER(TRIM(p_value)) IN ('N', 'NO', 'FALSE', '0') THEN
            RETURN 'N';
        ELSE
            RETURN c_missing_char;
        END IF;
    END f_yes_no;

    FUNCTION f_transaction_type (
        p_value IN VARCHAR2
    ) RETURN VARCHAR2
    IS
    BEGIN
        IF UPPER(TRIM(NVL(p_value, c_transaction_create))) = c_transaction_update THEN
            RETURN c_transaction_update;
        ELSE
            RETURN c_transaction_create;
        END IF;
    END f_transaction_type;

    FUNCTION f_get_api_messages (
        p_msg_count IN NUMBER,
        p_msg_data  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        l_message_text     CLOB;
        l_fnd_message      VARCHAR2(4000);
        l_msg_index_out    NUMBER;
        l_stack_count      NUMBER;
        l_stack_data       VARCHAR2(4000);
    BEGIN
        DBMS_LOB.CREATETEMPORARY(l_message_text, TRUE);

        IF p_msg_data IS NOT NULL THEN
            pcd_append_text(l_message_text, 'API message data: ' || p_msg_data);
        END IF;

        BEGIN
            apps.fnd_msg_pub.count_and_get(
                p_encoded => apps.fnd_api.g_false,
                p_count   => l_stack_count,
                p_data    => l_stack_data
            );

            IF l_stack_data IS NOT NULL THEN
                pcd_append_text(l_message_text, 'FND stack data: ' || l_stack_data);
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                pcd_append_text(l_message_text, 'Could not call FND_MSG_PUB.COUNT_AND_GET: ' || SQLERRM);
        END;

        IF NVL(p_msg_count, 0) > 0 THEN
            FOR i IN 1 .. p_msg_count LOOP
                BEGIN
                    apps.fnd_msg_pub.get(
                        p_msg_index     => i,
                        p_encoded       => apps.fnd_api.g_false,
                        p_data          => l_fnd_message,
                        p_msg_index_out => l_msg_index_out
                    );

                    IF l_fnd_message IS NOT NULL THEN
                        pcd_append_text(l_message_text, 'FND message ' || i || ': ' || l_fnd_message);
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        pcd_append_text(l_message_text, 'Could not read FND message ' || i || ': ' || SQLERRM);
                END;
            END LOOP;
        END IF;

        IF DBMS_LOB.GETLENGTH(l_message_text) = 0 THEN
            pcd_append_text(l_message_text, 'No detailed API message was returned. API message count = ' || NVL(TO_CHAR(p_msg_count), '0'));
        END IF;

        RETURN l_message_text;
    END f_get_api_messages;

    PROCEDURE pcd_initialize_ebs_context (
        p_user_id      IN NUMBER,
        p_resp_id      IN NUMBER,
        p_resp_appl_id IN NUMBER
    ) IS
    BEGIN
        IF p_user_id IS NOT NULL
           AND p_resp_id IS NOT NULL
           AND p_resp_appl_id IS NOT NULL THEN

            pcd_write_log(
                'PCD_INITIALIZE_EBS_CONTEXT',
                'Initializing EBS context. USER_ID=' || p_user_id ||
                ', RESP_ID=' || p_resp_id ||
                ', RESP_APPL_ID=' || p_resp_appl_id
            );

            apps.fnd_global.apps_initialize(
                user_id      => p_user_id,
                resp_id      => p_resp_id,
                resp_appl_id => p_resp_appl_id
            );

            BEGIN
                apps.mo_global.init('INV');
            EXCEPTION
                WHEN OTHERS THEN
                    pcd_write_log('PCD_INITIALIZE_EBS_CONTEXT', 'MO_GLOBAL.INIT failed or was not required. Error: ' || SQLERRM);
            END;
        ELSE
            pcd_write_log(
                'PCD_INITIALIZE_EBS_CONTEXT',
                'EBS context initialization skipped because one or more context values are missing.'
            );
        END IF;
    END pcd_initialize_ebs_context;

    FUNCTION f_item_exists (
        p_item_number       IN  VARCHAR2,
        p_organization_code IN  VARCHAR2,
        x_inventory_item_id OUT NUMBER,
        x_organization_id   OUT NUMBER,
        x_item_status_code  OUT VARCHAR2
    ) RETURN BOOLEAN
    IS
    BEGIN
        SELECT msik.inventory_item_id,
               msik.organization_id,
               msi.inventory_item_status_code
          INTO x_inventory_item_id,
               x_organization_id,
               x_item_status_code
          FROM apps.mtl_system_items_kfv msik
          JOIN apps.mtl_system_items_b msi
            ON msi.inventory_item_id = msik.inventory_item_id
           AND msi.organization_id   = msik.organization_id
          JOIN apps.mtl_parameters mp
            ON mp.organization_id = msik.organization_id
         WHERE UPPER(TRIM(msik.concatenated_segments)) = UPPER(TRIM(p_item_number))
           AND UPPER(TRIM(mp.organization_code)) = UPPER(TRIM(p_organization_code))
           AND ROWNUM = 1;

        RETURN TRUE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            x_inventory_item_id := NULL;
            x_organization_id   := NULL;
            x_item_status_code  := NULL;
            RETURN FALSE;
    END f_item_exists;

    PROCEDURE pcd_validate_staging_row (
        p_stg IN ops.xinv_item_creation_stg_v2%ROWTYPE
    ) IS
    BEGIN
        IF p_stg.item_number IS NULL THEN
            RAISE_APPLICATION_ERROR(-20001, 'Item number is required before calling APPS.EGO_ITEM_PUB.PROCESS_ITEM.');
        END IF;

        IF p_stg.item_description IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Item description is required before calling APPS.EGO_ITEM_PUB.PROCESS_ITEM.');
        END IF;

        IF p_stg.primary_uom_code IS NULL THEN
            RAISE_APPLICATION_ERROR(-20003, 'Primary UOM code is required before calling APPS.EGO_ITEM_PUB.PROCESS_ITEM.');
        END IF;

        IF p_stg.master_org_code IS NULL THEN
            RAISE_APPLICATION_ERROR(-20004, 'Master organization code is required.');
        END IF;

        IF p_stg.target_org_code IS NOT NULL AND p_stg.target_template_name IS NULL THEN
            RAISE_APPLICATION_ERROR(-20006, 'Target template name is required when target organization code is provided.');
        END IF;
    END pcd_validate_staging_row;

    PROCEDURE pcd_call_item_api (
        p_item_creation_stg_id IN  NUMBER,
        p_validate_only_flag   IN  VARCHAR2 DEFAULT NULL,
        p_user_id              IN  NUMBER   DEFAULT NULL,
        p_resp_id              IN  NUMBER   DEFAULT NULL,
        p_resp_appl_id         IN  NUMBER   DEFAULT NULL,
        p_commit_flag          IN  VARCHAR2 DEFAULT 'Y',
        x_return_status        OUT VARCHAR2,
        x_message              OUT CLOB
    )
    IS
        l_stg                     ops.xinv_item_creation_stg_v2%ROWTYPE;
        l_validate_only_flag      VARCHAR2(1);
        l_commit_flag             VARCHAR2(1);
        l_transaction_type        VARCHAR2(30);
        l_new_request_status      VARCHAR2(30);
        l_session_user            VARCHAR2(100);
        l_session_login           VARCHAR2(100);
        l_error_text              VARCHAR2(4000);
        l_error_clob              CLOB;
        l_overall_message         CLOB;

        l_master_exists           BOOLEAN;
        l_target_exists           BOOLEAN;
        l_master_item_id          NUMBER;
        l_master_org_id           NUMBER;
        l_master_status_code      VARCHAR2(30);
        l_target_item_id          NUMBER;
        l_target_org_id           NUMBER;
        l_target_status_code      VARCHAR2(30);

        l_master_return_status    VARCHAR2(1);
        l_master_msg_count        NUMBER;
        l_master_msg_data         VARCHAR2(4000);
        l_master_message          CLOB;
        l_target_return_status    VARCHAR2(1);
        l_target_msg_count        NUMBER;
        l_target_msg_data         VARCHAR2(4000);
        l_target_message          CLOB;

        l_context_user_id         NUMBER;
        l_context_resp_id         NUMBER;
        l_context_resp_appl_id    NUMBER;
    BEGIN
        x_return_status := NULL;
        x_message       := NULL;

        l_session_user  := f_get_session_user;
        l_session_login := NVL(SYS_CONTEXT('APEX$SESSION', 'APP_SESSION'), USER);

        l_commit_flag := CASE
                             WHEN UPPER(NVL(p_commit_flag, 'Y')) = 'Y' THEN 'Y'
                             ELSE 'N'
                         END;

        DBMS_LOB.CREATETEMPORARY(l_overall_message, TRUE);

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Start. ITEM_CREATION_STG_ID=' || NVL(TO_CHAR(p_item_creation_stg_id), 'NULL') ||
            ', OVERRIDE_VALIDATE_ONLY_FLAG=' || NVL(p_validate_only_flag, 'NULL') ||
            ', COMMIT_FLAG=' || l_commit_flag
        );

        SELECT *
          INTO l_stg
          FROM ops.xinv_item_creation_stg_v2
         WHERE item_creation_stg_id = p_item_creation_stg_id
         FOR UPDATE;

        pcd_validate_staging_row(l_stg);

        l_validate_only_flag := CASE
                                    WHEN p_validate_only_flag IS NOT NULL
                                    THEN UPPER(SUBSTR(TRIM(p_validate_only_flag), 1, 1))
                                    ELSE UPPER(NVL(l_stg.validate_only_flag, 'Y'))
                                END;

        IF l_validate_only_flag NOT IN ('Y', 'N') THEN
            l_validate_only_flag := 'Y';
        END IF;

        l_transaction_type := f_transaction_type(l_stg.api_transaction_type);

        pcd_append_text(l_overall_message, 'Item API process started.');
        pcd_append_text(l_overall_message, 'Item number: ' || l_stg.item_number);
        pcd_append_text(l_overall_message, 'Master org/template: ' || l_stg.master_org_code || ' / ' || NVL(l_stg.master_template_name, 'NULL'));
        pcd_append_text(l_overall_message, 'Target org/template: ' || NVL(l_stg.target_org_code, 'NULL') || ' / ' || NVL(l_stg.target_template_name, 'NULL'));

        set_env;
        l_context_user_id      := NVL(p_user_id, g_user_id);
        l_context_resp_id      := NVL(p_resp_id, g_resp_id);
        l_context_resp_appl_id := NVL(p_resp_appl_id, g_application_id);

        pcd_initialize_ebs_context(
            p_user_id      => l_context_user_id,
            p_resp_id      => l_context_resp_id,
            p_resp_appl_id => l_context_resp_appl_id
        );

        /* ============================================================
           CALL #1 - MASTER ITEM CREATION / VERIFICATION
           This call uses MASTER_ORG_CODE and MASTER_TEMPLATE_NAME.
           Example: MAS + GLOBAL ITEM.
           ============================================================ */
        l_master_exists := f_item_exists(
                               p_item_number       => l_stg.item_number,
                               p_organization_code => l_stg.master_org_code,
                               x_inventory_item_id => l_master_item_id,
                               x_organization_id   => l_master_org_id,
                               x_item_status_code  => l_master_status_code
                           );

        IF l_master_exists THEN
            l_master_return_status := c_return_success;
            l_master_msg_count     := 0;
            pcd_append_text(l_master_message, 'CALL #1 skipped. Master item already exists in organization ' || l_stg.master_org_code || '.');
            pcd_append_text(l_overall_message, 'CALL #1 skipped. Item already exists in ' || l_stg.master_org_code || '.');
            pcd_write_log('PCD_CALL_ITEM_API', 'CALL #1 skipped. Item already exists in master organization ' || l_stg.master_org_code || '.');
        ELSE
            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'CALL #1 starting. Creating master item. ITEM_NUMBER=' || l_stg.item_number ||
                ', ORGANIZATION_CODE=' || l_stg.master_org_code ||
                ', TEMPLATE_NAME=' || NVL(l_stg.master_template_name, 'NULL')
            );

            BEGIN
                apps.fnd_msg_pub.initialize;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

            apps.ego_item_pub.process_item(
                p_api_version                    => 1.0,
                p_init_msg_list                  => c_api_true,
                p_commit                         => c_api_false,
                p_transaction_type               => l_transaction_type,
                p_template_name                  => l_stg.master_template_name,
                p_item_number                    => l_stg.item_number,
                p_segment1                       => l_stg.item_number,
                p_organization_code              => l_stg.master_org_code,
                p_description                    => l_stg.item_description,
                p_long_description               => f_optional_char(l_stg.long_description),
                p_primary_uom_code               => l_stg.primary_uom_code,
                p_inventory_item_status_code     => f_optional_char(l_stg.item_status_code),
                p_bom_enabled_flag               => f_yes_no(l_stg.bom_enabled_flag),
                p_eng_item_flag                  => CASE
                                                       WHEN l_stg.engineering_status IS NOT NULL THEN 'Y'
                                                       ELSE c_missing_char
                                                    END,
                x_inventory_item_id              => l_master_item_id,
                x_organization_id                => l_master_org_id,
                x_return_status                  => l_master_return_status,
                x_msg_count                      => l_master_msg_count,
                x_msg_data                       => l_master_msg_data
            );

            l_master_message := f_get_api_messages(l_master_msg_count, l_master_msg_data);

            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'CALL #1 completed. RETURN_STATUS=' || NVL(l_master_return_status, 'NULL') ||
                ', MSG_COUNT=' || NVL(TO_CHAR(l_master_msg_count), '0') ||
                ', INVENTORY_ITEM_ID=' || NVL(TO_CHAR(l_master_item_id), 'NULL') ||
                ', ORGANIZATION_ID=' || NVL(TO_CHAR(l_master_org_id), 'NULL')
            );

            pcd_append_text(l_overall_message, 'CALL #1 master status: ' || NVL(l_master_return_status, 'NULL'));
            pcd_append_text(l_overall_message, DBMS_LOB.SUBSTR(l_master_message, 3000, 1));
        END IF;

        IF l_master_return_status <> c_return_success THEN
            ROLLBACK;
            l_new_request_status := c_status_error;
            x_return_status      := NVL(l_master_return_status, c_return_error);
            pcd_append_text(l_overall_message, 'Process stopped because CALL #1 master item creation failed.');
        ELSE
            /* ============================================================
               CALL #2 - TARGET ORGANIZATION ITEM CREATION / VERIFICATION
               This call uses TARGET_ORG_CODE and TARGET_TEMPLATE_NAME.
               Example: GRI + ADHESIVES.
               ============================================================ */
            IF l_stg.target_org_code IS NOT NULL
               AND UPPER(TRIM(l_stg.target_org_code)) <> UPPER(TRIM(l_stg.master_org_code)) THEN

                l_target_exists := f_item_exists(
                                       p_item_number       => l_stg.item_number,
                                       p_organization_code => l_stg.target_org_code,
                                       x_inventory_item_id => l_target_item_id,
                                       x_organization_id   => l_target_org_id,
                                       x_item_status_code  => l_target_status_code
                                   );

                IF l_target_exists THEN
                    l_target_return_status := c_return_success;
                    l_target_msg_count     := 0;
                    pcd_append_text(l_target_message, 'CALL #2 skipped. Target item already exists in organization ' || l_stg.target_org_code || '.');
                    pcd_append_text(l_overall_message, 'CALL #2 skipped. Item already exists in ' || l_stg.target_org_code || '.');
                    pcd_write_log('PCD_CALL_ITEM_API', 'CALL #2 skipped. Item already exists in target organization ' || l_stg.target_org_code || '.');
                ELSE
                    pcd_write_log(
                        'PCD_CALL_ITEM_API',
                        'CALL #2 starting. Creating target org item. ITEM_NUMBER=' || l_stg.item_number ||
                        ', ORGANIZATION_CODE=' || l_stg.target_org_code ||
                        ', TEMPLATE_NAME=' || l_stg.target_template_name
                    );

                    BEGIN
                        apps.fnd_msg_pub.initialize;
                    EXCEPTION
                        WHEN OTHERS THEN
                            NULL;
                    END;

                    apps.ego_item_pub.process_item(
                        p_api_version                    => 1.0,
                        p_init_msg_list                  => c_api_true,
                        p_commit                         => c_api_false,
                        p_transaction_type               => l_transaction_type,
                        p_template_name                  => l_stg.target_template_name,
                        p_item_number                    => l_stg.item_number,
                        p_segment1                       => l_stg.item_number,
                        p_organization_code              => l_stg.target_org_code,
                        p_description                    => l_stg.item_description,
                        p_long_description               => f_optional_char(l_stg.long_description),
                        p_primary_uom_code               => l_stg.primary_uom_code,
                        p_inventory_item_status_code     => f_optional_char(l_stg.item_status_code),
                        p_bom_enabled_flag               => f_yes_no(l_stg.bom_enabled_flag),
                        p_eng_item_flag                  => CASE
                                                               WHEN l_stg.engineering_status IS NOT NULL THEN 'Y'
                                                               ELSE c_missing_char
                                                            END,
                        x_inventory_item_id              => l_target_item_id,
                        x_organization_id                => l_target_org_id,
                            x_return_status                  => l_target_return_status,
                        x_msg_count                      => l_target_msg_count,
                        x_msg_data                       => l_target_msg_data
                    );

                    l_target_message := f_get_api_messages(l_target_msg_count, l_target_msg_data);

                    pcd_write_log(
                        'PCD_CALL_ITEM_API',
                        'CALL #2 completed. RETURN_STATUS=' || NVL(l_target_return_status, 'NULL') ||
                        ', MSG_COUNT=' || NVL(TO_CHAR(l_target_msg_count), '0') ||
                        ', INVENTORY_ITEM_ID=' || NVL(TO_CHAR(l_target_item_id), 'NULL') ||
                        ', ORGANIZATION_ID=' || NVL(TO_CHAR(l_target_org_id), 'NULL')
                    );

                    pcd_append_text(l_overall_message, 'CALL #2 target status: ' || NVL(l_target_return_status, 'NULL'));
                    pcd_append_text(l_overall_message, DBMS_LOB.SUBSTR(l_target_message, 3000, 1));
                END IF;

                IF l_target_return_status = c_return_success THEN
                    x_return_status := c_return_success;
                ELSE
                    ROLLBACK;
                    x_return_status := NVL(l_target_return_status, c_return_error);
                    pcd_append_text(l_overall_message, 'Process stopped because CALL #2 target organization creation failed.');
                END IF;
            ELSE
                l_target_return_status := NULL;
                l_target_msg_count     := NULL;
                x_return_status        := c_return_success;
                pcd_append_text(l_overall_message, 'CALL #2 skipped. No separate target organization was provided.');
            END IF;

            IF x_return_status = c_return_success THEN
                IF l_validate_only_flag = 'Y' THEN
                    ROLLBACK;
                    l_new_request_status := c_status_validated;
                    pcd_append_text(l_overall_message, 'Validate-only mode completed successfully. API changes were rolled back.');
                ELSE
                    l_new_request_status := c_status_processed;
                    pcd_append_text(l_overall_message, 'Create/update mode completed successfully.');
                END IF;
            ELSE
                l_new_request_status := c_status_error;
            END IF;
        END IF;

        x_message := l_overall_message;

        UPDATE ops.xinv_item_creation_stg_v2
           SET request_status             = l_new_request_status,
               validate_only_flag         = l_validate_only_flag,

               master_inventory_item_id   = NVL(l_master_item_id, master_inventory_item_id),
               master_organization_id     = NVL(l_master_org_id, master_organization_id),
               master_api_return_status   = l_master_return_status,
               master_api_message_count   = l_master_msg_count,
               master_api_message_text    = l_master_message,
               master_api_processed_date  = SYSDATE,

               target_inventory_item_id   = NVL(l_target_item_id, target_inventory_item_id),
               target_organization_id     = NVL(l_target_org_id, target_organization_id),
               target_api_return_status   = l_target_return_status,
               target_api_message_count   = l_target_msg_count,
               target_api_message_text    = l_target_message,
               target_api_processed_date  = CASE
                                                WHEN l_stg.target_org_code IS NOT NULL THEN SYSDATE
                                                ELSE target_api_processed_date
                                             END,

               oracle_inventory_item_id   = CASE
                                                WHEN l_target_item_id IS NOT NULL THEN l_target_item_id
                                                ELSE l_master_item_id
                                             END,
               oracle_organization_id     = CASE
                                                WHEN l_target_org_id IS NOT NULL THEN l_target_org_id
                                                ELSE l_master_org_id
                                             END,
               api_return_status          = x_return_status,
               api_message_count          = NVL(l_master_msg_count, 0) + NVL(l_target_msg_count, 0),
               api_message_text           = x_message,
               api_processed_date         = SYSDATE,
               last_updated_by            = l_session_user,
               last_update_date           = SYSDATE,
               last_update_login          = l_session_login
         WHERE item_creation_stg_id = p_item_creation_stg_id;

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Staging row updated. ITEM_CREATION_STG_ID=' || p_item_creation_stg_id ||
            ', REQUEST_STATUS=' || l_new_request_status ||
            ', RETURN_STATUS=' || NVL(x_return_status, 'NULL') ||
            ', ROWCOUNT=' || SQL%ROWCOUNT
        );

        IF l_commit_flag = 'Y' THEN
            COMMIT;
        END IF;

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'End. ITEM_CREATION_STG_ID=' || p_item_creation_stg_id ||
            ', RETURN_STATUS=' || NVL(x_return_status, 'NULL') ||
            ', FINAL_REQUEST_STATUS=' || l_new_request_status
        );

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            x_return_status := c_return_error;
            x_message       := TO_CLOB('No staging row found for ITEM_CREATION_STG_ID = ' || p_item_creation_stg_id);
            pcd_write_log('PCD_CALL_ITEM_API', 'No staging row found. ITEM_CREATION_STG_ID=' || NVL(TO_CHAR(p_item_creation_stg_id), 'NULL'));

        WHEN OTHERS THEN
            l_error_text := 'Unexpected error in PCD_CALL_ITEM_API. ITEM_CREATION_STG_ID=' ||
                            NVL(TO_CHAR(p_item_creation_stg_id), 'NULL') ||
                            ', SQLERRM=' || SQLERRM ||
                            ', BACKTRACE=' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;

            pcd_write_log('PCD_CALL_ITEM_API', l_error_text);

            BEGIN
                ROLLBACK;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

            x_return_status := c_return_unexpected;
            DBMS_LOB.CREATETEMPORARY(l_error_clob, TRUE);
            pcd_append_text(l_error_clob, l_error_text);
            x_message := l_error_clob;

            BEGIN
                UPDATE ops.xinv_item_creation_stg_v2
                   SET request_status     = c_status_error,
                       api_return_status  = x_return_status,
                       api_message_count  = 1,
                       api_message_text   = x_message,
                       api_processed_date = SYSDATE,
                       last_updated_by    = NVL(l_session_user, USER),
                       last_update_date   = SYSDATE,
                       last_update_login  = NVL(l_session_login, USER)
                 WHERE item_creation_stg_id = p_item_creation_stg_id;

                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    pcd_write_log('PCD_CALL_ITEM_API', 'Could not update staging row after exception. Error: ' || SQLERRM);
            END;
    END pcd_call_item_api;

    PROCEDURE pcd_process_staging (
        p_request_status        IN  VARCHAR2 DEFAULT 'SUBMITTED',
        p_request_number        IN  VARCHAR2 DEFAULT NULL,
        p_max_rows              IN  NUMBER   DEFAULT NULL,
        p_validate_only_flag    IN  VARCHAR2 DEFAULT NULL,
        p_user_id               IN  NUMBER   DEFAULT NULL,
        p_resp_id               IN  NUMBER   DEFAULT NULL,
        p_resp_appl_id          IN  NUMBER   DEFAULT NULL,
        p_commit_each_row_flag  IN  VARCHAR2 DEFAULT 'Y',
        x_total_count           OUT NUMBER,
        x_success_count         OUT NUMBER,
        x_error_count           OUT NUMBER,
        x_message               OUT CLOB
    )
    IS
        CURSOR c_staging IS
            SELECT item_creation_stg_id,
                   request_number,
                   item_number
              FROM ops.xinv_item_creation_stg_v2
             WHERE request_status = NVL(p_request_status, c_status_submitted)
               AND (p_request_number IS NULL OR request_number = p_request_number)
             ORDER BY item_creation_stg_id;

        l_row_status VARCHAR2(1);
        l_row_message CLOB;
        l_summary     CLOB;
        l_error_text  VARCHAR2(4000);
    BEGIN
        x_total_count   := 0;
        x_success_count := 0;
        x_error_count   := 0;
        x_message       := NULL;

        DBMS_LOB.CREATETEMPORARY(l_summary, TRUE);
        pcd_append_text(l_summary, 'Batch started.');

        FOR r IN c_staging LOOP
            EXIT WHEN p_max_rows IS NOT NULL AND x_total_count >= p_max_rows;

            x_total_count := x_total_count + 1;

            pcd_call_item_api(
                p_item_creation_stg_id => r.item_creation_stg_id,
                p_validate_only_flag   => p_validate_only_flag,
                p_user_id              => p_user_id,
                p_resp_id              => p_resp_id,
                p_resp_appl_id         => p_resp_appl_id,
                p_commit_flag          => p_commit_each_row_flag,
                x_return_status        => l_row_status,
                x_message              => l_row_message
            );

            IF l_row_status = c_return_success THEN
                x_success_count := x_success_count + 1;
            ELSE
                x_error_count := x_error_count + 1;
            END IF;

            pcd_append_text(
                l_summary,
                'Request ' || r.request_number ||
                ' / staging ID ' || r.item_creation_stg_id ||
                ' / item ' || r.item_number ||
                ' finished with status ' || NVL(l_row_status, 'NULL') || '.'
            );
        END LOOP;

        pcd_append_text(l_summary, 'Total attempted: ' || x_total_count);
        pcd_append_text(l_summary, 'Success count: ' || x_success_count);
        pcd_append_text(l_summary, 'Error count: ' || x_error_count);

        x_message := l_summary;

        IF UPPER(NVL(p_commit_each_row_flag, 'Y')) <> 'Y' THEN
            COMMIT;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            l_error_text := 'Unexpected error in PCD_PROCESS_STAGING. SQLERRM=' || SQLERRM ||
                            ', BACKTRACE=' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;

            pcd_write_log('PCD_PROCESS_STAGING', l_error_text);

            x_error_count := NVL(x_error_count, 0) + 1;

            IF x_message IS NULL THEN
                DBMS_LOB.CREATETEMPORARY(x_message, TRUE);
            END IF;

            pcd_append_text(x_message, l_error_text);
            RAISE;
    END pcd_process_staging;

END xinv_item_api_pkg_v2;
/
SHOW ERRORS PACKAGE BODY apps.xinv_item_api_pkg_v2
