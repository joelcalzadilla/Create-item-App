SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ============================================================
PROMPT Test 1: Validate one staging row without creating the item
PROMPT ============================================================

DECLARE
    l_return_status VARCHAR2(10);
    l_message       CLOB;
BEGIN
    xinv_item_api_pkg.pcd_call_item_api(
        p_item_creation_stg_id => 1,
        p_validate_only_flag   => 'Y',
        p_user_id              => NULL, -- Replace with the EBS FND_USER.USER_ID when available.
        p_resp_id              => NULL, -- Replace with the EBS responsibility_id when available.
        p_resp_appl_id         => NULL, -- Replace with the EBS responsibility_application_id when available.
        p_commit_flag          => 'Y',
        x_return_status        => l_return_status,
        x_message              => l_message
    );

    DBMS_OUTPUT.PUT_LINE('Return status: ' || NVL(l_return_status, 'NULL'));
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_message, 4000, 1));
END;
/

PROMPT ============================================================
PROMPT Test 2: Process all submitted rows in validate-only mode
PROMPT ============================================================

DECLARE
    l_total_count   NUMBER;
    l_success_count NUMBER;
    l_error_count   NUMBER;
    l_message       CLOB;
BEGIN
    xinv_item_api_pkg.pcd_process_staging(
        p_request_status        => 'SUBMITTED',
        p_request_number        => NULL,
        p_max_rows              => NULL,
        p_validate_only_flag    => 'Y',
        p_user_id               => NULL, -- Replace with the EBS FND_USER.USER_ID when available.
        p_resp_id               => NULL, -- Replace with the EBS responsibility_id when available.
        p_resp_appl_id          => NULL, -- Replace with the EBS responsibility_application_id when available.
        p_commit_each_row_flag  => 'Y',
        x_total_count           => l_total_count,
        x_success_count         => l_success_count,
        x_error_count           => l_error_count,
        x_message               => l_message
    );

    DBMS_OUTPUT.PUT_LINE('Total count:   ' || l_total_count);
    DBMS_OUTPUT.PUT_LINE('Success count: ' || l_success_count);
    DBMS_OUTPUT.PUT_LINE('Error count:   ' || l_error_count);
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_message, 4000, 1));
END;
/
