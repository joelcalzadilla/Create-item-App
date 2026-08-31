/* ============================================================
   AR Global - Manual Test Call and Validation
   Purpose:
   - Manually call APPS.XINV_ITEM_API_PKG for the test request.
   - Validate that the item exists in MAS and GRI after the package runs.

   Run from OPS, APPS, or another schema that has execute privilege.
   If using SQL Developer, run as script/F5 to see DBMS_OUTPUT.
   If using APEX SQL Workshop, remove SET SERVEROUTPUT if it causes ORA-00922.
   ============================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    l_item_creation_stg_id NUMBER;
    l_return_status        VARCHAR2(10);
    l_message              CLOB;
BEGIN
    SELECT item_creation_stg_id
      INTO l_item_creation_stg_id
      FROM xinv_item_creation_stg
     WHERE request_number = 'REQ-MH-94904-992-GRI-001';

    apps.xinv_item_api_pkg.pcd_call_item_api(
        p_item_creation_stg_id => l_item_creation_stg_id,
        p_validate_only_flag   => 'N',
        p_user_id              => NULL,
        p_resp_id              => NULL,
        p_resp_appl_id         => NULL,
        p_commit_flag          => 'Y',
        x_return_status        => l_return_status,
        x_message              => l_message
    );

    DBMS_OUTPUT.PUT_LINE('ITEM_CREATION_STG_ID: ' || l_item_creation_stg_id);
    DBMS_OUTPUT.PUT_LINE('RETURN_STATUS: ' || l_return_status);
    DBMS_OUTPUT.PUT_LINE('MESSAGE: ' || DBMS_LOB.SUBSTR(l_message, 4000, 1));
END;
/

PROMPT ============================================================
PROMPT Staging API result
PROMPT ============================================================

SELECT
    item_creation_stg_id,
    request_number,
    request_status,
    item_number,
    master_org_code,
    master_template_name,
    master_inventory_item_id,
    master_organization_id,
    master_api_return_status,
    DBMS_LOB.SUBSTR(master_api_message_text, 1000, 1) AS master_message,
    target_org_code,
    target_template_name,
    target_inventory_item_id,
    target_organization_id,
    target_api_return_status,
    DBMS_LOB.SUBSTR(target_api_message_text, 1000, 1) AS target_message,
    api_return_status,
    DBMS_LOB.SUBSTR(api_message_text, 2000, 1) AS overall_message
FROM xinv_item_creation_stg
WHERE request_number = 'REQ-MH-94904-992-GRI-001';

PROMPT ============================================================
PROMPT EBS item validation. Expected result: MAS and GRI.
PROMPT ============================================================

SELECT
    mp.organization_code,
    msi.organization_id,
    msi.inventory_item_id,
    msik.concatenated_segments AS item_number,
    msi.description,
    msi.inventory_item_status_code,
    msi.creation_date
FROM apps.mtl_system_items_b msi
JOIN apps.mtl_system_items_kfv msik
  ON msik.inventory_item_id = msi.inventory_item_id
 AND msik.organization_id   = msi.organization_id
JOIN apps.mtl_parameters mp
  ON mp.organization_id = msi.organization_id
WHERE UPPER(TRIM(msik.concatenated_segments)) = UPPER(TRIM('MH-94904-992'))
ORDER BY mp.organization_code;
