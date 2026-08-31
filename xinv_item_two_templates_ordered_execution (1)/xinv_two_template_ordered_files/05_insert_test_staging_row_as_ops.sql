/* ============================================================
   AR Global - Test Staging Row
   Purpose:
   - Insert one test request using ITEM_TYPE_ID = 1.
   - One staging row contains both the master template and the target template.

   Run as OPS after the package compiles.
   ============================================================ */

DELETE FROM xinv_item_creation_stg
 WHERE request_number = 'REQ-MH-94904-992-GRI-001';

INSERT INTO xinv_item_creation_stg (
    request_number,
    request_status,
    item_type_id,
    api_transaction_type,
    validate_only_flag,
    base_part_number,
    item_number,
    part_status,
    item_description,
    long_description,
    primary_uom_code,
    item_status_code,
    master_org_code,
    master_template_name,
    target_org_code,
    target_template_name,
    legacy_template_name,
    outside_processing_flag,
    planner_code,
    division,
    business_unit,
    cost_rollup_requested_flag,
    engineering_status,
    pdr_number,
    tsr_number,
    ucm_content_id,
    inventory_class,
    inventory_item_flag,
    revision_control_flag,
    stockable_flag,
    reservable_flag,
    transactable_flag,
    check_material_shortage_flag,
    cycle_count_enabled_flag,
    purchasing_enabled_flag,
    customer_order_flag,
    shippable_flag,
    invoiceable_flag,
    bom_enabled_flag,
    build_in_wip_flag,
    costing_enabled_flag,
    inventory_asset_flag,
    created_by,
    creation_date,
    last_updated_by,
    last_update_date,
    last_update_login,
    record_version_number
)
VALUES (
    'REQ-MH-94904-992-GRI-001',
    'DRAFT',
    1,
    'CREATE',
    'N',
    'MH-94904-992',
    'MH-94904-992',
    'New',
    'Test item created from APEX staging - two template flow',
    'Test item created from APEX staging - master organization and target organization assignment.',
    'TFT',
    'Active',
    'MAS',
    'GLOBAL ITEM',
    'GRI',
    'ADHESIVES',
    NULL,
    'N',
    NULL,
    'ARcare',
    'Medical',
    'N',
    'ENGINEER',
    NULL,
    NULL,
    NULL,
    'WIP',
    'Y',
    'N',
    'Y',
    'N',
    'Y',
    'Y',
    'Y',
    'N',
    'N',
    'N',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER),
    SYSDATE,
    NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER),
    SYSDATE,
    NVL(SYS_CONTEXT('APEX$SESSION', 'APP_SESSION'), USER),
    1
);

COMMIT;

SELECT
    item_creation_stg_id,
    request_number,
    request_status,
    item_type_id,
    item_number,
    primary_uom_code,
    master_org_code,
    master_template_name,
    target_org_code,
    target_template_name
FROM xinv_item_creation_stg
WHERE request_number = 'REQ-MH-94904-992-GRI-001';
