-- =====================================================================
-- JCALZADILLA - 22.08.2026 - START CHANGE
-- Purpose:
-- Restructure ADRE_INV_ITEM_CATEGORY so Oracle EBS becomes the
-- system of record for Category Sets.
--
-- The previous application-owned Category Set reference is removed:
--
--   ITEM_CAT_SET_ID
--
-- It is replaced with the direct Oracle EBS identifier:
--
--   EBS_CATEGORY_SET_ID
--
-- EBS_CATEGORY_ID continues to identify the selected Oracle EBS
-- Category.
--
-- The table currently contains no transactional records, therefore no
-- data migration is required.
--
-- No foreign key is created against Oracle EBS base tables.
-- =====================================================================


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Add the direct Oracle EBS Category Set identifier.
--
-- Every Category assignment must identify an Oracle EBS Category Set.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_category
ADD
(
    ebs_category_set_id NUMBER NOT NULL
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Remove the obsolete application-owned Category Set reference.
--
-- CASCADE CONSTRAINTS removes constraints that depend directly on
-- ITEM_CAT_SET_ID, including the previous foreign key and uniqueness
-- definition.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_category
DROP COLUMN item_cat_set_id CASCADE CONSTRAINTS;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Require a valid positive Oracle EBS Category Set identifier.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_category
ADD CONSTRAINT adre_inv_item_category_ck4
CHECK
(
    ebs_category_set_id > 0
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Prevent the same Oracle EBS Category Set from being assigned more
-- than once to the same Request Organization.
-- =====================================================================

ALTER TABLE ops.adre_inv_item_category
ADD CONSTRAINT adre_inv_item_category_u1
UNIQUE
(
    request_org_id,
    ebs_category_set_id
);


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Recreate the Category Set / Request Organization index using the
-- direct Oracle EBS Category Set identifier.
-- =====================================================================

CREATE INDEX ops.adre_inv_item_category_n4
    ON ops.adre_inv_item_category
    (
        ebs_category_set_id,
        request_org_id
    );


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Update table documentation for the final direct Oracle EBS model.
-- =====================================================================

COMMENT ON TABLE ops.adre_inv_item_category IS
'Stores Oracle EBS Category assignments for each Item Request Organization. Oracle EBS is the system of record for Category Sets and Categories.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Document the direct Oracle EBS Category Set identifier.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_category.ebs_category_set_id IS
'Oracle EBS Category Set identifier associated with the Category assignment. Oracle EBS is the system of record for Category Sets.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Refresh documentation for the Oracle EBS Category identifier.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_category.ebs_category_id IS
'Oracle EBS Category identifier selected for the Request Organization and Category Set. NULL is allowed while the Item Request remains in Draft status.';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Refresh documentation for the display Category value.
-- =====================================================================

COMMENT ON COLUMN ops.adre_inv_item_category.category_value IS
'Display value of the selected Oracle EBS Category used by the application for review and processing context.';


COMMIT;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate the new Oracle EBS Category Set reference.
--
-- Expected:
--
-- EBS_CATEGORY_SET_ID   NUMBER   NULLABLE = N
-- EBS_CATEGORY_ID       NUMBER   NULLABLE = Y
-- =====================================================================

SELECT
    column_name,
    data_type,
    nullable
FROM all_tab_columns
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_CATEGORY'
  AND column_name IN
      (
          'EBS_CATEGORY_SET_ID',
          'EBS_CATEGORY_ID'
      )
ORDER BY column_id;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Confirm that the obsolete local Category Set reference no longer
-- exists.
--
-- Expected result:
-- 0 rows
-- =====================================================================

SELECT
    column_name
FROM all_tab_columns
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_CATEGORY'
  AND column_name = 'ITEM_CAT_SET_ID';


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate foreign keys owned by ADRE_INV_ITEM_CATEGORY.
--
-- Expected result:
--
-- REQUEST_ORG_ID -> ADRE_INV_ITEM_REQUEST_ORG
--
-- There must be no foreign key to ADRE_INV_ITEM_CAT_SET.
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
  AND c.table_name = 'ADRE_INV_ITEM_CATEGORY'
  AND c.constraint_type = 'R'
ORDER BY
    c.constraint_name,
    cc.position;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate indexes affected by the restructuring.
--
-- Expected:
--
-- ADRE_INV_ITEM_CATEGORY_N1   VALID
-- ADRE_INV_ITEM_CATEGORY_N2   VALID
-- ADRE_INV_ITEM_CATEGORY_N3   VALID
-- ADRE_INV_ITEM_CATEGORY_N4   VALID
-- =====================================================================

SELECT
    index_name,
    uniqueness,
    status
FROM all_indexes
WHERE owner = 'OPS'
  AND table_name = 'ADRE_INV_ITEM_CATEGORY'
ORDER BY index_name;


-- =====================================================================
-- JCALZADILLA - 22.08.2026
-- Validate that the existing audit and normalization trigger remains
-- enabled.
--
-- Expected:
-- ADRE_INV_ITEM_CATEGORY_BIU = ENABLED
-- =====================================================================

SELECT
    owner,
    trigger_name,
    table_name,
    status
FROM all_triggers
WHERE owner = 'OPS'
  AND trigger_name = 'ADRE_INV_ITEM_CATEGORY_BIU';


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
  AND name = 'ADRE_INV_ITEM_CATEGORY_BIU'
  AND type = 'TRIGGER'
ORDER BY sequence;


-- =====================================================================
-- JCALZADILLA - 22.08.2026 - END CHANGE
-- =====================================================================