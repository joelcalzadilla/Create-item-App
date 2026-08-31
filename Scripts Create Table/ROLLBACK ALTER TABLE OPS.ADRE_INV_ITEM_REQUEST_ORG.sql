-- =====================================================================
-- JCALZADILLA - 22.08.2026 - START CHANGE
-- Purpose:
-- Roll back the previously executed restructuring of
-- ADRE_INV_ITEM_REQUEST_ORG.
--
-- This rollback restores the original application-owned references:
--
--   ITEM_ORG_ID
--   ITEM_TEMPLATE_ID
--
-- and removes the direct Oracle EBS reference columns:
--
--   EBS_ORGANIZATION_ID
--   EBS_TEMPLATE_ID
--
-- This rollback is safe because ADRE_INV_ITEM_REQUEST_ORG currently
-- contains no transactional records.
--
-- The purpose of this rollback is to restore the original table
-- structure so the restructuring script can be executed again under
-- the correct script name:
--
--   ALTER TABLE OPS.ADRE_INV_ITEM_REQUEST_ORG
-- =====================================================================


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the index created for the direct Oracle EBS Template ID.
-- =====================================================================

DROP INDEX ops.adre_inv_item_req_org_n5;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the index created for the direct Oracle EBS Organization ID.
-- =====================================================================

DROP INDEX ops.adre_inv_item_req_org_n3;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the uniqueness constraint based on EBS_ORGANIZATION_ID.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP CONSTRAINT adre_inv_item_req_org_u1;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the Oracle EBS Organization validation constraint.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP CONSTRAINT adre_inv_item_req_org_ck6;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the Oracle EBS Template validation constraint.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP CONSTRAINT adre_inv_item_req_org_ck7;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the direct Oracle EBS Organization identifier.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP COLUMN ebs_organization_id;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the direct Oracle EBS Item Template identifier.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
DROP COLUMN ebs_template_id;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the original application-owned Inventory Organization
-- reference.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD
(
    item_org_id NUMBER NOT NULL
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the original application-owned Item Template reference.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD
(
    item_template_id NUMBER
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the foreign key to the application Organization
-- configuration table.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD CONSTRAINT adre_inv_item_request_org_fk2
FOREIGN KEY
(
    item_org_id
)
REFERENCES ops.adre_inv_item_org
(
    item_org_id
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the foreign key to the application Item Template
-- configuration table.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD CONSTRAINT adre_inv_item_request_org_fk3
FOREIGN KEY
(
    item_template_id
)
REFERENCES ops.adre_inv_item_template
(
    item_template_id
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the original uniqueness rule.
--
-- The same application Organization cannot be assigned more than once
-- to the same Item Request.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_request_org
ADD CONSTRAINT adre_inv_item_req_org_u1
UNIQUE
(
    item_request_id,
    item_org_id
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the original Organization / Assignment Status index.
-- =====================================================================

CREATE INDEX ops.adre_inv_item_req_org_n3
    ON ops.adre_inv_item_request_org
    (
        item_org_id,
        assignment_status
    );


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore the original table documentation.
-- =====================================================================

COMMENT ON TABLE ops.adre_inv_item_request_org IS
'Associates an Item Request with an application-configured Inventory Organization. Stores MASTER or TARGET role, selected Item Template, Oracle EBS Inventory Item identifier and organization-level processing status.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore documentation for ITEM_ORG_ID.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_request_org.item_org_id IS
'Foreign key identifying the application-configured Inventory Organization assigned to the Item Request.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Restore documentation for ITEM_TEMPLATE_ID.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_request_org.item_template_id IS
'Optional foreign key identifying the application-configured Oracle EBS Item Template selected for this Request Organization.';


COMMIT;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate that the original columns were restored.
--
-- Expected:
--
-- ITEM_ORG_ID        NUMBER   NULLABLE = N
-- ITEM_TEMPLATE_ID   NUMBER   NULLABLE = Y
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
          'ITEM_ORG_ID',
          'ITEM_TEMPLATE_ID'
      )
ORDER BY column_id;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Confirm that the direct Oracle EBS reference columns were removed.
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
          'EBS_ORGANIZATION_ID',
          'EBS_TEMPLATE_ID'
      );


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate the restored foreign keys.
--
-- Expected:
--
-- ITEM_REQUEST_ID    -> ADRE_INV_ITEM_REQUEST
-- ITEM_ORG_ID        -> ADRE_INV_ITEM_ORG
-- ITEM_TEMPLATE_ID   -> ADRE_INV_ITEM_TEMPLATE
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
-- Validate the original Organization index.
--
-- Expected:
-- ADRE_INV_ITEM_REQ_ORG_N3 = VALID
-- =====================================================================

SELECT
    index_name,
    status
FROM all_indexes
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
  AND index_name = 'ADRE_INV_ITEM_REQ_ORG_N3';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Confirm that the one-MASTER-per-request index remains valid.
--
-- Expected:
-- ADRE_INV_ITEM_REQ_ORG_U2 = VALID
-- =====================================================================

SELECT
    index_name,
    status
FROM all_indexes
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_REQUEST_ORG'
  AND index_name = 'ADRE_INV_ITEM_REQ_ORG_U2';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate the existing audit trigger.
--
-- Expected:
-- ADRE_INV_ITEM_REQ_ORG_BIU = ENABLED
-- =====================================================================

SELECT
    trigger_name,
    status
FROM all_triggers
WHERE owner = 'OPS'
  AND trigger_name = 'ADRE_INV_ITEM_REQ_ORG_BIU';


-- =====================================================================
-- JCALZADILLA - 22.08.2026 - END CHANGE
-- =====================================================================