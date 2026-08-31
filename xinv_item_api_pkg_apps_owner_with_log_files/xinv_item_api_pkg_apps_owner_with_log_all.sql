CREATE OR REPLACE PACKAGE xinv_item_api_pkg AS
/******************************************************************************
AR Global.
NAME:     xinv_item_api_pkg
PURPOSE:  Package used by the APEX item creation process for AR Global.
          It reads item creation requests from XINV_ITEM_CREATION_STG,
          initializes the EBS application context when requested, writes detailed
          process logs through PKG_LOG, and calls APPS.EGO_ITEM_PUB.PROCESS_ITEM
          through a controlled wrapper.

          This version qualifies EBS API calls with the APPS owner and avoids
          direct references to EGO_ITEM_PUB constants in order to compile from
          custom schemas that have execute access but do not expose package
          constants through local synonyms.

REVIEWS:
Version        Date        Author           Description
---------  ----------  ---------------  ------------------------------------
1.0        13.07.2026  JCALZADILLA      First version
1.1        13.07.2026  JCALZADILLA      Added detailed PKG_LOG logging
1.2        13.07.2026  JCALZADILLA      Qualified EBS API calls with APPS owner
*******************************************************************************/

    /******************************************************************************
    AR Global.
    Name:        pcd_call_item_api
    Description: Calls APPS.EGO_ITEM_PUB.PROCESS_ITEM for one item creation
                 staging row. The procedure reads one row from
                 XINV_ITEM_CREATION_STG, maps the staging columns to the minimum
                 controlled API parameters, executes the API, captures the API
                 return status and messages, logs the execution details through
                 PKG_LOG, and updates the staging row with the API result.

                 When validate-only mode is enabled, the procedure rolls back the
                 API work to the local savepoint after execution and only preserves
                 the staging result message. This allows APEX to test item creation
                 without creating the item.

                 The first production version relies heavily on the EBS item
                 template to default detailed item attributes. More direct
                 attribute mappings can be added after AR Global confirms the exact
                 item API signature, templates, and attribute rules in the target
                 EBS instance.

    Parameters:  p_item_creation_stg_id  NUMBER    Primary key from XINV_ITEM_CREATION_STG.
                 p_validate_only_flag    VARCHAR2  Optional override. Y = validate only,
                                                   N = create/update item.
                 p_user_id               NUMBER    EBS user_id used by APPS.FND_GLOBAL.APPS_INITIALIZE.
                 p_resp_id               NUMBER    EBS responsibility_id used by APPS_INITIALIZE.
                 p_resp_appl_id          NUMBER    EBS responsibility_application_id.
                 p_commit_flag           VARCHAR2  Y = commit staging/API result, N = caller controls commit.
                 x_return_status         VARCHAR2  API return status: S, E, U.
                 x_message               CLOB      Aggregated API message text.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.1          13.07.2026  JCALZADILLA    Added detailed PKG_LOG logging
    1.2          13.07.2026  JCALZADILLA    Qualified API call with APPS owner
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

    /******************************************************************************
    AR Global.
    Name:        pcd_process_staging
    Description: Loops through XINV_ITEM_CREATION_STG and calls pcd_call_item_api
                 for each eligible staging row. This is the batch-oriented entry
                 point that can be called from APEX, SQL Developer, a concurrent
                 program wrapper, or a scheduler job.

                 By default, it processes rows with request_status = SUBMITTED.
                 It can also process one request number, limit the number of rows,
                 and optionally override validate-only mode for all selected rows.

    Parameters:  p_request_status       VARCHAR2  Staging status to process.
                 p_request_number       VARCHAR2  Optional specific request number.
                 p_max_rows             NUMBER    Optional maximum number of rows to process.
                 p_validate_only_flag   VARCHAR2  Optional override. Y = validate only,
                                                 N = create/update item.
                 p_user_id              NUMBER    EBS user_id used by APPS.FND_GLOBAL.APPS_INITIALIZE.
                 p_resp_id              NUMBER    EBS responsibility_id used by APPS_INITIALIZE.
                 p_resp_appl_id         NUMBER    EBS responsibility_application_id.
                 p_commit_each_row_flag VARCHAR2  Y = commit each row independently.
                 x_total_count          NUMBER    Total rows attempted.
                 x_success_count        NUMBER    Rows successfully validated/processed.
                 x_error_count          NUMBER    Rows ending in error.
                 x_message              CLOB      Batch execution summary.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.1          13.07.2026  JCALZADILLA    Added detailed PKG_LOG logging
    1.2          13.07.2026  JCALZADILLA    Qualified API call with APPS owner
    ******************************************************************************/
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

