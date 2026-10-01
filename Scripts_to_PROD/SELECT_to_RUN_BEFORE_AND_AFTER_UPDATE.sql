SELECT DISTINCT
      mp.organization_code,
       msik.concatenated_segments       AS item_number,
       msik.inventory_item_id,
       msik.inventory_item_status_code  AS item_status,
       mc_lr.concatenated_segments      AS log_roll_category,
       uip.current_value                AS use_inherited_properties,
       CASE
          WHEN uip.current_value IS NULL
             THEN 'Current value Value NULL it will be updated to -> YES'
          WHEN UPPER(uip.current_value) = 'YES'
             THEN 'ALREADY YES'
          ELSE 'UPDATE TO YES'
       END                              AS action_required
FROM   apps.mtl_system_items_kfv msik,
       apps.mtl_parameters mp,
       apps.mtl_item_categories mic_lr,
       apps.mtl_category_sets_vl mcs_lr,
       apps.mtl_categories_kfv mc_lr,
       (
          SELECT mic.inventory_item_id,
                 mic.organization_id,
                 mc.concatenated_segments AS current_value
          FROM   apps.mtl_item_categories mic,
                 apps.mtl_category_sets_vl mcs,
                 apps.mtl_categories_kfv mc
          WHERE  mic.category_set_id = mcs.category_set_id
          AND    mic.category_id = mc.category_id
          AND    UPPER(mcs.category_set_name) =
                    'USE INHERITED PROPERTIES'
       ) uip
WHERE  msik.organization_id = mp.organization_id
AND    mp.organization_code = 'GRI'

AND    UPPER(NVL(msik.inventory_item_status_code, 'X')) <> 'INACTIVE'

AND    mic_lr.inventory_item_id = msik.inventory_item_id
AND    mic_lr.organization_id = msik.organization_id
AND    mic_lr.category_set_id = mcs_lr.category_set_id
AND    mc_lr.category_id = mic_lr.category_id

AND    UPPER(mcs_lr.category_set_name) = 'LOG ROLL / SLIT ROLL'
AND    UPPER(mc_lr.concatenated_segments) = 'LOG ROLL'

AND    uip.inventory_item_id(+) = msik.inventory_item_id
AND    uip.organization_id(+) = msik.organization_id

ORDER BY msik.concatenated_segments;