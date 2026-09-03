Adhesives Research - Split Production Configuration Generators

These five scripts replace the previous single all-in-one configuration generator.

Recommended execution/dependency order:
1. OPS.ADRE_INV_ITEM_TYPE
2. OPS.ADRE_INV_ITEM_SECTION
3. OPS.ADRE_INV_ITEM_ATTRIBUTE
4. OPS.ADRE_INV_ITEM_TYPE_ATTR
5. OPS.ADRE_INV_ITEM_TEMPLATE_RULE

Each generator:
- runs in DEV;
- performs no INSERT/UPDATE/DELETE/COMMIT in DEV;
- prints a production seed script for only one configuration table;
- does not export local surrogate IDs;
- resolves cross-table relationships by business codes;
- uses WHERE NOT EXISTS so generated INSERTs are re-runnable.

For a later change affecting only one configuration table:
- run only that table's generator in DEV;
- save its generated output as that table's production seed file;
- deploy only that production seed file, after confirming its dependencies exist.

Important:
The generated seed logic is INSERT-only. If an existing configuration row must be changed
rather than added, use a separately reviewed UPDATE/MERGE migration for that specific change.
