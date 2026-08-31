/* ============================================================
   AR Global - Troubleshooting Queries V2
   Purpose:
   - Check compile errors, object status, grants visibility, and EBS template setup.
   ============================================================ */

PROMPT Package status
SELECT owner,
       object_name,
       object_type,
       status
FROM all_objects
WHERE owner = 'APPS'
  AND object_name = 'XINV_ITEM_API_PKG_V2'
ORDER BY object_type;

PROMPT Package compile errors
SELECT line,
       position,
       text
FROM all_errors
WHERE owner = 'APPS'
  AND name = 'XINV_ITEM_API_PKG_V2'
ORDER BY sequence;

PROMPT Custom table visibility from current schema
SELECT owner,
       object_name,
       object_type,
       status
FROM all_objects
WHERE object_name IN ('XINV_ITEM_CREATION_STG_V2', 'XINV_ITEM_TYPES_V2', 'PKG_LOG')
ORDER BY object_name, owner, object_type;

PROMPT Template lookup by name
SELECT template_id,
       template_name,
       description
FROM apps.mtl_item_templates
WHERE UPPER(template_name) IN (UPPER('GLOBAL ITEM'), UPPER('ADHESIVES'))
ORDER BY template_name;

PROMPT Validate GRI organization code
SELECT mp.organization_code,
       mp.organization_id
FROM apps.mtl_parameters mp
WHERE UPPER(mp.organization_code) IN (UPPER('MAS'), UPPER('GRI'))
ORDER BY mp.organization_code;
