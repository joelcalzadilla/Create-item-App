-- =====================================================================
-- JCALZADILLA - 22.08.2026 - START CHANGE
-- Purpose:
-- Restructure ADRE_INV_ITEM_REQUEST_ORG so Oracle EBS becomes the
-- system of record for Inventory Organizations and Item Templates.
--
-- The previous application-owned references are removed:
--
--   ITEM_ORG_ID
--   ITEM_TEMPLATE_ID
--
-- They are replaced with direct Oracle EBS identifiers:
--
--   EBS_ORGANIZATION_ID
--   EBS_TEMPLATE_ID
--
-- The table currently contains no transactional records, therefore no
-- data migration is required.
--
-- No foreign keys are created against Oracle EBS base tables.
-- =====================================================================


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Add the direct Oracle EBS Inventory Organization identifier.
--
-- Every Request Organization must identify an Oracle EBS Inventory
-- Organization.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD
(
    ebs_organization_id NUMBER NOT NULL
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Add the direct Oracle EBS Item Template identifier.
--
-- The value remains nullable because the template may not yet be
-- resolved while the Item Request is in Draft status.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD
(
    ebs_template_id NUMBER
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the obsolete application-owned Inventory Organization
-- reference.
--
-- CASCADE CONSTRAINTS removes constraints that depend directly on
-- ITEM_ORG_ID, including the previous Request / Organization
-- uniqueness definition.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP COLUMN item_org_id CASCADE CONSTRAINTS;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the obsolete application-owned Item Template reference.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP COLUMN item_template_id CASCADE CONSTRAINTS;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Require a valid positive Oracle EBS Inventory Organization ID.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD CONSTRAINT adre_inv_item_req_org_ck6
CHECK
(
    ebs_organization_id > 0
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Require a positive Oracle EBS Item Template ID when populated.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD CONSTRAINT adre_inv_item_req_org_ck7
CHECK
(
    ebs_template_id IS NULL
    OR ebs_template_id > 0
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Prevent the same Oracle EBS Inventory Organization from being
-- assigned more than once to the same Item Request.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD CONSTRAINT adre_inv_item_req_org_u1
UNIQUE
(
    item_request_id,
    ebs_organization_id
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Recreate the Organization / Assignment Status index using the
-- direct Oracle EBS Inventory Organization identifier.
-- =====================================================================

CREATE INDEX ops.adre_inv_item_req_org_n3
    ON ops.adre_inv_item_request_org
    (
        ebs_organization_id,
        assignment_status
    );


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Support searches and processing by the resolved Oracle EBS Item
-- Template identifier.
-- =====================================================================

CREATE INDEX ops.adre_inv_item_req_org_n5
    ON ops.adre_inv_item_request_org
    (
        ebs_template_id
    );


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Update table documentation for the final direct Oracle EBS model.
-- =====================================================================

COMMENT ON TABLE ops.adre_inv_item_request_org IS
'Associates an Item Request with an Oracle EBS Inventory Organization. Stores MASTER or TARGET role, resolved Oracle EBS Item Template, Oracle EBS Inventory Item identifier and organization-level processing status.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Document the direct Oracle EBS Inventory Organization identifier.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_request_org.ebs_organization_id IS
'Oracle EBS Inventory Organization identifier assigned to the Item Request. Oracle EBS is the system of record for Inventory Organizations.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Document the direct Oracle EBS Item Template identifier.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_request_org.ebs_template_id IS
'Identifier of the existing Oracle EBS Item Template resolved for this Request Organization. NULL is allowed until template resolution is complete.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate the new Oracle EBS reference columns.
--
-- Expected:
--
-- EBS_ORGANIZATION_ID   NUMBER   NULLABLE = N
-- EBS_TEMPLATE_ID       NUMBER   NULLABLE = Y
-- =====================================================================

SELECT
    column_name,
    data_type,
    nullable
FROM all_tab_columns
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
  AND column_name IN
      (
          'EBS_ORGANIZATION_ID',
          'EBS_TEMPLATE_ID'
      )
ORDER BY column_id;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Confirm that the obsolete application-owned reference columns no
-- longer exist.
--
-- Expected result:
-- 0 rows
-- =====================================================================

SELECT
    column_name
FROM all_tab_columns
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
  AND column_name IN
      (
          'ITEM_ORG_ID',
          'ITEM_TEMPLATE_ID'
      );


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate the foreign keys owned by REQUEST_ORG.
--
-- Expected result:
--
-- ITEM_REQUEST_ID -> ADRE_INV_ITEM_REQUEST
--
-- There must be no foreign key to:
--
--   ADRE_INV_ITEM_ORG
--   ADRE_INV_ITEM_TEMPLATE
-- =====================================================================

SELECT
    c.constraint_name,
    cc.column_name,
    r.table_name AS referenced_table
FROM all_constraints c
JOIN all_cons_columns cc
  ON cc.owner = c.owner
 AND cc.constraint_name = c.constraint_name
JOIN all_constraints r
  ON r.owner = c.r_owner
 AND r.constraint_name = c.r_constraint_name
WHERE c.owner = 'OPS'
  AND c.table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
  AND c.constraint_type = 'R'
ORDER BY
    c.constraint_name,
    cc.position;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate that child tables still reference REQUEST_ORG_ID.
--
-- Expected child tables:
--
--   ADRE_INV_ITEM_CATEGORY
--   ADRE_INV_ITEM_ATTR_VALUE
--   ADRE_INV_ITEM_DOCUMENT
--   ADRE_INV_ITEM_BOM
--   ADRE_INV_ITEM_API_LOG
--
-- Expected result:
-- 5 rows
-- =====================================================================

SELECT
    c.table_name AS child_table,
    c.constraint_name
FROM all_constraints c
JOIN all_constraints r
  ON r.owner = c.r_owner
 AND r.constraint_name = c.r_constraint_name
WHERE c.owner = 'OPS'
  AND c.constraint_type = 'R'
  AND r.owner = 'OPS'
  AND r.table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
ORDER BY c.table_name;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate the indexes affected by the restructuring.
--
-- Expected:
--
-- ADRE_INV_ITEM_REQ_ORG_N3   VALID
-- ADRE_INV_ITEM_REQ_ORG_N5   VALID
-- ADRE_INV_ITEM_REQ_ORG_U2   VALID
--
-- U2 is the existing function-based unique index that limits each
-- Item Request to one MASTER organization.
-- =====================================================================

SELECT
    index_name,
    uniqueness,
    status
FROM all_indexes
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
  AND index_name IN
      (
          'ADRE_INV_ITEM_REQ_ORG_N3',
          'ADRE_INV_ITEM_REQ_ORG_N5',
          'ADRE_INV_ITEM_REQ_ORG_U2'
      )
ORDER BY index_name;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate that the existing audit and normalization trigger remains
-- enabled.
--
-- Expected:
-- ADRE_INV_ITEM_REQ_ORG_BIU = ENABLED
-- =====================================================================

SELECT
    owner,
    trigger_name,
    table_name,
    status
FROM all_triggers
WHERE owner = 'OPS'
  AND trigger_name = 'ADRE_INV_ITEM_REQ_ORG_BIU';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Check for trigger compilation errors.
--
-- Expected result:
-- 0 rows
-- =====================================================================

SELECT
    line,
    position,
    text
FROM all_errors
WHERE owner = 'OPS'
  AND name = 'ADRE_INV_ITEM_REQ_ORG_BIU'
  AND type = 'TRIGGER'
ORDER BY sequence;


-- =====================================================================
-- JCALZADILLA - 22.08.2026 - END CHANGE
-- =====================================================================