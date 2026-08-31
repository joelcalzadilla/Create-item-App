CREATE OR REPLACE PACKAGE xinv_item_api_pkg AS
/******************************************************************************
AR Global.
NAME:     xinv_item_api_pkg
PURPOSE:  Package used by the APEX item creation process for AR Global.
          It reads item creation requests from XINV_ITEM_CREATION_STG,
          initializes the EBS application context when requested, writes detailed
          process logs through PKG_LOG, and calls EGO_ITEM_PUB.PROCESS_ITEM
          through a controlled wrapper.

          The package is intentionally designed as a staging-to-API layer:
          APEX should insert and validate the request in staging first, and
          this package should be the only code path that calls the EBS item API.

REVIEWS:
Version        Date        Author           Description
---------  ----------  ---------------  ------------------------------------
1.0        13.07.2026  JCALZADILLA      First version
1.1        13.07.2026  JCALZADILLA      Added detailed PKG_LOG logging
******************************************************************************/

    /******************************************************************************
    AR Global.
    Name:        pcd_call_item_api
    Description: Calls EGO_ITEM_PUB.PROCESS_ITEM for one item creation staging row.
                 The procedure reads one row from XINV_ITEM_CREATION_STG, maps the
                 staging columns to the minimum controlled API parameters, executes
                 the API, captures the API return status and messages, logs the
                 execution details through PKG_LOG, and updates the staging row with
                 the API result.

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
                 p_user_id               NUMBER    EBS user_id used by FND_GLOBAL.APPS_INITIALIZE.
                 p_resp_id               NUMBER    EBS responsibility_id used by APPS_INITIALIZE.
                 p_resp_appl_id          NUMBER    EBS responsibility_application_id.
                 p_commit_flag           VARCHAR2  Y = commit staging/API result, N = caller controls commit.
                 x_return_status         VARCHAR2  API return status: S, E, U.
                 x_message               CLOB      Aggregated API message text.

    Version      Date        Author         Description
    ---------    ----------  -------------  ------------------------------------
    1.0          13.07.2026  JCALZADILLA    First version
    1.1          13.07.2026  JCALZADILLA    Added detailed PKG_LOG logging
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
                 p_user_id              NUMBER    EBS user_id used by FND_GLOBAL.APPS_INITIALIZE.
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
