-- =====================================================================
-- Adhesives Research
-- Script    : ADRE_PROD_CONFIG_SEED_20261007.sql
-- Author    : Joel Calzadilla
-- Date      : 10/07/2026
-- Purpose   : Insert the verified DEV configuration into nine OPS
--             catalogs. Resolve EBS and OPS technical IDs by name/code.
-- Execution : APEX SQL Scripts; run only after all nine OPS catalogs
--             are empty and the corresponding DDL is installed.
-- Source    : DEV exports report(362-364,366-372).csv.
-- =====================================================================

DECLARE
    l_count                 NUMBER;
    l_view_application_id   NUMBER;
    l_security_group_id     NUMBER;
    l_actor                 VARCHAR2(100) := SUBSTR(NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), 1, 100);
    l_type_001              NUMBER;
    l_type_002              NUMBER;
    l_type_003              NUMBER;
    l_type_004              NUMBER;
    l_type_005              NUMBER;
    l_type_006              NUMBER;
    l_type_007              NUMBER;
    l_section_001           NUMBER;
    l_section_002           NUMBER;
    l_section_003           NUMBER;
    l_section_004           NUMBER;
    l_section_005           NUMBER;
    l_section_006           NUMBER;
    l_section_007           NUMBER;
    l_section_008           NUMBER;
    l_section_009           NUMBER;
    l_section_010           NUMBER;
    l_section_011           NUMBER;
    l_section_012           NUMBER;
    l_section_013           NUMBER;
    l_attribute_001         NUMBER;
    l_attribute_002         NUMBER;
    l_attribute_003         NUMBER;
    l_attribute_004         NUMBER;
    l_attribute_005         NUMBER;
    l_attribute_006         NUMBER;
    l_attribute_007         NUMBER;
    l_attribute_008         NUMBER;
    l_attribute_009         NUMBER;
    l_attribute_010         NUMBER;
    l_attribute_011         NUMBER;
    l_attribute_012         NUMBER;
    l_attribute_013         NUMBER;
    l_attribute_014         NUMBER;
    l_attribute_015         NUMBER;
    l_attribute_016         NUMBER;
    l_attribute_017         NUMBER;
    l_attribute_018         NUMBER;
    l_attribute_019         NUMBER;
    l_attribute_020         NUMBER;
    l_attribute_021         NUMBER;
    l_attribute_022         NUMBER;
    l_attribute_023         NUMBER;
    l_attribute_024         NUMBER;
    l_attribute_025         NUMBER;
    l_attribute_026         NUMBER;
    l_attribute_027         NUMBER;
    l_attribute_028         NUMBER;
    l_attribute_029         NUMBER;
    l_attribute_030         NUMBER;
    l_attribute_031         NUMBER;
    l_attribute_032         NUMBER;
    l_attribute_033         NUMBER;
    l_attribute_034         NUMBER;
    l_attribute_035         NUMBER;
    l_attribute_036         NUMBER;
    l_attribute_037         NUMBER;
    l_attribute_038         NUMBER;
    l_attribute_039         NUMBER;
    l_attribute_040         NUMBER;
    l_category_set_001      NUMBER;
    l_category_set_002      NUMBER;
    l_category_set_003      NUMBER;
    l_organization_004      NUMBER;
    l_organization_005      NUMBER;
    l_organization_006      NUMBER;
    l_template_007          NUMBER;
    l_template_008          NUMBER;
    l_template_009          NUMBER;
    l_template_010          NUMBER;
    l_template_011          NUMBER;
    l_template_012          NUMBER;
    l_template_013          NUMBER;
    l_template_014          NUMBER;
    l_template_015          NUMBER;
    l_template_016          NUMBER;
    l_template_017          NUMBER;
    l_template_018          NUMBER;
    l_template_019          NUMBER;
    l_template_020          NUMBER;
    l_template_021          NUMBER;
    l_template_022          NUMBER;
    l_template_023          NUMBER;
    l_template_024          NUMBER;
    l_template_025          NUMBER;
    l_template_026          NUMBER;
    l_template_027          NUMBER;

    -- ---------------------------------------------------------------
    -- Routine    : fnc_ebs_id
    -- Purpose    : Resolve one unique EBS identifier by object name.
    -- Parameters : p_object_type IN VARCHAR2 - EBS object family.
    --              p_object_name IN VARCHAR2 - expected EBS name/code.
    -- Returns    : NUMBER - unique EBS technical identifier.
    -- ---------------------------------------------------------------
    FUNCTION fnc_ebs_id
    (
        p_object_type IN VARCHAR2,
        p_object_name IN VARCHAR2
    )
    RETURN NUMBER
    IS
        l_match_count NUMBER;
        l_identifier  NUMBER;
    BEGIN
        IF p_object_type = 'ORGANIZATION' THEN
            SELECT COUNT(*), MIN(organization_id)
              INTO l_match_count, l_identifier
              FROM apps.mtl_parameters
             WHERE  organization_code = p_object_name;
        ELSIF p_object_type = 'TEMPLATE' THEN
            SELECT COUNT(*), MIN(template_id)
              INTO l_match_count, l_identifier
              FROM apps.mtl_item_templates
             WHERE  template_name = p_object_name;
        ELSIF p_object_type = 'CATEGORY_SET' THEN
            SELECT COUNT(*), MIN(category_set_id)
              INTO l_match_count, l_identifier
              FROM apps.mtl_category_sets_vl
             WHERE  category_set_name = p_object_name
               AND  control_level     = 1;
        ELSE
            raise_application_error(-20910, 'Unsupported EBS object type: ' || p_object_type);
        END IF;
        IF l_match_count <> 1 THEN
            raise_application_error
            (
                -20915,
                'Expected exactly one EBS ' || p_object_type || ' named ' ||
                p_object_name || '; COUNT=' || l_match_count
            );
        END IF;
        RETURN l_identifier;
    EXCEPTION
        WHEN OTHERS THEN
            raise_application_error
            (
                -20920,
                'Unexpected Error in fnc_ebs_id: ' || SQLERRM,
                TRUE
            );
    END fnc_ebs_id;

