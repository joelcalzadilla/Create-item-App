-- =====================================================================
-- Adhesives Research
-- Script    : ADRE_DEV_CONFIG_RESET_20261007.sql
-- Author    : Joel Calzadilla
-- Date      : 10/07/2026
-- Purpose   : Removes OPS item requests and their dependent rows, then
--             clears the nine configuration tables in development so a
--             production configuration seed can be tested from empty data.
--             This also removes OPS request history and processing logs.
--             EBS inventory items are not changed.
-- Execution : APEX SQL Scripts, development database only.
-- =====================================================================

DECLARE
    l_rows           NUMBER;
    l_external_count NUMBER;
    l_external_fk    VARCHAR2(300);
BEGIN
    -- Stop before deleting anything if a new external child FK is enabled.
    SELECT COUNT(*),
           MIN(allconch.owner || '.' || allconch.table_name || ' -> ' ||
               allconpa.owner || '.' || allconpa.table_name)
      INTO l_external_count,
           l_external_fk
      FROM all_constraints allconch,
           all_constraints allconpa
     WHERE  allconch.constraint_type   = 'R'
       AND  allconch.status            = 'ENABLED'
       AND  allconch.r_owner           = allconpa.owner
       AND  allconch.r_constraint_name = allconpa.constraint_name
       AND  allconpa.owner            = 'OPS'
       AND  allconpa.table_name IN
            (
                'ADRE_INV_ITEM_BOM_COMP', 'ADRE_INV_ITEM_APPROVAL',
                'ADRE_INV_ITEM_API_LOG', 'ADRE_INV_ITEM_ATTR_VALUE',
                'ADRE_INV_ITEM_CATEGORY', 'ADRE_INV_ITEM_DOCUMENT',
                'ADRE_INV_ITEM_BOM', 'ADRE_INV_ITEM_REQUEST_ORG',
                'ADRE_INV_ITEM_REQUEST', 'ADRE_INV_ITEM_TYPE_ATTR',
                'ADRE_INV_ITEM_PLANNER_RULE', 'ADRE_INV_ITEM_TEMPLATE_RULE',
                'ADRE_INV_ITEM_TYPE_ORG', 'ADRE_INV_ITEM_TYPE_UOM',
                'ADRE_INV_ITEM_ATTRIBUTE', 'ADRE_INV_ITEM_SECTION',
                'ADRE_INV_ITEM_TYPE', 'ADRE_INV_ITEM_ORG_CAT_SET'
            )
       AND  (allconch.owner <> 'OPS' OR allconch.table_name NOT IN
            (
                'ADRE_INV_ITEM_BOM_COMP', 'ADRE_INV_ITEM_APPROVAL',
                'ADRE_INV_ITEM_API_LOG', 'ADRE_INV_ITEM_ATTR_VALUE',
                'ADRE_INV_ITEM_CATEGORY', 'ADRE_INV_ITEM_DOCUMENT',
                'ADRE_INV_ITEM_BOM', 'ADRE_INV_ITEM_REQUEST_ORG',
                'ADRE_INV_ITEM_REQUEST', 'ADRE_INV_ITEM_TYPE_ATTR',
                'ADRE_INV_ITEM_PLANNER_RULE', 'ADRE_INV_ITEM_TEMPLATE_RULE',
                'ADRE_INV_ITEM_TYPE_ORG', 'ADRE_INV_ITEM_TYPE_UOM',
                'ADRE_INV_ITEM_ATTRIBUTE', 'ADRE_INV_ITEM_SECTION',
                'ADRE_INV_ITEM_TYPE', 'ADRE_INV_ITEM_ORG_CAT_SET'
            ));

    IF l_external_count <> 0 THEN
        raise_application_error
        (
            -20900,
            'External child FK is not included in DEV reset: ' ||
            l_external_fk || '; COUNT=' || l_external_count
        );
    END IF;

    -- Request content, ordered from child to parent by the DEV FK report.
    DELETE FROM ops.adre_inv_item_bom_comp;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_BOM_COMP=' || l_rows);

    DELETE FROM ops.adre_inv_item_approval;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_APPROVAL=' || l_rows);

    DELETE FROM ops.adre_inv_item_api_log;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_API_LOG=' || l_rows);

    DELETE FROM ops.adre_inv_item_attr_value;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_ATTR_VALUE=' || l_rows);

    DELETE FROM ops.adre_inv_item_category;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_CATEGORY=' || l_rows);

    DELETE FROM ops.adre_inv_item_document;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_DOCUMENT=' || l_rows);

    DELETE FROM ops.adre_inv_item_bom;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_BOM=' || l_rows);

    DELETE FROM ops.adre_inv_item_request_org;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_REQUEST_ORG=' || l_rows);

    DELETE FROM ops.adre_inv_item_request;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_REQUEST=' || l_rows);

    -- Configuration relations before their parent catalogs.
    DELETE FROM ops.adre_inv_item_type_attr;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_TYPE_ATTR=' || l_rows);

    DELETE FROM ops.adre_inv_item_planner_rule;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_PLANNER_RULE=' || l_rows);

    DELETE FROM ops.adre_inv_item_template_rule;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_TEMPLATE_RULE=' || l_rows);

    DELETE FROM ops.adre_inv_item_type_org;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_TYPE_ORG=' || l_rows);

    DELETE FROM ops.adre_inv_item_type_uom;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_TYPE_UOM=' || l_rows);

    DELETE FROM ops.adre_inv_item_attribute;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_ATTRIBUTE=' || l_rows);

    DELETE FROM ops.adre_inv_item_section;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_SECTION=' || l_rows);

    DELETE FROM ops.adre_inv_item_type;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_TYPE=' || l_rows);

    DELETE FROM ops.adre_inv_item_org_cat_set;
    l_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('ADRE_INV_ITEM_ORG_CAT_SET=' || l_rows);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DEV OPS data reset committed. EBS items were not deleted.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        raise_application_error
        (
            -20905,
            'Unexpected Error in ADRE DEV configuration reset: ' || SQLERRM,
            TRUE
        );
END;
/
