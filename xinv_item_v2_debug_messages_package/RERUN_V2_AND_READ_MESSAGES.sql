/* ============================================================
   AR Global - Re-run V2 item API and read target error details
   Replace the staging id when needed.
   ============================================================ */

DECLARE
    l_return_status VARCHAR2(10);
    l_message       CLOB;
BEGIN
    apps.xinv_item_api_pkg_v2.pcd_call_item_api(
        p_item_creation_stg_id => 5,
        p_validate_only_flag   => 'N',
        p_user_id              => NULL,
        p_resp_id              => NULL,
        p_resp_appl_id         => NULL,
        p_commit_flag          => 'Y',
        x_return_status        => l_return_status,
        x_message              => l_message
    );
END;
/

SELECT
    item_creation_stg_id,
    request_status,
    item_number,
    master_org_code,
    master_template_name,
    master_api_return_status,
    master_api_message_count,
    DBMS_LOB.SUBSTR(master_api_message_text, 4000, 1) AS master_message,
    target_org_code,
    target_template_name,
    target_api_return_status,
    target_api_message_count,
    DBMS_LOB.SUBSTR(target_api_message_text, 4000, 1) AS target_message,
    api_return_status,
    api_message_count,
    DBMS_LOB.SUBSTR(api_message_text, 4000, 1) AS overall_message
FROM ops.xinv_item_creation_stg_v2
WHERE item_creation_stg_id = 5;

SELECT
    mp.organization_code,
    msi.organization_id,
    msi.inventory_item_id,
    msik.concatenated_segments AS item_number,
    msi.description,
    msi.primary_uom_code,
    msi.inventory_item_status_code,
    msi.creation_date
FROM apps.mtl_system_items_b msi
JOIN apps.mtl_system_items_kfv msik
  ON msik.inventory_item_id = msi.inventory_item_id
 AND msik.organization_id   = msi.organization_id
JOIN apps.mtl_parameters mp
  ON mp.organization_id = msi.organization_id
WHERE UPPER(TRIM(msik.concatenated_segments)) = UPPER(TRIM('MH-94904-993'))
ORDER BY mp.organization_code;
