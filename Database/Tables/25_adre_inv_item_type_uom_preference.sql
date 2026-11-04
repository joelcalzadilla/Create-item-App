-- Adhesives Research
-- Script  : 25_adre_inv_item_type_uom_preference.sql
-- Purpose : Mark one active default UOM per item type and user UOM system.
-- Order   : 25. Run once after Tables/24.
-- Requires: OPS.ADRE_INV_ITEM_TYPE_UOM.
-- Existing rows and UOM permissions are preserved. Configuration follows separately.

ALTER TABLE ops.adre_inv_item_type_uom
    ADD (default_uom_system VARCHAR2(20));

ALTER TABLE ops.adre_inv_item_type_uom
    ADD CONSTRAINT adre_inv_item_type_uom_c4
    CHECK (default_uom_system IN ('IMPERIAL', 'METRIC'));

CREATE UNIQUE INDEX ops.adre_inv_item_type_uom_u2
    ON ops.adre_inv_item_type_uom
    (
        CASE
            WHEN active_flag = 'Y' AND default_uom_system IS NOT NULL
            THEN item_type_id
        END,
        CASE
            WHEN active_flag = 'Y' AND default_uom_system IS NOT NULL
            THEN default_uom_system
        END
    );

COMMENT ON COLUMN ops.adre_inv_item_type_uom.default_uom_system IS
    'IMPERIAL or METRIC selects this active UOM as the default for the item type and the user preference; NULL means selectable but not a default.';

