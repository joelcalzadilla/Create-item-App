/* ============================================================
   APEX Button Process V2 - Send Item to EBS
   Process Type: Execute Code / PL/SQL Code
   Point: After Submit
   Server-side Condition: When Button Pressed = SEND_ITEM

   Replace PXX_*_V2 page item names with your real APEX page item names.
   ============================================================ */

DECLARE
    l_return_status VARCHAR2(10);
    l_message       CLOB;
BEGIN
    apps.xinv_item_api_pkg_v2.pcd_call_item_api(
        p_item_creation_stg_id => :PXX_ITEM_CREATION_STG_ID_V2,
        p_validate_only_flag   => 'N',
        p_user_id              => NULL,
        p_resp_id              => NULL,
        p_resp_appl_id         => NULL,
        p_commit_flag          => 'Y',
        x_return_status        => l_return_status,
        x_message              => l_message
    );

    :PXX_API_RETURN_STATUS_V2 := l_return_status;
    :PXX_API_MESSAGE_V2       := DBMS_LOB.SUBSTR(l_message, 4000, 1);

    IF l_return_status <> 'S' THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Item API process failed. ' || DBMS_LOB.SUBSTR(l_message, 3000, 1)
        );
    END IF;
END;