END xinv_item_api_pkg;
/
SHOW ERRORS
CREATE OR REPLACE PACKAGE BODY xinv_item_api_pkg AS
/******************************************************************************
AR Global.
NAME:     xinv_item_api_pkg
PURPOSE:  Package body for the AR Global APEX item creation process.
          This body contains helper routines, detailed PKG_LOG logging, the
          single-row API wrapper, and the staging-table batch processor.

          EBS package calls are explicitly qualified with the APPS owner.
          Local constants are used for standard API values in order to avoid
          compilation failures when EGO_ITEM_PUB constants are not visible from
          the custom schema.

REVIEWS:
Version        Date        Author           Description
---------  ----------  ---------------  ------------------------------------
1.0        13.07.2026  JCALZADILLA      First version
1.1        13.07.2026  JCALZADILLA      Added detailed PKG_LOG logging
1.2        13.07.2026  JCALZADILLA      Qualified EBS API calls with APPS owner
*******************************************************************************/

    c_application_code CONSTANT VARCHAR2(30) := 'XINV';

    c_status_draft     CONSTANT VARCHAR2(30) := 'DRAFT';
    c_status_validated CONSTANT VARCHAR2(30) := 'VALIDATED';
    c_status_submitted CONSTANT VARCHAR2(30) := 'SUBMITTED';
    c_status_processed CONSTANT VARCHAR2(30) := 'PROCESSED';
    c_status_error     CONSTANT VARCHAR2(30) := 'ERROR';

    c_api_true         CONSTANT VARCHAR2(1)  := 'T';
    c_api_false        CONSTANT VARCHAR2(1)  := 'F';
    c_return_success   CONSTANT VARCHAR2(1)  := 'S';
    c_return_error     CONSTANT VARCHAR2(1)  := 'E';
    c_return_unexpected CONSTANT VARCHAR2(1) := 'U';
    c_missing_char     CONSTANT VARCHAR2(1)  := CHR(0);
    c_transaction_create CONSTANT VARCHAR2(20) := 'CREATE';
    c_transaction_update CONSTANT VARCHAR2(20) := 'UPDATE';

    /******************************************************************************
    AR Global.
    Name:        pcd_write_log
    Description: Writes one diagnostic message using the existing PKG_LOG package.
                 Logging failures are intentionally ignored so that a logging issue
                 never blocks item creation processing.

    Parameters:  p_business_process VARCHAR2  Logical package procedure or step name.
                 p_message          VARCHAR2  Diagnostic message text.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    ******************************************************************************/
    PROCEDURE pcd_write_log (
        p_business_process IN VARCHAR2,
        p_message          IN VARCHAR2
    ) IS
    BEGIN
        pkg_log.sp_insert_message(
            p_co_aplication       => c_application_code,
            p_tx_business_process => SUBSTR(p_business_process, 1, 240),
            p_tx_message          => SUBSTR(p_message, 1, 3900)
        );
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END pcd_write_log;

    /******************************************************************************
    AR Global.
    Name:        pcd_append_text
    Description: Appends one text line to a CLOB. This helper is used to build API
                 and batch summary messages that will be returned to APEX.

    Parameters:  io_clob CLOB      CLOB being built.
                 p_text  VARCHAR2  Text to append.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    ******************************************************************************/
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

    /******************************************************************************
    AR Global.
    Name:        f_get_session_user
    Description: Returns the APEX user when the package is executed from APEX.
                 Otherwise, it returns the database user. This value is used only
                 for local staging audit/error updates. The EBS security context is
                 controlled separately by APPS.FND_GLOBAL.APPS_INITIALIZE.

    Parameters:  None.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    ******************************************************************************/
    FUNCTION f_get_session_user
        RETURN VARCHAR2
    IS
    BEGIN
        RETURN NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);
    END f_get_session_user;

    /******************************************************************************
    AR Global.
    Name:        f_optional_char
    Description: Returns the value provided by the staging row. When the value is
                 NULL, it returns the EBS standard missing-character value CHR(0).
                 This avoids using EGO_ITEM_PUB.G_MISS_CHAR directly from a custom
                 schema where the constant may not compile due to grants/synonyms.

    Parameters:  p_value VARCHAR2  Optional text value.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    ******************************************************************************/
    FUNCTION f_optional_char (
        p_value IN VARCHAR2
    ) RETURN VARCHAR2
    IS
    BEGIN
        RETURN NVL(p_value, c_missing_char);
    END f_optional_char;

    /******************************************************************************
    AR Global.
    Name:        f_yes_no
    Description: Normalizes a Y/N staging flag before passing it to the API.
                 Unknown or NULL values are returned as the EBS standard missing
                 character value CHR(0), which means the value is not explicitly
                 passed to the API.

    Parameters:  p_value VARCHAR2  Staging flag value.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.2          13.07.2026  JCALZADILLA    Removed direct EGO_ITEM_PUB constant references
    ******************************************************************************/
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

    /******************************************************************************
    AR Global.
    Name:        f_transaction_type
    Description: Converts the staging transaction type to the API transaction type
                 value expected by APPS.EGO_ITEM_PUB.PROCESS_ITEM.

    Parameters:  p_value VARCHAR2  Staging transaction type.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.2          13.07.2026  JCALZADILLA    Removed direct EGO_ITEM_PUB constant references
    ******************************************************************************/
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

    /******************************************************************************
    AR Global.
    Name:        f_get_api_messages
    Description: Retrieves messages generated by APPS.EGO_ITEM_PUB and returns them
                 as a single CLOB. This version only uses APPS.FND_MSG_PUB and does
                 not depend on ERROR_HANDLER.ERROR_TBL_TYPE, which may not be
                 directly granted to a custom schema.

    Parameters:  p_msg_count NUMBER  Message count returned by the API.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.2          13.07.2026  JCALZADILLA    Removed ERROR_HANDLER dependency
    ******************************************************************************/
    FUNCTION f_get_api_messages (
        p_msg_count IN NUMBER
    ) RETURN CLOB
    IS
        l_message_text CLOB;
        l_fnd_message  VARCHAR2(4000);
    BEGIN
        DBMS_LOB.CREATETEMPORARY(l_message_text, TRUE);

        IF NVL(p_msg_count, 0) > 0 THEN
            FOR i IN 1 .. p_msg_count LOOP
                BEGIN
                    l_fnd_message := APPS.FND_MSG_PUB.GET(
                                         p_msg_index => i,
                                         p_encoded   => c_api_false
                                     );

                    IF l_fnd_message IS NOT NULL THEN
                        pcd_append_text(
                            l_message_text,
                            'FND message ' || i || ': ' || l_fnd_message
                        );
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        pcd_append_text(
                            l_message_text,
                            'Could not read FND message ' || i || ': ' || SQLERRM
                        );
                END;
            END LOOP;
        END IF;

        IF DBMS_LOB.GETLENGTH(l_message_text) = 0 THEN
            pcd_append_text(
                l_message_text,
                'No detailed API message was returned. API message count = ' || NVL(TO_CHAR(p_msg_count), '0')
            );
        END IF;

        RETURN l_message_text;
    END f_get_api_messages;

    /******************************************************************************
    AR Global.
    Name:        pcd_initialize_ebs_context
    Description: Initializes the EBS application context if user, responsibility,
                 and application responsibility values were provided. This is
                 required when the package is executed from APEX using a database
                 schema instead of a live EBS Forms session.

    Parameters:  p_user_id       NUMBER  EBS FND_USER.USER_ID.
                 p_resp_id       NUMBER  EBS responsibility_id.
                 p_resp_appl_id  NUMBER  EBS responsibility_application_id.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.1          13.07.2026  JCALZADILLA    Added logging around context initialization
    1.2          13.07.2026  JCALZADILLA    Qualified EBS context calls with APPS owner
    ******************************************************************************/
    PROCEDURE pcd_initialize_ebs_context (
        p_user_id      IN NUMBER,
        p_resp_id      IN NUMBER,
        p_resp_appl_id IN NUMBER
    )
    IS
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

            APPS.FND_GLOBAL.APPS_INITIALIZE(
                user_id      => p_user_id,
                resp_id      => p_resp_id,
                resp_appl_id => p_resp_appl_id
            );

            BEGIN
                APPS.MO_GLOBAL.INIT('INV');
                pcd_write_log(
                    'PCD_INITIALIZE_EBS_CONTEXT',
                    'APPS.MO_GLOBAL.INIT completed for application INV.'
                );
            EXCEPTION
                WHEN OTHERS THEN
                    pcd_write_log(
                        'PCD_INITIALIZE_EBS_CONTEXT',
                        'APPS.MO_GLOBAL.INIT failed or was not required. Error: ' || SQLERRM
                    );
            END;
        ELSE
            pcd_write_log(
                'PCD_INITIALIZE_EBS_CONTEXT',
                'EBS context initialization skipped. One or more values are missing. ' ||
                'USER_ID=' || NVL(TO_CHAR(p_user_id), 'NULL') ||
                ', RESP_ID=' || NVL(TO_CHAR(p_resp_id), 'NULL') ||
                ', RESP_APPL_ID=' || NVL(TO_CHAR(p_resp_appl_id), 'NULL')
            );
        END IF;
    END pcd_initialize_ebs_context;

    /******************************************************************************
    AR Global.
    Name:        pcd_validate_staging_row
    Description: Performs basic defensive validation before calling the EBS item API.
                 Business-specific validations should continue to be handled by APEX
                 and by setup-driven rules, but this procedure prevents empty critical
                 values from reaching the API wrapper.

    Parameters:  p_stg XINV_ITEM_CREATION_STG%ROWTYPE  Staging row being processed.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    ******************************************************************************/
    PROCEDURE pcd_validate_staging_row (
        p_stg IN xinv_item_creation_stg%ROWTYPE
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
            RAISE_APPLICATION_ERROR(-20004, 'Master organization code is required before calling APPS.EGO_ITEM_PUB.PROCESS_ITEM.');
        END IF;
    END pcd_validate_staging_row;

    /******************************************************************************
    AR Global.
    Name:        pcd_call_item_api
    Description: Calls APPS.EGO_ITEM_PUB.PROCESS_ITEM for one item creation staging
                 row. The procedure reads one row from XINV_ITEM_CREATION_STG,
                 maps the staging columns to the minimum controlled API parameters,
                 executes the API, captures the API return status and messages,
                 logs each relevant execution step, and updates the staging row
                 with the API result.

                 Detailed inventory controls such as lot, serial, shelf life,
                 locator, WIP, costing, and purchasing are expected to come from
                 the template in this first version. They can be added to the API
                 call after AR Global confirms the exact required mappings.

    Parameters:  p_item_creation_stg_id  NUMBER    Primary key from XINV_ITEM_CREATION_STG.
                 p_validate_only_flag    VARCHAR2  Optional override. Y = validate only,
                                                   N = create/update item.
                 p_user_id               NUMBER    EBS user_id used by APPS.FND_GLOBAL.APPS_INITIALIZE.
                 p_resp_id               NUMBER    EBS responsibility_id used by APPS_INITIALIZE.
                 p_resp_appl_id          NUMBER    EBS responsibility_application_id.
                 p_commit_flag           VARCHAR2  Y = commit staging/API result, N = caller controls commit.
                 x_return_status         VARCHAR2  API return status: S, E, U.
                 x_message               CLOB      Aggregated API message text.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.1          13.07.2026  JCALZADILLA    Added detailed PKG_LOG logging
    1.2          13.07.2026  JCALZADILLA    Qualified API call with APPS owner
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
    )
    IS
        l_stg                xinv_item_creation_stg%ROWTYPE;
        l_validate_only_flag VARCHAR2(1);
        l_new_request_status VARCHAR2(30);
        l_transaction_type   VARCHAR2(30);
        l_return_status      VARCHAR2(1);
        l_msg_count          NUMBER;
        l_inventory_item_id  NUMBER;
        l_organization_id    NUMBER;
        l_message            CLOB;
        l_commit_flag        VARCHAR2(1);
        l_error_text         VARCHAR2(4000);
        l_error_clob         CLOB;
    BEGIN
        x_return_status := NULL;
        x_message       := NULL;

        l_commit_flag := CASE
                             WHEN UPPER(NVL(p_commit_flag, 'Y')) = 'Y' THEN 'Y'
                             ELSE 'N'
                         END;

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Start. ITEM_CREATION_STG_ID=' || NVL(TO_CHAR(p_item_creation_stg_id), 'NULL') ||
            ', OVERRIDE_VALIDATE_ONLY_FLAG=' || NVL(p_validate_only_flag, 'NULL') ||
            ', COMMIT_FLAG=' || l_commit_flag
        );

        SELECT *
          INTO l_stg
          FROM xinv_item_creation_stg
         WHERE item_creation_stg_id = p_item_creation_stg_id
         FOR UPDATE;

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Staging row loaded. REQUEST_NUMBER=' || l_stg.request_number ||
            ', CURRENT_STATUS=' || l_stg.request_status ||
            ', ITEM_NUMBER=' || l_stg.item_number ||
            ', MASTER_ORG_CODE=' || l_stg.master_org_code ||
            ', TARGET_ORG_CODE=' || NVL(l_stg.target_org_code, 'NULL')
        );

        pcd_validate_staging_row(l_stg);

        l_validate_only_flag := CASE
                                    WHEN p_validate_only_flag IS NOT NULL
                                    THEN UPPER(SUBSTR(TRIM(p_validate_only_flag), 1, 1))
                                    ELSE UPPER(NVL(l_stg.validate_only_flag, 'Y'))
                                END;

        IF l_validate_only_flag NOT IN ('Y', 'N') THEN
            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'Invalid validate-only flag received. Value=' || NVL(l_validate_only_flag, 'NULL') ||
                '. The procedure will default to validate-only mode.'
            );
            l_validate_only_flag := 'Y';
        END IF;

        l_transaction_type := f_transaction_type(l_stg.api_transaction_type);

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Normalized execution values. VALIDATE_ONLY_FLAG=' || l_validate_only_flag ||
            ', API_TRANSACTION_TYPE=' || l_transaction_type ||
            ', TEMPLATE_NAME=' || NVL(l_stg.template_name, 'NULL') ||
            ', PRIMARY_UOM_CODE=' || l_stg.primary_uom_code ||
            ', ITEM_STATUS_CODE=' || NVL(l_stg.item_status_code, 'NULL')
        );

        pcd_initialize_ebs_context(
            p_user_id      => p_user_id,
            p_resp_id      => p_resp_id,
            p_resp_appl_id => p_resp_appl_id
        );

        SAVEPOINT xinv_before_item_api;

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Savepoint created. Calling APPS.EGO_ITEM_PUB.PROCESS_ITEM for item ' || l_stg.item_number ||
            ' in organization ' || l_stg.master_org_code || '.'
        );

        APPS.EGO_ITEM_PUB.PROCESS_ITEM(
            p_api_version                    => 1.0,
            p_init_msg_list                  => c_api_true,
            p_commit                         => c_api_false,
            p_transaction_type               => l_transaction_type,
            p_template_name                  => l_stg.template_name,
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
            x_inventory_item_id              => l_inventory_item_id,
            x_organization_id                => l_organization_id,
            x_return_status                  => l_return_status,
            x_msg_count                      => l_msg_count
        );

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'API call completed. RETURN_STATUS=' || NVL(l_return_status, 'NULL') ||
            ', MSG_COUNT=' || NVL(TO_CHAR(l_msg_count), '0') ||
            ', INVENTORY_ITEM_ID=' || NVL(TO_CHAR(l_inventory_item_id), 'NULL') ||
            ', ORGANIZATION_ID=' || NVL(TO_CHAR(l_organization_id), 'NULL')
        );

        l_message := f_get_api_messages(l_msg_count);

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'API message preview: ' || DBMS_LOB.SUBSTR(l_message, 3000, 1)
        );

        IF l_return_status = c_return_success THEN
            IF l_validate_only_flag = 'Y' THEN
                ROLLBACK TO xinv_before_item_api;
                l_new_request_status := c_status_validated;

                pcd_write_log(
                    'PCD_CALL_ITEM_API',
                    'Validate-only mode completed successfully. API changes were rolled back to the savepoint. ' ||
                    'Staging status will be set to VALIDATED.'
                );
            ELSE
                l_new_request_status := c_status_processed;

                pcd_write_log(
                    'PCD_CALL_ITEM_API',
                    'API completed successfully in create/update mode. Staging status will be set to PROCESSED.'
                );
            END IF;
        ELSE
            ROLLBACK TO xinv_before_item_api;
            l_new_request_status := c_status_error;

            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'API returned an error or unexpected status. API changes were rolled back to the savepoint. ' ||
                'Staging status will be set to ERROR.'
            );
        END IF;

        UPDATE xinv_item_creation_stg
           SET request_status           = l_new_request_status,
               validate_only_flag       = l_validate_only_flag,
               oracle_inventory_item_id = CASE
                                              WHEN l_return_status = c_return_success
                                                   AND l_validate_only_flag = 'N'
                                              THEN l_inventory_item_id
                                              ELSE oracle_inventory_item_id
                                           END,
               oracle_organization_id   = CASE
                                              WHEN l_return_status = c_return_success
                                                   AND l_validate_only_flag = 'N'
                                              THEN l_organization_id
                                              ELSE oracle_organization_id
                                           END,
               api_return_status        = l_return_status,
               api_message_count        = l_msg_count,
               api_message_text         = l_message,
               api_processed_date       = SYSDATE,
               last_updated_by          = f_get_session_user,
               last_update_date         = SYSDATE,
               last_update_login        = NVL(SYS_CONTEXT('APEX$SESSION', 'APP_SESSION'), USER)
         WHERE item_creation_stg_id = p_item_creation_stg_id;

        pcd_write_log(
            'PCD_CALL_ITEM_API',
            'Staging row updated. ITEM_CREATION_STG_ID=' || p_item_creation_stg_id ||
            ', NEW_REQUEST_STATUS=' || l_new_request_status ||
            ', ROWCOUNT=' || SQL%ROWCOUNT
        );

        x_return_status := l_return_status;
        x_message       := l_message;

        IF l_commit_flag = 'Y' THEN
            COMMIT;
            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'Commit completed for ITEM_CREATION_STG_ID=' || p_item_creation_stg_id || '.'
            );
        ELSE
            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'Commit skipped because COMMIT_FLAG=N. Caller is responsible for commit or rollback.'
            );
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

            pcd_write_log(
                'PCD_CALL_ITEM_API',
                'No staging row found. ITEM_CREATION_STG_ID=' || NVL(TO_CHAR(p_item_creation_stg_id), 'NULL')
            );

            IF l_commit_flag = 'Y' THEN
                COMMIT;
            END IF;

        WHEN OTHERS THEN
            l_error_text := 'Unexpected error in PCD_CALL_ITEM_API. ITEM_CREATION_STG_ID=' ||
                            NVL(TO_CHAR(p_item_creation_stg_id), 'NULL') ||
                            ', SQLERRM=' || SQLERRM ||
                            ', BACKTRACE=' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;

            pcd_write_log('PCD_CALL_ITEM_API', l_error_text);

            BEGIN
                ROLLBACK TO xinv_before_item_api;
                pcd_write_log(
                    'PCD_CALL_ITEM_API',
                    'Rollback to savepoint completed after unexpected error.'
                );
            EXCEPTION
                WHEN OTHERS THEN
                    pcd_write_log(
                        'PCD_CALL_ITEM_API',
                        'Rollback to savepoint was not available or failed. Error: ' || SQLERRM
                    );
            END;

            x_return_status := c_return_unexpected;
            DBMS_LOB.CREATETEMPORARY(l_error_clob, TRUE);
            pcd_append_text(l_error_clob, l_error_text);
            x_message := l_error_clob;

            BEGIN
                UPDATE xinv_item_creation_stg
                   SET request_status     = c_status_error,
                       api_return_status  = x_return_status,
                       api_message_count  = 1,
                       api_message_text   = x_message,
                       api_processed_date = SYSDATE,
                       last_updated_by    = f_get_session_user,
                       last_update_date   = SYSDATE,
                       last_update_login  = NVL(SYS_CONTEXT('APEX$SESSION', 'APP_SESSION'), USER)
                 WHERE item_creation_stg_id = p_item_creation_stg_id;

                pcd_write_log(
                    'PCD_CALL_ITEM_API',
                    'Staging row marked as ERROR after unexpected exception. ROWCOUNT=' || SQL%ROWCOUNT
                );

                IF l_commit_flag = 'Y' THEN
                    COMMIT;
                    pcd_write_log(
                        'PCD_CALL_ITEM_API',
                        'Commit completed after error status update.'
                    );
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    pcd_write_log(
                        'PCD_CALL_ITEM_API',
                        'Could not update staging row after exception. Error: ' || SQLERRM
                    );
            END;
    END pcd_call_item_api;

    /******************************************************************************
    AR Global.
    Name:        pcd_process_staging
    Description: Loops through XINV_ITEM_CREATION_STG and calls pcd_call_item_api
                 for each eligible staging row. This procedure is the recommended
                 batch entry point after users submit requests from APEX.

                 Processing order is by ITEM_CREATION_STG_ID. When p_max_rows is
                 provided, the procedure stops after that number of attempted rows.

    Parameters:  p_request_status       VARCHAR2  Staging status to process.
                 p_request_number       VARCHAR2  Optional specific request number.
                 p_max_rows             NUMBER    Optional maximum number of rows to process.
                 p_validate_only_flag   VARCHAR2  Optional override. Y = validate only,
                                                 N = create/update item.
                 p_user_id              NUMBER    EBS user_id used by APPS.FND_GLOBAL.APPS_INITIALIZE.
                 p_resp_id              NUMBER    EBS responsibility_id used by APPS_INITIALIZE.
                 p_resp_appl_id         NUMBER    EBS responsibility_application_id.
                 p_commit_each_row_flag VARCHAR2  Y = commit each row independently.
                 x_total_count          NUMBER    Total rows attempted.
                 x_success_count        NUMBER    Rows successfully validated/processed.
                 x_error_count          NUMBER    Rows ending in error.
                 x_message              CLOB      Batch execution summary.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.1          13.07.2026  JCALZADILLA    Added detailed PKG_LOG logging
    1.2          13.07.2026  JCALZADILLA    Uses APPS-qualified single-row wrapper
    ******************************************************************************/
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
              FROM xinv_item_creation_stg
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

        pcd_write_log(
            'PCD_PROCESS_STAGING',
            'Start. REQUEST_STATUS=' || NVL(p_request_status, 'NULL') ||
            ', REQUEST_NUMBER=' || NVL(p_request_number, 'NULL') ||
            ', MAX_ROWS=' || NVL(TO_CHAR(p_max_rows), 'NULL') ||
            ', OVERRIDE_VALIDATE_ONLY_FLAG=' || NVL(p_validate_only_flag, 'NULL') ||
            ', COMMIT_EACH_ROW_FLAG=' || NVL(p_commit_each_row_flag, 'NULL')
        );

        pcd_append_text(
            l_summary,
            'Batch started. Request status filter=' || NVL(p_request_status, 'NULL') ||
            ', request number filter=' || NVL(p_request_number, 'NULL') ||
            ', max rows=' || NVL(TO_CHAR(p_max_rows), 'NULL') || '.'
        );

        FOR r IN c_staging LOOP
            EXIT WHEN p_max_rows IS NOT NULL AND x_total_count >= p_max_rows;

            x_total_count := x_total_count + 1;

            pcd_write_log(
                'PCD_PROCESS_STAGING',
                'Processing row ' || x_total_count || '. REQUEST_NUMBER=' || r.request_number ||
                ', ITEM_CREATION_STG_ID=' || r.item_creation_stg_id ||
                ', ITEM_NUMBER=' || r.item_number
            );

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
                pcd_write_log(
                    'PCD_PROCESS_STAGING',
                    'Row completed successfully. REQUEST_NUMBER=' || r.request_number ||
                    ', ITEM_CREATION_STG_ID=' || r.item_creation_stg_id
                );
            ELSE
                x_error_count := x_error_count + 1;
                pcd_write_log(
                    'PCD_PROCESS_STAGING',
                    'Row completed with error. REQUEST_NUMBER=' || r.request_number ||
                    ', ITEM_CREATION_STG_ID=' || r.item_creation_stg_id ||
                    ', RETURN_STATUS=' || NVL(l_row_status, 'NULL')
                );
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

        pcd_write_log(
            'PCD_PROCESS_STAGING',
            'End. TOTAL_COUNT=' || x_total_count ||
            ', SUCCESS_COUNT=' || x_success_count ||
            ', ERROR_COUNT=' || x_error_count
        );

        IF UPPER(NVL(p_commit_each_row_flag, 'Y')) <> 'Y' THEN
            COMMIT;
            pcd_write_log(
                'PCD_PROCESS_STAGING',
                'Final commit completed because COMMIT_EACH_ROW_FLAG was not Y.'
            );
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

END xinv_item_api_pkg;
/
SHOW ERRORS
