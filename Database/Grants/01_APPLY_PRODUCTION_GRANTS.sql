-- =====================================================================
-- Adhesives Research
-- Oracle EBS Inventory Item Creation
-- Consolidated Cross-Schema Object Grants
-- Date: 2026-10-26
-- Author: Joel Calzadilla
--
-- Sources:
--   * Production grants script dated 2026-09-03 supplied by the user.
--   * Current ALL_SOURCE export pkg.tsv: PACKAGE 42 / PACKAGE BODY 7586 lines.
--   * Current ORG_ORDER validation trigger from the supplied/rebuilt DDL.
--
-- Execution: DBA (or an account authorized to grant all listed privileges).
-- If using schema-owner connections, run section 1 as OPS, section 2 as
-- APPS, and section 3 as DBA or the authorized owner of each resolved EBS
-- object. Keep verification SELECTs in SQL Commands, in the separate file.
--
-- Architecture: OPS owns the application tables and is the APEX parsing
-- schema. APPS owns ADRE_CREATE_INV_ITEM. No privileges are revoked.
-- Existing APPS ANY TABLE system privileges are not modified.
-- =====================================================================

-- SECTION 1: OPS application tables used by APPS.ADRE_CREATE_INV_ITEM.
GRANT INSERT ON ops.adre_inv_item_api_log TO apps;
GRANT INSERT ON ops.adre_inv_item_approval TO apps;
GRANT SELECT, INSERT, UPDATE ON ops.adre_inv_item_attr_value TO apps;
GRANT SELECT ON ops.adre_inv_item_attribute TO apps;
GRANT SELECT ON ops.adre_inv_item_bom TO apps;
GRANT SELECT, UPDATE ON ops.adre_inv_item_category TO apps;
GRANT SELECT ON ops.adre_inv_item_org_cat_set TO apps;
GRANT SELECT ON ops.adre_inv_item_planner_rule TO apps;
GRANT SELECT, INSERT, UPDATE ON ops.adre_inv_item_request TO apps;
GRANT SELECT, INSERT, UPDATE ON ops.adre_inv_item_request_org TO apps;
GRANT SELECT ON ops.adre_inv_item_template_rule TO apps;
GRANT SELECT, UPDATE ON ops.adre_inv_item_type TO apps;
GRANT SELECT ON ops.adre_inv_item_type_attr TO apps;
GRANT SELECT ON ops.adre_inv_item_type_org TO apps;

-- SECTION 2: APEX parsing schema calls the integration package.
GRANT EXECUTE ON apps.adre_create_inv_item TO ops;

-- SECTION 3: EBS reads performed by OPS.ADRE_INV_ITEM_ORG_ORDER_BIU.
-- APPS names may be synonyms. Oracle grants on the resolved base object.
GRANT SELECT ON apps.mtl_parameters TO ops;
GRANT SELECT ON apps.hr_all_organization_units TO ops;
