-- =====================================================================
-- Adhesives Research
-- Script    : ADRE_INV_ITEM_ORG_CAT_SET_SETUP.sql
-- Author    : Joel Calzadilla
-- Date      : 10/07/2026
-- Purpose   : Rebuilds the organization category set configuration table
--             and loads the initial MAS configuration using EBS metadata.
-- =====================================================================

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ops.adre_inv_item_org_cat_set';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -942 THEN
            raise_application_error(-20964,
                'Unexpected Error dropping organization category set configuration: ' || SQLERRM,
                TRUE);
        END IF;
END;
/

CREATE TABLE ops.adre_inv_item_org_cat_set
(
    ebs_organization_id NUMBER       NOT NULL,
    ebs_category_set_id NUMBER       NOT NULL,
    active_flag         VARCHAR2(1)  DEFAULT 'Y' NOT NULL,
    required_flag       VARCHAR2(1)  DEFAULT 'N' NOT NULL,
    display_sequence    NUMBER       NOT NULL,
    CONSTRAINT adre_inv_item_org_cat_set_pk
        PRIMARY KEY (ebs_organization_id, ebs_category_set_id),
    CONSTRAINT adre_inv_item_org_cat_set_act_ck
        CHECK (active_flag IN ('Y', 'N')),
    CONSTRAINT adre_inv_item_org_cat_set_req_ck
        CHECK (required_flag IN ('Y', 'N')),
    CONSTRAINT adre_inv_item_org_cat_set_seq_ck
        CHECK (display_sequence > 0)
);

DECLARE
    TYPE t_names IS TABLE OF VARCHAR2(240);
    l_names                t_names := t_names('DIVISION', 'BUSINESS UNIT', 'PLATFORM');
    l_organization_id      apps.mtl_parameters.organization_id%TYPE;
    l_category_set_id      apps.mtl_category_sets_vl.category_set_id%TYPE;
    l_count                NUMBER;
BEGIN
    SELECT COUNT(*), MIN(mtlpar.organization_id)
      INTO l_count, l_organization_id
      FROM apps.mtl_parameters mtlpar
     WHERE mtlpar.organization_code = 'MAS'
       AND mtlpar.organization_id   = mtlpar.master_organization_id;

    IF l_count <> 1 THEN
        raise_application_error(-20960,
            'Expected exactly one MAS master organization. COUNT=' || l_count);
    END IF;

    FOR i IN 1..l_names.COUNT LOOP
        SELECT COUNT(*), MIN(casetvl.category_set_id)
          INTO l_count, l_category_set_id
          FROM apps.mtl_category_sets_vl casetvl
         WHERE UPPER(TRIM(casetvl.category_set_name)) = l_names(i)
           AND casetvl.control_level                  = 1;

        IF l_count <> 1 THEN
            raise_application_error(-20961,
                'Expected exactly one master-controlled EBS category set: ' ||
                l_names(i) || '; COUNT=' || l_count);
        END IF;

        SELECT COUNT(*)
          INTO l_count
          FROM ops.adre_inv_item_org_cat_set orcaset
         WHERE orcaset.ebs_organization_id = l_organization_id
           AND orcaset.ebs_category_set_id = l_category_set_id;

        IF l_count <> 0 THEN
            raise_application_error(-20962,
                'Category set already configured for MAS: ' || l_names(i));
        END IF;

        INSERT INTO ops.adre_inv_item_org_cat_set
        (
            ebs_organization_id,
            ebs_category_set_id,
            active_flag,
            required_flag,
            display_sequence
        )
        VALUES
        (
            l_organization_id,
            l_category_set_id,
            'Y',
            'N',
            i * 10
        );
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('MAS category set configuration created: ' || l_names.COUNT);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        raise_application_error(-20963,
            'Unexpected Error in MAS category set configuration seed: ' || SQLERRM,
            TRUE);
END;
/
