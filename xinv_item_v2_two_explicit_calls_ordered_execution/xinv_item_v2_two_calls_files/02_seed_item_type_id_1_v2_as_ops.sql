/* ============================================================
   AR Global - Seed Item Type ID 1 V2
   Purpose:
   - Insert one test item type configuration for the two-template flow.
   - User confirmed ITEM_TYPE_ID = 1.

   Run as OPS after 01_create_custom_tables_v2_as_ops.sql.
   ============================================================ */

INSERT INTO xinv_item_types (
    item_type_id,
    item_type_code,
    item_type_name,
    item_type_description,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_master_template_name,
    default_target_org_code,
    default_target_template_name,
    default_division,
    default_business_unit,
    default_inventory_class,
    default_outside_processing_flag,
    requires_bom_flag,
    requires_routing_flag,
    requires_shelf_life_flag,
    requires_lot_control_flag,
    requires_serial_control_flag,
    requires_revision_control_flag,
    requires_cost_rollup_flag,
    requires_engineering_review_flag,
    default_inventory_item_flag,
    default_stockable_flag,
    default_transactable_flag,
    default_purchasing_enabled_flag,
    default_customer_order_flag,
    default_bom_enabled_flag,
    default_build_in_wip_flag,
    default_costing_enabled_flag,
    default_inventory_asset_flag,
    active_flag,
    created_by,
    creation_date,
    last_updated_by,
    last_update_date,
    last_update_login,
    record_version_number
)
VALUES (
    1,
    'ADHESIVE_COATING',
    'Adhesive Coating',
    'AR Global adhesive coating item type used for the initial MAS to GRI item creation test.',
    'TFT',
    'Active',
    'New',
    'MAS',
    'GLOBAL ITEM',
    'GRI',
    'ADHESIVES',
    'ARcare',
    'Medical',
    'WIP',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    'N',
    'N',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    'N',
    'N',
    'Y',
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

PROMPT Item type seed completed. ITEM_TYPE_ID = 1.
