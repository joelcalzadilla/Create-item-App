/* ============================================================
   XINV ITEM CREATION - SAMPLE DATA SCRIPT
   Purpose:
   - Insert item type setup rows.
   - Insert one sample item creation staging request based on the
     ARGR Adhesive Coating example observed in the screenshot/video context.

   Important:
   - Primary keys are intentionally omitted to let the identity columns assign them.
   - Audit columns are intentionally omitted to let the audit triggers assign them.
   ============================================================ */

SET DEFINE OFF

PROMPT ============================================================
PROMPT Inserting sample item types
PROMPT ============================================================

INSERT INTO xinv_item_types (
    item_type_code,
    item_type_name,
    item_type_description,
    default_template_name,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_target_org_code,
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
    active_flag
)
VALUES (
    'ADHESIVE_COATING',
    'Adhesive Coating',
    'Item type used for ARGR adhesive coating item creation. Based on the visible ARGR Adhesive Coating form and the EBS Engineering Item Inventory tab.',
    'ARGR Adhesive Coating',
    'TFT',
    'Active',
    'New',
    'MAS',
    'GRI',
    'ARcare',
    'Medical',
    'WIP - Work In Process',
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
    'Y'
);

INSERT INTO xinv_item_types (
    item_type_code,
    item_type_name,
    item_type_description,
    default_template_name,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_target_org_code,
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
    active_flag
)
VALUES (
    'RAW_MATERIAL',
    'Raw Material Item',
    'Generic raw material item type placeholder. Defaults must be confirmed against AR Global item setup rules.',
    'Raw Material',
    'EA',
    'Active',
    'New',
    'MAS',
    'GRI',
    'N',
    'N',
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
    'N',
    'N',
    'N',
    'Y',
    'Y',
    'Y'
);

INSERT INTO xinv_item_types (
    item_type_code,
    item_type_name,
    item_type_description,
    default_template_name,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_target_org_code,
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
    active_flag
)
VALUES (
    'SLIT_CUSTOMER_SERVICE',
    'Slit Item from Customer Service',
    'Slit item request normally initiated from Customer Service. Defaults must be confirmed with AR Global.',
    'Slit Item',
    'EA',
    'Active',
    'New',
    'MAS',
    'GRI',
    'Y',
    'Y',
    'N',
    'N',
    'N',
    'N',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    'Y',
    'Y'
);

INSERT INTO xinv_item_types (
    item_type_code,
    item_type_name,
    item_type_description,
    default_template_name,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_target_org_code,
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
    active_flag
)
VALUES (
    'SLIT_ENGINEERING',
    'Slit Item from Engineering',
    'Slit item request normally initiated from Engineering. Defaults must be confirmed with AR Global.',
    'Slit Item',
    'EA',
    'Active',
    'New',
    'MAS',
    'GRI',
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
    'Y',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    'Y',
    'Y'
);

INSERT INTO xinv_item_types (
    item_type_code,
    item_type_name,
    item_type_description,
    default_template_name,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_target_org_code,
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
    active_flag
)
VALUES (
    'ADHESIVES_FORMULATIONS_PRIMERS',
    'Adhesives / Formulations / Primers',
    'Generic formulation, adhesive, or primer item type placeholder. Defaults must be confirmed with AR Global.',
    'Formulation Item',
    'LBS',
    'Active',
    'New',
    'MAS',
    'GRI',
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
    'N',
    'N',
    'Y',
    'Y',
    'Y',
    'Y',
    'Y'
);

INSERT INTO xinv_item_types (
    item_type_code,
    item_type_name,
    item_type_description,
    default_template_name,
    default_primary_uom_code,
    default_item_status_code,
    default_part_status,
    default_master_org_code,
    default_target_org_code,
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
    active_flag
)
VALUES (
    'LINER_COATING',
    'Liner Coating Item',
    'Generic liner coating item type placeholder. Defaults must be confirmed with AR Global.',
    'Liner Coating',
    'TFT',
    'Active',
    'New',
    'MAS',
    'GRI',
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
    'Y'
);

PROMPT ============================================================
PROMPT Inserting sample item creation request
PROMPT ============================================================

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
    template_name,

    master_org_code,
    target_org_code,

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

    lot_expiration_control,
    shelf_life_days,
    retest_interval_days,
    expiration_action_interval,
    expiration_action_code,

    lot_control_code,
    lot_starting_prefix,
    lot_starting_number,
    lot_maturity_days,
    lot_hold_days,

    serial_generation_control,
    serial_tagging_enabled_flag,
    serial_starting_prefix,
    serial_starting_number,

    grade_controlled_flag,
    default_grade,

    locator_control_code,
    restrict_subinventories_flag,
    restrict_locators_flag,

    material_classification_type,
    material_classification_control,

    category_set_name,
    category_name,

    bom_step1_item1_number,
    bom_step1_item1_qty,
    bom_step1_item1_uom_code,
    bom_step1_item1_theoretical_qty,

    bom_step1_item2_number,
    bom_step1_item2_qty,
    bom_step1_item2_uom_code,
    bom_step1_item2_theoretical_qty,

    bom_step1_item3_number,
    bom_step1_item3_qty,
    bom_step1_item3_uom_code,
    bom_step1_item3_theoretical_qty,

    bom_step1_copy_from
)
SELECT
    'REQ-ADH-000001',
    'DRAFT',
    item_type_id,
    'CREATE',
    'Y',

    'MH-94904-990',
    'MH-94904-990',
    'New',
    'ARSEAL 94904 (29.0")(27.5" MIN ADHESIVE WIDTH)',
    'ARSEAL 94904 (29.0")(27.5" MIN ADHESIVE WIDTH)',
    'TFT',
    'Active',
    'ARGR Adhesive Coating',

    'MAS',
    'GRI',

    'N',
    NULL,
    'ARcare',
    'Medical',
    'N',
    'PDR',
    NULL,
    NULL,
    NULL,
    'WIP - Work In Process',

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

    'Shelf life days',
    360,
    NULL,
    NULL,
    NULL,

    'Full Control',
    NULL,
    NULL,
    NULL,
    NULL,

    'No Control',
    'N',
    NULL,
    NULL,

    'N',
    NULL,

    'No Control',
    'N',
    'N',

    NULL,
    'No Control',

    NULL,
    NULL,

    'R-12904-971',
    1200,
    'FT',
    NULL,

    'A-5487-0',
    58,
    'LBS',
    NULL,

    'R-12936-973',
    132,
    'LBS',
    NULL,

    NULL
FROM xinv_item_types
WHERE item_type_code = 'ADHESIVE_COATING';

COMMIT;

PROMPT ============================================================
PROMPT Validation queries
PROMPT ============================================================

SELECT
    item_type_id,
    item_type_code,
    item_type_name,
    default_template_name,
    default_primary_uom_code,
    default_master_org_code,
    default_target_org_code,
    active_flag
FROM xinv_item_types
ORDER BY item_type_id;

SELECT
    s.item_creation_stg_id,
    s.request_number,
    s.request_status,
    t.item_type_code,
    s.item_number,
    s.item_description,
    s.primary_uom_code,
    s.master_org_code,
    s.target_org_code,
    s.lot_expiration_control,
    s.shelf_life_days,
    s.lot_control_code,
    s.serial_generation_control,
    s.created_by,
    s.creation_date
FROM xinv_item_creation_stg s
JOIN xinv_item_types t
  ON t.item_type_id = s.item_type_id
ORDER BY s.item_creation_stg_id;

PROMPT ============================================================
PROMPT Sample data completed
PROMPT ============================================================
