-- Adhesives Research
-- Script  : 27_adre_inv_item_request_org_uom.sql
-- Purpose : Store the user-selected and EBS-resolved primary UOM per request organization.
-- Order   : 27. Run once after Tables/26.
-- Requires: OPS.ADRE_INV_ITEM_REQUEST_ORG.
-- Existing rows remain unchanged. The legacy request-header primary UOM is preserved.

ALTER TABLE ops.adre_inv_item_request_org
    ADD
    (
        primary_uom_code     VARCHAR2(30),
        ebs_primary_uom_code VARCHAR2(30)
    );

COMMENT ON COLUMN ops.adre_inv_item_request_org.primary_uom_code IS
    'Primary UOM selected in APEX for this request organization before EBS organization-specific resolution; NULL for historical requests until migrated or resolved.';

COMMENT ON COLUMN ops.adre_inv_item_request_org.ebs_primary_uom_code IS
    'Primary UOM resolved for EBS in this organization. Preserves the result used by processing and supports verification or safe retries.';