BEGIN
    -- A seed from a complete snapshot must never mix with old rows.
    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_type;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_TYPE must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_section;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_SECTION must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_attribute;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_ATTRIBUTE must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_type_attr;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_TYPE_ATTR must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_type_uom;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_TYPE_UOM must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_type_org;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_TYPE_ORG must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_template_rule;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_TEMPLATE_RULE must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_planner_rule;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_PLANNER_RULE must be empty; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*) INTO l_count
      FROM ops.adre_inv_item_org_cat_set;
    IF l_count <> 0 THEN
        raise_application_error(-20925, 'OPS.ADRE_INV_ITEM_ORG_CAT_SET must be empty; COUNT=' || l_count);
    END IF;

    -- Resolve all external references before inserting any OPS row.
    l_category_set_001 := fnc_ebs_id('CATEGORY_SET', 'BUSINESS UNIT');
    l_category_set_002 := fnc_ebs_id('CATEGORY_SET', 'DIVISION');
    l_category_set_003 := fnc_ebs_id('CATEGORY_SET', 'PLATFORM');
    l_organization_004 := fnc_ebs_id('ORGANIZATION', 'GRI');
    l_organization_005 := fnc_ebs_id('ORGANIZATION', 'IRI');
    l_organization_006 := fnc_ebs_id('ORGANIZATION', 'MAS');
    l_template_007 := fnc_ebs_id('TEMPLATE', 'ADHESIVES');
    l_template_008 := fnc_ebs_id('TEMPLATE', 'CONVERTING GR');
    l_template_009 := fnc_ebs_id('TEMPLATE', 'ELECTRONICS ARCARE COATING');
    l_template_010 := fnc_ebs_id('TEMPLATE', 'ELECTRONICS ARCARE GR');
    l_template_011 := fnc_ebs_id('TEMPLATE', 'ELECTRONICS ARCLAD COATING');
    l_template_012 := fnc_ebs_id('TEMPLATE', 'ELECTRONICS ARCLAD GR');
    l_template_013 := fnc_ebs_id('TEMPLATE', 'ENGINEERED TAPES COATING');
    l_template_014 := fnc_ebs_id('TEMPLATE', 'ENGINEERED TAPES GR');
    l_template_015 := fnc_ebs_id('TEMPLATE', 'ENGINEERING ADH IRE');
    l_template_016 := fnc_ebs_id('TEMPLATE', 'EXPENSE GR');
    l_template_017 := fnc_ebs_id('TEMPLATE', 'GLOBAL ITEM');
    l_template_018 := fnc_ebs_id('TEMPLATE', 'INDUSTRIAL ARCLAD GR');
    l_template_019 := fnc_ebs_id('TEMPLATE', 'INDUSTRIAL COATING');
    l_template_020 := fnc_ebs_id('TEMPLATE', 'MEDICAL ARCARE GR');
    l_template_021 := fnc_ebs_id('TEMPLATE', 'MEDICAL ARCARE IRE');
    l_template_022 := fnc_ebs_id('TEMPLATE', 'MEDICAL ARCLAD GR');
    l_template_023 := fnc_ebs_id('TEMPLATE', 'MEDICAL COATING');
    l_template_024 := fnc_ebs_id('TEMPLATE', 'PURCHASING GR');
    l_template_025 := fnc_ebs_id('TEMPLATE', 'REL LINERS');
    l_template_026 := fnc_ebs_id('TEMPLATE', 'SPLICING ARCLAD GR');
    l_template_027 := fnc_ebs_id('TEMPLATE', 'SPLICING COATING');

    SELECT COUNT(*),
           MIN(lotyvl.view_application_id),
           MIN(lotyvl.security_group_id)
      INTO l_count,
           l_view_application_id,
           l_security_group_id
      FROM apps.fnd_lookup_types_vl lotyvl,
           apps.fnd_application fndapp
     WHERE  lotyvl.lookup_type            = 'ITEM_TYPE'
       AND  fndapp.application_id         = lotyvl.application_id
       AND  fndapp.application_short_name = 'INV';
    IF l_count <> 1 THEN
        raise_application_error(-20930, 'Expected one INV ITEM_TYPE lookup; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*)
      INTO l_count
      FROM apps.fnd_lookup_values_vl lovavl
     WHERE  lovavl.lookup_type         = 'ITEM_TYPE'
       AND  lovavl.lookup_code         = 'A'
       AND  lovavl.view_application_id = l_view_application_id
       AND  lovavl.security_group_id   = l_security_group_id
       AND  lovavl.enabled_flag        = 'Y';
    IF l_count <> 1 THEN
        raise_application_error(-20930, 'EBS Item Type lookup missing or ambiguous: A; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*)
      INTO l_count
      FROM apps.fnd_lookup_values_vl lovavl
     WHERE  lovavl.lookup_type         = 'ITEM_TYPE'
       AND  lovavl.lookup_code         = 'ADHESIVE_COATING'
       AND  lovavl.view_application_id = l_view_application_id
       AND  lovavl.security_group_id   = l_security_group_id
       AND  lovavl.enabled_flag        = 'Y';
    IF l_count <> 1 THEN
        raise_application_error(-20930, 'EBS Item Type lookup missing or ambiguous: ADHESIVE_COATING; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*)
      INTO l_count
      FROM apps.fnd_lookup_values_vl lovavl
     WHERE  lovavl.lookup_type         = 'ITEM_TYPE'
       AND  lovavl.lookup_code         = 'SLIT_CUSTOMER_SERVICE'
       AND  lovavl.view_application_id = l_view_application_id
       AND  lovavl.security_group_id   = l_security_group_id
       AND  lovavl.enabled_flag        = 'Y';
    IF l_count <> 1 THEN
        raise_application_error(-20930, 'EBS Item Type lookup missing or ambiguous: SLIT_CUSTOMER_SERVICE; COUNT=' || l_count);
    END IF;

    SELECT COUNT(*)
      INTO l_count
      FROM apps.fnd_lookup_values_vl lovavl
     WHERE  lovavl.lookup_type         = 'ITEM_TYPE'
       AND  lovavl.lookup_code         = 'SLIT_ENGINEERING'
       AND  lovavl.view_application_id = l_view_application_id
       AND  lovavl.security_group_id   = l_security_group_id
       AND  lovavl.enabled_flag        = 'Y';
    IF l_count <> 1 THEN
        raise_application_error(-20930, 'EBS Item Type lookup missing or ambiguous: SLIT_ENGINEERING; COUNT=' || l_count);
    END IF;

    -- TYPE : 7 configuration rows.
    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'RAW_MATERIAL_ITEM',
        'Raw Material',
        'Raw Material item type from the Caron functional matrix.',
        'Y',
        50,
        NULL,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_001;

    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'ADHESIVES',
        'Adhesives',
        'Adhesives item type from the Caron functional matrix.',
        'Y',
        10,
        'A',
        l_view_application_id,
        l_security_group_id,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_002;

    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'ADHESIVE_COATING',
        'Adhesive Coating',
        'Adhesive Coating item type from the Caron functional matrix.',
        'Y',
        20,
        'ADHESIVE_COATING',
        l_view_application_id,
        l_security_group_id,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_003;

    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'CONVERTING',
        'Converting',
        'Converting item type from the Caron functional matrix.',
        'Y',
        30,
        NULL,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_004;

    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'SLIT_CUSTOMER_SERVICE',
        'Slitting for CS',
        'Slitting for Customer Service item type from the Caron functional matrix.',
        'Y',
        60,
        'SLIT_CUSTOMER_SERVICE',
        l_view_application_id,
        l_security_group_id,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_005;

    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'LINER_COATING',
        'Liner Coating',
        'Liner Coating item type from the Caron functional matrix.',
        'Y',
        40,
        NULL,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_006;

    INSERT INTO ops.adre_inv_item_type
    (
        item_type_code,
        item_type_name,
        description,
        active_flag,
        display_sequence,
        ebs_item_type_code,
        ebs_view_application_id,
        ebs_security_group_id,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'SLIT_ENGINEERING',
        'Slitting for Eng',
        'Slitting for Engineering item type from the Caron functional matrix.',
        'Y',
        70,
        'SLIT_ENGINEERING',
        l_view_application_id,
        l_security_group_id,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_type_id INTO l_type_007;

    DBMS_OUTPUT.PUT_LINE('TYPE inserted: 7');

    -- SECTION : 13 configuration rows.
    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'PHYSICAL',
        'Physical',
        'ATTRIBUTE',
        'TARGET',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_006;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'QUALITY',
        'Quality / Regulatory',
        'ATTRIBUTE',
        'TARGET',
        'Y',
        50,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_007;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'COMMERCIAL',
        'Commercial / Customer',
        'ATTRIBUTE',
        'TARGET',
        'Y',
        60,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_008;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'COSTING',
        'Costing',
        'ATTRIBUTE',
        'BOTH',
        'Y',
        40,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_001;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'PURCHASING',
        'Purchasing',
        'ATTRIBUTE',
        'TARGET',
        'Y',
        40,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_003;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'FLEXFIELD',
        'Flexfield',
        'ATTRIBUTE',
        'BOTH',
        'Y',
        50,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_004;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'PHYSICAL_ATTRIBUTES',
        'Physical Attributes',
        'ATTRIBUTE',
        'BOTH',
        'Y',
        80,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_005;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'DOCUMENT',
        'Document',
        'DOCUMENT',
        'BOTH',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_009;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'INVENTORY',
        'Inventory',
        'ATTRIBUTE',
        'TARGET',
        'Y',
        30,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_010;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'CATEGORIES',
        'Categories',
        'CATEGORY',
        'BOTH',
        'Y',
        60,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_011;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'BOM',
        'BOM',
        'BOM',
        'BOTH',
        'Y',
        70,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_012;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'ENGINEERING',
        'Engineering',
        'ATTRIBUTE',
        'BOTH',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_013;

    INSERT INTO ops.adre_inv_item_section
    (
        section_code,
        section_name,
        section_type,
        organization_scope,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        'LEAD_TIMES',
        'Lead Times',
        'ATTRIBUTE',
        'BOTH',
        'Y',
        100,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_section_id INTO l_section_002;

    DBMS_OUTPUT.PUT_LINE('SECTION inserted: 13');

    -- ATTRIBUTE : 40 configuration rows.
    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_008,
        'CUSTOMER',
        'Customer',
        'CHAR',
        'Customer name/reference.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        'ATTRIBUTE4',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_012;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'SHELF_LIFE_CONTROL',
        'Shelf Life Control',
        'CHAR',
        'EBS shelf life / expiration control terminology. This replaces treating Shelf Life From as a separate EBS destination.',
        NULL,
        NULL,
        'N',
        'Y',
        70,
        'SHELF_LIFE_CODE',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_013;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'BATCH_SIZE',
        'Batch Size',
        'CHAR',
        'Batch Size business value.',
        NULL,
        NULL,
        'N',
        'Y',
        90,
        'ATTRIBUTE9',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_004;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'SHELF_LIFE_DAYS',
        'Shelf Life Days',
        'NUMBER',
        'Shelf Life Days.',
        NULL,
        'DAY',
        'N',
        'Y',
        60,
        'SHELF_LIFE_DAYS',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_005;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'SHIPPABLE_ITEM_FLAG',
        'Shippable',
        'YES_NO',
        'Oracle EBS Shippable Item flag where explicitly configured.',
        NULL,
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_006;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'VEEVA_CONTENT_ID',
        'Veeva Content ID #',
        'CHAR',
        'Veeva Content identifier.',
        NULL,
        NULL,
        'N',
        'Y',
        70,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_015;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'SELLABLE',
        'Sellable',
        'YES_NO',
        'Sellable business field. It is intentionally NOT mapped automatically to Shippable.',
        NULL,
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_016;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'PURCHASABLE',
        'Purchasable',
        'YES_NO',
        'Purchasable business field from the functional matrix.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_017;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_003,
        'CUSTOMER_PURCHASED_RAW',
        'Customer Purchased Raw',
        'YES_NO',
        'Customer Purchased Raw flag.',
        NULL,
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_018;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_003,
        'VENDOR',
        'Vendor',
        'CHAR',
        'Vendor name/reference.',
        NULL,
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_019;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_003,
        'CONTACT_NAME',
        'Contact Name',
        'CHAR',
        'Vendor contact name.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_020;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_003,
        'ADDRESS',
        'Address',
        'CHAR',
        'Vendor/contact address.',
        NULL,
        NULL,
        'N',
        'Y',
        40,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_021;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_003,
        'PHONE',
        'Phone',
        'CHAR',
        'Vendor/contact phone.',
        NULL,
        NULL,
        'N',
        'Y',
        50,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_022;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_007,
        'MEDICAL_GRADE',
        'Medical Grade',
        'YES_NO',
        'Medical Grade business field.',
        NULL,
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_023;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_007,
        'OTHER_GRADE',
        'Other Grade',
        'CHAR',
        'Other Grade business value.',
        NULL,
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_024;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_007,
        'UN_NUMBER',
        'UN Number',
        'CHAR',
        'UN Number. Current functional direction uses this instead of Food Grade.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_025;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_007,
        'HAZARD_CLASS',
        'Hazard Class',
        'CHAR',
        'Hazard Class.',
        NULL,
        NULL,
        'N',
        'Y',
        40,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_026;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_007,
        'STORAGE_CONDITIONS',
        'Storage Conditions',
        'CHAR',
        'Storage Conditions.',
        NULL,
        NULL,
        'N',
        'Y',
        50,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_027;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_008,
        'NOTIFY_CS',
        'Notify CS',
        'YES_NO',
        'Notify Customer Service flag.',
        NULL,
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_028;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_008,
        'NOTIFY_PLANNING',
        'Notify Planning',
        'YES_NO',
        'Notify Planning flag.',
        NULL,
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_029;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'HIMS',
        'HIMS',
        'CHAR',
        'HIMS value. Current package applies this from the MASTER organization.',
        '000',
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_038;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'ENGINEERING_ITEM_FLAG',
        'Engineering Item',
        'YES_NO',
        'Oracle EBS Engineering Item flag.',
        'Y',
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_039;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_003,
        'PRICE_PER_UOM',
        'Price Per UOM',
        'NUMBER',
        'Price per primary UOM.',
        NULL,
        NULL,
        'N',
        'Y',
        60,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_040;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'PDR_NUMBER',
        'PDR',
        'CHAR',
        'PDR reference number.',
        NULL,
        NULL,
        'N',
        'Y',
        40,
        'ATTRIBUTE1',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_001;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'PLANNER',
        'Planner',
        'CHAR',
        'Planner code. Current package can derive the configured Planner for supported Item Types.',
        NULL,
        NULL,
        'N',
        'Y',
        100,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_014;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'PLANNING_METHOD',
        'Planning Method',
        'CHAR',
        'Planning method resolved against TARGET template metadata where applicable.',
        'MRP Planning',
        NULL,
        'N',
        'Y',
        110,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_030;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'COST_ROLL_UP_REQUESTED',
        'Cost Roll Up',
        'YES_NO',
        'Cost Roll Up request flag.',
        'N',
        NULL,
        'N',
        'Y',
        50,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_031;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_004,
        'COAT_WEIGHT',
        'Coat Weight',
        'NUMBER',
        'Coat weight used for applicable Item Types.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_033;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'TSR_NUMBER',
        'TSR',
        'CHAR',
        'TSR reference number or supplied TSR reference value.',
        NULL,
        NULL,
        'N',
        'Y',
        50,
        'ATTRIBUTE2',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_034;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_006,
        'WIDTH',
        'Width',
        'NUMBER',
        'Item width. VALUE_UOM_CODE stores the selected EBS UOM.',
        NULL,
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_035;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'OUTSIDE_PROCESSING',
        'Outside Processing',
        'YES_NO',
        'Outside Processing flag.',
        'N',
        NULL,
        'N',
        'Y',
        40,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_036;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'ENGINEERING_STATUS',
        'Engineering',
        'CHAR',
        'Engineering / OPS / PDR / TSR business value from the functional matrix.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_037;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_004,
        'RLHD_RLDH',
        'RLHD / RLDH',
        'CHAR',
        'RLHD or RLDH value used for applicable Item Types.',
        NULL,
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_002;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_006,
        'TARGET_LENGTH',
        'Target Length',
        'NUMBER',
        'Item target length. VALUE_UOM_CODE stores the selected EBS UOM.',
        NULL,
        NULL,
        'N',
        'Y',
        20,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_003;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_004,
        'COATER',
        'Coater',
        'CHAR',
        'Coater used for applicable Item Types.',
        NULL,
        NULL,
        'N',
        'Y',
        10,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_007;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'LEAD_TIME_DAYS',
        'Lead Time Days',
        'NUMBER',
        'Lead Time Days.',
        NULL,
        'DAY',
        'N',
        'Y',
        80,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_008;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_010,
        'EXPENSE_ITEM_FLAG',
        'Expense Item',
        'YES_NO',
        'Expense Item flag used by TARGET template rule resolution.',
        'N',
        NULL,
        'N',
        'Y',
        120,
        NULL,
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_032;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_013,
        'CONSTRUCTION',
        'Construction',
        'CHAR',
        'Construction text supplied for the item.',
        NULL,
        NULL,
        'N',
        'Y',
        60,
        'ATTRIBUTE3',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_011;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_006,
        'PERCENT_SOLIDS',
        'Percent Solids',
        'NUMBER',
        'Percent Solids value.',
        NULL,
        NULL,
        'N',
        'Y',
        40,
        'ATTRIBUTE16',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_009;

    INSERT INTO ops.adre_inv_item_attribute
    (
        item_section_id,
        attribute_code,
        attribute_name,
        attribute_data_type,
        description,
        default_value,
        unit_of_measure,
        required_flag,
        active_flag,
        display_sequence,
        ebs_attribute_name,
        ebs_attribute_group,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_section_006,
        'WEIGHT_PER_GALLON',
        'Weight Per Gallon',
        'NUMBER',
        'Weight per gallon business value. Do not map this to UNIT_WEIGHT. For confirmed Adhesives behavior it can be represented in Construction text.',
        NULL,
        NULL,
        'N',
        'Y',
        30,
        'UNIT_WEIGHT',
        'MTL_SYSTEM_ITEMS',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    ) RETURNING item_attribute_id INTO l_attribute_010;

    DBMS_OUTPUT.PUT_LINE('ATTRIBUTE inserted: 40');

    -- TYPE_ATTR : 99 configuration rows.
    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        110,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_012,
        'TARGET',
        'N',
        NULL,
        'Y',
        120,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_031,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_005,
        'TARGET',
        'Y',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_008,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'Y',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_012,
        'TARGET',
        'N',
        NULL,
        'Y',
        110,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_013,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        130,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_013,
        'TARGET',
        'N',
        NULL,
        'Y',
        100,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        90,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_039,
        'MASTER',
        'N',
        NULL,
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_039,
        'MASTER',
        'N',
        NULL,
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_035,
        'TARGET',
        'N',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_003,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_035,
        'TARGET',
        'N',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_039,
        'MASTER',
        'N',
        'Y',
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_003,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_039,
        'MASTER',
        'N',
        NULL,
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_004,
        'TARGET',
        'N',
        NULL,
        'Y',
        90,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_005,
        'TARGET',
        'N',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_006,
        'TARGET',
        'N',
        NULL,
        'Y',
        110,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        100,
        'Y',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_038,
        'MASTER',
        'N',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_008,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_037,
        'TARGET',
        'N',
        NULL,
        'Y',
        140,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_016,
        'TARGET',
        'N',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_017,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_028,
        'TARGET',
        'N',
        NULL,
        'Y',
        120,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_029,
        'TARGET',
        'N',
        NULL,
        'Y',
        130,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_005,
        'TARGET',
        'Y',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_037,
        'TARGET',
        'N',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_013,
        'TARGET',
        'N',
        NULL,
        'Y',
        110,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_018,
        'TARGET',
        'N',
        NULL,
        'Y',
        130,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_019,
        'TARGET',
        'N',
        NULL,
        'Y',
        140,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_020,
        'TARGET',
        'N',
        NULL,
        'Y',
        150,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_021,
        'TARGET',
        'N',
        NULL,
        'Y',
        160,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_022,
        'TARGET',
        'N',
        NULL,
        'Y',
        170,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_023,
        'TARGET',
        'N',
        NULL,
        'Y',
        190,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_025,
        'TARGET',
        'N',
        NULL,
        'Y',
        200,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_026,
        'TARGET',
        'N',
        NULL,
        'Y',
        210,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_027,
        'TARGET',
        'N',
        NULL,
        'Y',
        220,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_028,
        'TARGET',
        'N',
        NULL,
        'Y',
        230,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_013,
        'TARGET',
        'N',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_037,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_013,
        'TARGET',
        'N',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_037,
        'TARGET',
        'N',
        NULL,
        'Y',
        90,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_032,
        'TARGET',
        'N',
        NULL,
        'Y',
        240,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_038,
        'MASTER',
        'N',
        '000',
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_039,
        'MASTER',
        'N',
        'Y',
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_040,
        'TARGET',
        'N',
        NULL,
        'Y',
        180,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_008,
        'TARGET',
        'N',
        NULL,
        'Y',
        120,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_005,
        'TARGET',
        'N',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_008,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_030,
        'MASTER',
        'N',
        NULL,
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_007,
        'TARGET',
        'N',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_002,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_033,
        'TARGET',
        'N',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_035,
        'TARGET',
        'N',
        NULL,
        'Y',
        20,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_003,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_008,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_037,
        'TARGET',
        'Y',
        NULL,
        'Y',
        100,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_031,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_036,
        'TARGET',
        'Y',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_039,
        'MASTER',
        'N',
        NULL,
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_037,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_011,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        40,
        'Y',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_005,
        'TARGET',
        'N',
        NULL,
        'Y',
        100,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_039,
        'MASTER',
        'N',
        'Y',
        'Y',
        10,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'Y',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        120,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_009,
        'TARGET',
        'N',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_010,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_005,
        'TARGET',
        'Y',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        110,
        'Y',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_008,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_005,
        'TARGET',
        'N',
        NULL,
        'Y',
        40,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_014,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'Y',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_031,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_037,
        'TARGET',
        'N',
        NULL,
        'Y',
        110,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        90,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_036,
        'TARGET',
        'N',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        50,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_009,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_010,
        'TARGET',
        'N',
        NULL,
        'Y',
        80,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_attribute_011,
        'TARGET',
        'N',
        NULL,
        'Y',
        90,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        90,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        100,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_attribute_001,
        'TARGET',
        'N',
        NULL,
        'Y',
        100,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        60,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_attribute_034,
        'TARGET',
        'N',
        NULL,
        'Y',
        100,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_011,
        'TARGET',
        'N',
        NULL,
        'Y',
        150,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_attribute_036,
        'TARGET',
        'N',
        NULL,
        'Y',
        70,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_attr
    (
        item_type_id,
        item_attribute_id,
        organization_scope,
        required_flag,
        default_value,
        active_flag,
        display_sequence,
        auto_derive_flag,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_attribute_036,
        'TARGET',
        'N',
        NULL,
        'Y',
        30,
        'N',
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    DBMS_OUTPUT.PUT_LINE('TYPE_ATTR inserted: 99');

    -- TYPE_UOM : 9 configuration rows.
    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        'LB',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        'KG',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        'M',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        'TFT',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        'RL',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        'TFT',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        'RL',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        'RL',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_uom
    (
        item_type_id,
        uom_code,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        'FT',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    DBMS_OUTPUT.PUT_LINE('TYPE_UOM inserted: 9');

    -- TYPE_ORG : 14 configuration rows.
    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        'TARGET',
        l_organization_004,
        NULL,
        'Y',
        'Y',
        'Y',
        20,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_type_org
    (
        item_type_id,
        organization_role,
        ebs_organization_id,
        ebs_template_id,
        required_flag,
        auto_assign_flag,
        active_flag,
        display_sequence,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        'MASTER',
        l_organization_006,
        l_template_017,
        'Y',
        'Y',
        'Y',
        10,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    DBMS_OUTPUT.PUT_LINE('TYPE_ORG inserted: 14');

    -- TEMPLATE_RULE : 30 configuration rows.
    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_organization_005,
        'ARcare',
        'Medical',
        NULL,
        l_template_015,
        'READY',
        'IRI source-led creation. Missing inputs preserve template/EBS defaults; no Item Number criterion.',
        10,
        'Y',
        TO_DATE('09/15/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_005,
        'ARcare',
        'Medical',
        NULL,
        l_template_021,
        'READY',
        'IRI source-led creation. Missing inputs preserve template/EBS defaults; no Item Number criterion.',
        10,
        'Y',
        TO_DATE('09/15/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARcare',
        'Electronics',
        NULL,
        l_template_010,
        'READY',
        'Slit Item from Customer Service - ARcare / Electronics.',
        10,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARcare',
        'Engineered Tape',
        NULL,
        l_template_014,
        'READY',
        'Slit Item from Customer Service - ARcare / Engineered Tape.',
        20,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARcare',
        'Medical',
        NULL,
        l_template_020,
        'READY',
        'Slit Item from Customer Service - ARcare / Medical.',
        30,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARcare',
        'Release Liners',
        NULL,
        l_template_025,
        'READY',
        'Slit Item from Customer Service - ARcare / Release Liners.',
        40,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARclad',
        'Electronics',
        NULL,
        l_template_012,
        'READY',
        'Slit Item from Customer Service - ARclad / Electronics.',
        50,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARclad',
        'Industrial',
        NULL,
        l_template_018,
        'READY',
        'Slit Item from Customer Service - ARclad / Industrial.',
        60,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARclad',
        'Medical',
        NULL,
        l_template_022,
        'READY',
        'Slit Item from Customer Service - ARclad / Medical.',
        70,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_005,
        l_organization_004,
        'ARclad',
        'Splicing',
        NULL,
        l_template_026,
        'READY',
        'Validated Slit Customer Service rule: ARclad / Splicing.',
        80,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARcare',
        'Electronics',
        NULL,
        l_template_010,
        'READY',
        'Validated Slit Engineering rule: ARcare / Electronics.',
        10,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARcare',
        'Engineered Tape',
        NULL,
        l_template_014,
        'READY',
        'Slit Item from Engineering - ARcare / Engineered Tape.',
        20,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARcare',
        'Medical',
        NULL,
        l_template_020,
        'READY',
        'Slit Item from Engineering - ARcare / Medical.',
        30,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARcare',
        'Release Liners',
        NULL,
        l_template_025,
        'READY',
        'Slit Item from Engineering - ARcare / Release Liners.',
        40,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARclad',
        'Electronics',
        NULL,
        l_template_012,
        'READY',
        'Slit Item from Engineering - ARclad / Electronics.',
        50,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARclad',
        'Industrial',
        NULL,
        l_template_018,
        'READY',
        'Slit Item from Engineering - ARclad / Industrial.',
        60,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARclad',
        'Medical',
        NULL,
        l_template_022,
        'READY',
        'Slit Item from Engineering - ARclad / Medical.',
        70,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_007,
        l_organization_004,
        'ARclad',
        'Splicing',
        NULL,
        l_template_026,
        'READY',
        'Slit Item from Engineering - ARclad / Splicing.',
        80,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_002,
        l_organization_004,
        NULL,
        NULL,
        NULL,
        l_template_007,
        'READY',
        'Generic ADHESIVES TARGET rule.',
        100,
        'Y',
        TO_DATE('09/01/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARcare',
        'Engineered Tape',
        NULL,
        l_template_013,
        'READY',
        'Previously validated Engineered Tape coating rule.',
        30,
        'Y',
        TO_DATE('08/27/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARcare',
        'Release Liners',
        NULL,
        l_template_025,
        'READY',
        'Previously validated Release Liners rule.',
        40,
        'Y',
        TO_DATE('08/27/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARclad',
        'Electronics',
        NULL,
        l_template_011,
        'READY',
        'Previously validated ARclad / Electronics coating rule.',
        10,
        'Y',
        TO_DATE('08/28/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARclad',
        'Industrial',
        NULL,
        l_template_019,
        'READY',
        'Previously validated ARclad / Industrial coating rule.',
        20,
        'Y',
        TO_DATE('08/28/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARclad',
        'Splicing',
        NULL,
        l_template_027,
        'READY',
        'Previously validated ARclad / Splicing coating rule.',
        30,
        'Y',
        TO_DATE('08/28/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_organization_004,
        NULL,
        NULL,
        'Y',
        l_template_016,
        'READY',
        'Validated Raw Material rule: Expense Item = Y.',
        10,
        'Y',
        TO_DATE('08/28/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_001,
        l_organization_004,
        NULL,
        NULL,
        'N',
        l_template_024,
        'READY',
        'Validated Raw Material rule: Expense Item = N.',
        20,
        'Y',
        TO_DATE('08/28/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARcare',
        'Medical',
        NULL,
        l_template_023,
        'READY',
        'Previously validated Medical coating rule.',
        10,
        'Y',
        TO_DATE('08/25/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_003,
        l_organization_004,
        'ARcare',
        'Electronics',
        NULL,
        l_template_009,
        'READY',
        'Validated Adhesive Coating rule: ARcare / Electronics.',
        20,
        'Y',
        TO_DATE('08/27/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_006,
        l_organization_004,
        'ARcare',
        'Electronics',
        NULL,
        l_template_009,
        'READY',
        'Validated Liner Coating rule used by current Caron matrix.',
        20,
        'Y',
        TO_DATE('09/07/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    INSERT INTO ops.adre_inv_item_template_rule
    (
        item_type_id,
        ebs_organization_id,
        division_value,
        business_unit_value,
        expense_item_flag,
        ebs_template_id,
        rule_status,
        rule_notes,
        rule_priority,
        active_flag,
        effective_start_date,
        effective_end_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date,
        last_update_login,
        record_version_number
    )
    VALUES
    (
        l_type_004,
        l_organization_004,
        NULL,
        NULL,
        NULL,
        l_template_008,
        'READY',
        'Generic CONVERTING TARGET rule.',
        100,
        'Y',
        TO_DATE('09/02/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE,
        SYS_CONTEXT('USERENV', 'SESSIONID'),
        1
    );

    DBMS_OUTPUT.PUT_LINE('TEMPLATE_RULE inserted: 30');

    -- PLANNER_RULE : 9 configuration rows.
    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_003,
        NULL,
        'SP',
        '14',
        10,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_005,
        NULL,
        'SP',
        '14',
        10,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_007,
        NULL,
        'SP',
        '14',
        10,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_003,
        NULL,
        NULL,
        '1',
        100,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_005,
        NULL,
        NULL,
        '1',
        100,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_007,
        NULL,
        NULL,
        '1',
        100,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_002,
        NULL,
        NULL,
        '1',
        100,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_006,
        NULL,
        NULL,
        '1',
        100,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    INSERT INTO ops.adre_inv_item_planner_rule
    (
        item_type_id,
        organization_id,
        item_prefix,
        planner_code,
        priority,
        active_flag,
        effective_from_date,
        effective_to_date,
        created_by,
        creation_date,
        last_updated_by,
        last_update_date
    )
    VALUES
    (
        l_type_004,
        NULL,
        NULL,
        '1',
        100,
        'Y',
        TO_DATE('09/22/2026', 'MM/DD/YYYY'),
        NULL,
        l_actor,
        SYSDATE,
        l_actor,
        SYSDATE
    );

    DBMS_OUTPUT.PUT_LINE('PLANNER_RULE inserted: 9');

    -- ORG_CAT_SET : 3 configuration rows.
    INSERT INTO ops.adre_inv_item_org_cat_set (ebs_organization_id, ebs_category_set_id, active_flag, required_flag, display_sequence)
    VALUES (l_organization_006, l_category_set_002, 'Y', 'N', 10);

    INSERT INTO ops.adre_inv_item_org_cat_set (ebs_organization_id, ebs_category_set_id, active_flag, required_flag, display_sequence)
    VALUES (l_organization_006, l_category_set_001, 'Y', 'N', 20);

    INSERT INTO ops.adre_inv_item_org_cat_set (ebs_organization_id, ebs_category_set_id, active_flag, required_flag, display_sequence)
    VALUES (l_organization_006, l_category_set_003, 'Y', 'N', 30);

    DBMS_OUTPUT.PUT_LINE('ORG_CAT_SET inserted: 3');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('All nine OPS configuration catalogs seeded successfully.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        raise_application_error
        (
            -20935,
            'Unexpected Error in ADRE production configuration seed: ' || SQLERRM,
            TRUE
        );
END;
/
