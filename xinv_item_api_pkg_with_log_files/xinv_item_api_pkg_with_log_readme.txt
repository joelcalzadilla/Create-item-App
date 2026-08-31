AR Global - XINV Item API Package with PKG_LOG

Files included:
1. xinv_item_api_pkg_with_log.pks
   Package specification.

2. xinv_item_api_pkg_with_log.pkb
   Package body with detailed calls to:
   PKG_LOG.SP_INSERT_MESSAGE(
       p_co_aplication,
       p_tx_business_process,
       p_tx_message
   )

3. xinv_item_api_pkg_with_log_all.sql
   Combined package specification and body.

4. xinv_item_api_pkg_with_log_test_call.sql
   Sample calls for single-row validate-only processing and batch validate-only processing.

Important notes:
- All comments, variables, procedure names, and log messages are in English.
- The package calls EGO_ITEM_PUB.PROCESS_ITEM using the convenience wrapper signature.
- The package assumes it is compiled in APPS or in a custom schema with grants/synonyms for EGO_ITEM_PUB, FND_API, FND_MSG_PUB, FND_GLOBAL, MO_GLOBAL, ERROR_HANDLER, PKG_LOG, and the XINV staging tables.
- Validate-only mode rolls back API changes to a local savepoint but preserves the staging result message.
- Create/update mode keeps API changes and staging changes together when the API succeeds.
