 DECLARE
/*==============================================================================
  Client      : ADHESIVES RESEARCH
  Developer   : Joel Calzadilla
  Date        : September 16, 2026 -8:04PM

  Script      : Update USE INHERITED PROPERTIES Category
                Production  Version

  Description :
      This script identifies all items assigned to the GRI organization that
      meet the following criteria:

          - Item Status is not INACTIVE.
          - Category Set "LOG ROLL / SLIT ROLL" is assigned with
            Category "LOG ROLL".

      For every qualifying item, the script ensures that the Category Set

          USE INHERITED PROPERTIES

      is assigned with Category

          YES

      Processing Rules:

          - If USE INHERITED PROPERTIES = YES is already assigned,
            no change is performed.

          - If USE INHERITED PROPERTIES currently has another value,
            the existing category assignment is updated to YES.

          - If no USE INHERITED PROPERTIES assignment currently exists,
            a new assignment with Category YES is created.

      EBS Integration:

          - The script uses Oracle E-Business Suite public API
            INV_ITEM_CATEGORY_PUB.

          - It does NOT directly INSERT, UPDATE or DELETE rows from
            MTL_ITEM_CATEGORIES.

          - Organization ID, Category Set IDs and Category IDs are
            dynamically resolved from EBS configuration.

      Logging:

          - Standard Oracle E-Business Suite FND_LOG is used.
          - Normal processing messages use LEVEL_STATEMENT.
          - Errors use LEVEL_ERROR.

          Log Module:

              ADRE.USE_INHERITED_PROPERTIES

      Transaction Control:
          - An explicit COMMIT is executed after all items are processed.

         
      Scope:

          Organization : GRI

==============================================================================*/


   ---------------------------------------------------------------------------
   -- PROCESS CONSTANTS
   ---------------------------------------------------------------------------
   c_org_code            CONSTANT VARCHAR2(3)   := 'GRI';

   c_source_set_name     CONSTANT VARCHAR2(100) :=
      'LOG ROLL / SLIT ROLL';

   c_source_category     CONSTANT VARCHAR2(100) :=
      'LOG ROLL';

   c_target_set_name     CONSTANT VARCHAR2(100) :=
      'USE INHERITED PROPERTIES';

   c_target_category     CONSTANT VARCHAR2(100) :=
      'YES';

   c_log_module          CONSTANT VARCHAR2(100) :=
      'ADRE.USE_INHERITED_PROPERTIES';


   ---------------------------------------------------------------------------
   -- RESOLVED EBS VALUES
   ---------------------------------------------------------------------------
   l_gri_org_id             NUMBER;

   l_source_set_id          NUMBER;
   l_source_category_id     NUMBER;

   l_target_set_id          NUMBER;
   l_target_category_id     NUMBER;

   l_target_control_level   NUMBER;
   l_target_multi_flag      VARCHAR2(1);


   ---------------------------------------------------------------------------
   -- API RETURN VALUES
   ---------------------------------------------------------------------------
   l_return_status          VARCHAR2(1);
   l_errorcode              NUMBER;
   l_msg_count              NUMBER;
   l_msg_data               VARCHAR2(4000);
   l_api_message            VARCHAR2(4000);


   ---------------------------------------------------------------------------
   -- CURRENT ASSIGNMENT
   ---------------------------------------------------------------------------
   l_current_count          NUMBER;
   l_old_category_id        NUMBER;
   l_old_category_name      VARCHAR2(240);
   l_yes_count              NUMBER;


   ---------------------------------------------------------------------------
   -- COUNTERS
   ---------------------------------------------------------------------------
   l_total                  NUMBER := 0;
   l_created                NUMBER := 0;
   l_updated                NUMBER := 0;
   l_already_yes            NUMBER := 0;
   l_skipped                NUMBER := 0;
   l_errors                 NUMBER := 0;


   ---------------------------------------------------------------------------
   -- WRITE STANDARD EBS LOG
   ---------------------------------------------------------------------------
   PROCEDURE p_log (
      p_message IN VARCHAR2,
      p_level   IN NUMBER DEFAULT apps.fnd_log.level_statement
   )
   IS
   BEGIN

      apps.fnd_log.string(
         p_level,
         c_log_module,
         SUBSTR(p_message, 1, 4000)
      );

   EXCEPTION
      WHEN OTHERS THEN
         NULL;

   END p_log;


   ---------------------------------------------------------------------------
   -- COLLECT EBS API MESSAGES
   ---------------------------------------------------------------------------
   FUNCTION f_api_messages (
      p_msg_count IN NUMBER,
      p_msg_data  IN VARCHAR2
   )
   RETURN VARCHAR2
   IS
      l_message        VARCHAR2(4000);
      l_data           VARCHAR2(2000);
      l_msg_index_out  NUMBER;
   BEGIN

      l_message := p_msg_data;

      IF NVL(p_msg_count, 0) > 1 THEN

         l_message := NULL;

         FOR i IN 1 .. p_msg_count LOOP

            apps.fnd_msg_pub.get(
               p_msg_index       => i,
               p_encoded         => apps.fnd_api.g_false,
               p_data            => l_data,
               p_msg_index_out   => l_msg_index_out
            );

            IF l_data IS NOT NULL THEN

               IF l_message IS NOT NULL THEN
                  l_message := l_message || ' | ';
               END IF;

               l_message :=
                  SUBSTR(
                     NVL(l_message, '') || l_data,
                     1,
                     4000
                  );

            END IF;

         END LOOP;

      END IF;

      RETURN SUBSTR(l_message, 1, 4000);

   EXCEPTION
      WHEN OTHERS THEN

         RETURN SUBSTR(
            NVL(
               p_msg_data,
               'Unable to retrieve API message'
            ) ||
            ' / ' ||
            SQLERRM,
            1,
            4000
         );

   END f_api_messages;


BEGIN

  ---------------------------------------------------------------------------
   -- INITIALIZE EBS LOGGING FOR THIS DATABASE SESSION ONLY
   --
   -- These profile values affect only the current server-side session.
   -- They do not permanently modify the EBS profile configuration.
   ---------------------------------------------------------------------------
   apps.fnd_profile.put(
      'AFLOG_ENABLED',
      'Y'
   );

   apps.fnd_profile.put(
      'AFLOG_MODULE',
      'ADRE.USE_INHERITED_PROPERTIES%'
   );

   apps.fnd_profile.put(
      'AFLOG_LEVEL',
      TO_CHAR(apps.fnd_log.level_statement)
   );

   apps.fnd_profile.put(
      'AFLOG_FILENAME',
      NULL
   );

   apps.fnd_log_repository.init();
---------------------------------------------------------------------------

   
   ---------------------------------------------------------------------------
   -- START
   ---------------------------------------------------------------------------
   p_log(
      'START - VALIDATION RUN - Assign USE INHERITED PROPERTIES = YES ' ||
      'for LOG ROLL items in GRI.',
      apps.fnd_log.level_event
   );


   ---------------------------------------------------------------------------
   -- 1. RESOLVE GRI ORGANIZATION
   ---------------------------------------------------------------------------
   SELECT organization_id
   INTO   l_gri_org_id
   FROM   apps.mtl_parameters
   WHERE  organization_code = c_org_code;


   p_log(
      'Resolved Organization [' ||
      c_org_code ||
      '], organization_id=' ||
      l_gri_org_id
   );


   ---------------------------------------------------------------------------
   -- 2. RESOLVE SOURCE CATEGORY SET
   --
   -- LOG ROLL / SLIT ROLL
   ---------------------------------------------------------------------------
   SELECT category_set_id
   INTO   l_source_set_id
   FROM   apps.mtl_category_sets_vl
   WHERE  UPPER(category_set_name) =
          UPPER(c_source_set_name);


   p_log(
      'Resolved Source Category Set [' ||
      c_source_set_name ||
      '], category_set_id=' ||
      l_source_set_id
   );


   ---------------------------------------------------------------------------
   -- 3. RESOLVE SOURCE CATEGORY
   --
   -- LOG ROLL
   --
   -- RTRIM handles configurations where concatenated_segments may contain
   -- empty trailing KFF segments displayed with trailing hyphens.
   ---------------------------------------------------------------------------
   SELECT mc.category_id
   INTO   l_source_category_id
   FROM   apps.mtl_categories_kfv mc,
          apps.mtl_category_sets_b mcs
   WHERE  mcs.category_set_id =
          l_source_set_id
   AND    mc.structure_id =
          mcs.structure_id
   AND    RTRIM(
             UPPER(mc.concatenated_segments),
             '- '
          ) =
          UPPER(c_source_category)
   AND    (
             mcs.validate_flag = 'N'

             OR

             EXISTS
             (
                SELECT 1
                FROM   apps.mtl_category_set_valid_cats mvc
                WHERE  mvc.category_set_id =
                       mcs.category_set_id
                AND    mvc.category_id =
                       mc.category_id
             )
          );


   p_log(
      'Resolved Source Category [' ||
      c_source_category ||
      '], category_id=' ||
      l_source_category_id
   );


   ---------------------------------------------------------------------------
   -- 4. RESOLVE TARGET CATEGORY SET
   --
   -- USE INHERITED PROPERTIES
   ---------------------------------------------------------------------------
   SELECT category_set_id,
          control_level,
          mult_item_cat_assign_flag
   INTO   l_target_set_id,
          l_target_control_level,
          l_target_multi_flag
   FROM   apps.mtl_category_sets_vl
   WHERE  UPPER(category_set_name) =
          UPPER(c_target_set_name);


   p_log(
      'Resolved Target Category Set [' ||
      c_target_set_name ||
      '], category_set_id=' ||
      l_target_set_id ||
      ', control_level=' ||
      l_target_control_level ||
      ', multi_assignment=' ||
      l_target_multi_flag
   );


   ---------------------------------------------------------------------------
   -- 5. SAFETY CHECK
   --
   -- CONTROL_LEVEL = 2 means Item / Organization level.
   --
   -- Requirement is specifically for GRI.
   ---------------------------------------------------------------------------
   IF l_target_control_level <> 2 THEN

      p_log(
         'ABORT - Category Set [' ||
         c_target_set_name ||
         '] has CONTROL_LEVEL=' ||
         l_target_control_level ||
         '. Expected CONTROL_LEVEL=2 because the requirement is ' ||
         'limited to GRI.',
         apps.fnd_log.level_error
      );


      RAISE_APPLICATION_ERROR(
         -20001,
         'USE INHERITED PROPERTIES is not Item/Organization controlled. ' ||
         'No changes performed.'
      );

   END IF;


   ---------------------------------------------------------------------------
   -- 6. RESOLVE TARGET CATEGORY
   --
   -- YES
   ---------------------------------------------------------------------------
   SELECT mc.category_id
   INTO   l_target_category_id
   FROM   apps.mtl_categories_kfv mc,
          apps.mtl_category_sets_b mcs
   WHERE  mcs.category_set_id =
          l_target_set_id
   AND    mc.structure_id =
          mcs.structure_id
   AND    RTRIM(
             UPPER(mc.concatenated_segments),
             '- '
          ) =
          UPPER(c_target_category)
   AND    (
             mcs.validate_flag = 'N'

             OR

             EXISTS
             (
                SELECT 1
                FROM   apps.mtl_category_set_valid_cats mvc
                WHERE  mvc.category_set_id =
                       mcs.category_set_id
                AND    mvc.category_id =
                       mc.category_id
             )
          );


   p_log(
      'Resolved Target Category [' ||
      c_target_category ||
      '], category_id=' ||
      l_target_category_id
   );


   ---------------------------------------------------------------------------
   -- 7. PROCESS ELIGIBLE ITEMS
   --
   -- Business Criteria:
   --
   --     Organization              = GRI
   --     Item Status               <> INACTIVE
   --     LOG ROLL / SLIT ROLL      = LOG ROLL
   ---------------------------------------------------------------------------
   FOR r_item IN
   (
      SELECT DISTINCT
             msik.inventory_item_id,
             msik.concatenated_segments AS item_number,
             msik.inventory_item_status_code
      FROM   apps.mtl_system_items_kfv msik,
             apps.mtl_item_categories mic
      WHERE  msik.organization_id =
             l_gri_org_id

      AND    NVL(
                UPPER(msik.inventory_item_status_code),
                '#NULL#'
             ) <> 'INACTIVE'

      AND    mic.inventory_item_id =
             msik.inventory_item_id

      AND    mic.organization_id =
             msik.organization_id

      AND    mic.category_set_id =
             l_source_set_id

      AND    mic.category_id =
             l_source_category_id

      ORDER BY
             msik.concatenated_segments
   )
   LOOP

      l_total := l_total + 1;


      BEGIN

         ---------------------------------------------------------------------
         -- 7A. CHECK IF YES IS ALREADY ASSIGNED
         ---------------------------------------------------------------------
         SELECT COUNT(*)
         INTO   l_yes_count
         FROM   apps.mtl_item_categories mic
         WHERE  mic.inventory_item_id =
                r_item.inventory_item_id

         AND    mic.organization_id =
                l_gri_org_id

         AND    mic.category_set_id =
                l_target_set_id

         AND    mic.category_id =
                l_target_category_id;


         ---------------------------------------------------------------------
         -- ALREADY YES
         ---------------------------------------------------------------------
         IF l_yes_count > 0 THEN

            l_already_yes :=
               l_already_yes + 1;


            p_log(
               'NO ACTION - Item [' ||
               r_item.item_number ||
               '] already has ' ||
               c_target_set_name ||
               ' = YES.'
            );


         ELSE

            ------------------------------------------------------------------
            -- 7B. CHECK CURRENT VALUE
            ------------------------------------------------------------------
            SELECT COUNT(*),
                   MIN(mic.category_id)
            INTO   l_current_count,
                   l_old_category_id
            FROM   apps.mtl_item_categories mic
            WHERE  mic.inventory_item_id =
                   r_item.inventory_item_id

            AND    mic.organization_id =
                   l_gri_org_id

            AND    mic.category_set_id =
                   l_target_set_id;


            ------------------------------------------------------------------
            -- 7C. NO CURRENT ASSIGNMENT
            --
            -- CREATE USE INHERITED PROPERTIES = YES
            ------------------------------------------------------------------
            IF l_current_count = 0 THEN

               l_return_status := NULL;
               l_errorcode     := NULL;
               l_msg_count     := NULL;
               l_msg_data      := NULL;
               l_api_message   := NULL;


               apps.inv_item_category_pub.create_category_assignment(
                  p_api_version         => 1.0,
                  p_init_msg_list       => apps.fnd_api.g_true,

                  ------------------------------------------------------------
                  -- CALLER CONTROLS TRANSACTION
                  ------------------------------------------------------------
                  p_commit              => apps.fnd_api.g_false,

                  x_return_status       => l_return_status,
                  x_errorcode           => l_errorcode,
                  x_msg_count           => l_msg_count,
                  x_msg_data            => l_msg_data,

                  p_category_id         => l_target_category_id,
                  p_category_set_id     => l_target_set_id,
                  p_inventory_item_id   => r_item.inventory_item_id,
                  p_organization_id     => l_gri_org_id
               );


               IF l_return_status =
                  apps.fnd_api.g_ret_sts_success
               THEN

                  l_created :=
                     l_created + 1;


                  p_log(
                     'CREATED - Item [' ||
                     r_item.item_number ||
                     '] assigned ' ||
                     c_target_set_name ||
                     ' = YES.'
                  );


               ELSE

                  l_errors :=
                     l_errors + 1;


                  l_api_message :=
                     f_api_messages(
                        l_msg_count,
                        l_msg_data
                     );


                  p_log(
                     'ERROR CREATE - Item [' ||
                     r_item.item_number ||
                     '], inventory_item_id=' ||
                     r_item.inventory_item_id ||
                     ', return_status=' ||
                     CASE
                        WHEN l_return_status IS NULL
                        THEN 'NULL'
                        ELSE l_return_status
                     END ||
                     ', errorcode=' ||
                     NVL(
                        TO_CHAR(l_errorcode),
                        'NULL'
                     ) ||
                     ', message=' ||
                     NVL(
                        l_api_message,
                        'No API message returned'
                     ),
                     apps.fnd_log.level_error
                  );

               END IF;


            ------------------------------------------------------------------
            -- 7D. EXACTLY ONE CURRENT VALUE
            --
            -- UPDATE CURRENT CATEGORY TO YES
            ------------------------------------------------------------------
            ELSIF l_current_count = 1 THEN


               BEGIN

                  SELECT mc.concatenated_segments
                  INTO   l_old_category_name
                  FROM   apps.mtl_categories_kfv mc
                  WHERE  mc.category_id =
                         l_old_category_id;


               EXCEPTION
                  WHEN NO_DATA_FOUND THEN

                     l_old_category_name :=
                        TO_CHAR(
                           l_old_category_id
                        );

               END;


               l_return_status := NULL;
               l_errorcode     := NULL;
               l_msg_count     := NULL;
               l_msg_data      := NULL;
               l_api_message   := NULL;


               apps.inv_item_category_pub.update_category_assignment(
                  p_api_version         => 1.0,
                  p_init_msg_list       => apps.fnd_api.g_true,

                  ------------------------------------------------------------
                  -- CALLER CONTROLS TRANSACTION
                  ------------------------------------------------------------
                  p_commit              => apps.fnd_api.g_false,

                  p_category_id         => l_target_category_id,
                  p_old_category_id     => l_old_category_id,
                  p_category_set_id     => l_target_set_id,
                  p_inventory_item_id   => r_item.inventory_item_id,
                  p_organization_id     => l_gri_org_id,

                  x_return_status       => l_return_status,
                  x_errorcode           => l_errorcode,
                  x_msg_count           => l_msg_count,
                  x_msg_data            => l_msg_data
               );


               IF l_return_status =
                  apps.fnd_api.g_ret_sts_success
               THEN

                  l_updated :=
                     l_updated + 1;


                  p_log(
                     'UPDATED - Item [' ||
                     r_item.item_number ||
                     '] ' ||
                     c_target_set_name ||
                     ' changed from [' ||
                     l_old_category_name ||
                     '] to [YES].'
                  );


               ELSE

                  l_errors :=
                     l_errors + 1;


                  l_api_message :=
                     f_api_messages(
                        l_msg_count,
                        l_msg_data
                     );


                  p_log(
                     'ERROR UPDATE - Item [' ||
                     r_item.item_number ||
                     '], inventory_item_id=' ||
                     r_item.inventory_item_id ||
                     ', old_category_id=' ||
                     l_old_category_id ||
                     ', return_status=' ||
                     CASE
                        WHEN l_return_status IS NULL
                        THEN 'NULL'
                        ELSE l_return_status
                     END ||
                     ', errorcode=' ||
                     NVL(
                        TO_CHAR(l_errorcode),
                        'NULL'
                     ) ||
                     ', message=' ||
                     NVL(
                        l_api_message,
                        'No API message returned'
                     ),
                     apps.fnd_log.level_error
                  );

               END IF;


            ------------------------------------------------------------------
            -- 7E. MORE THAN ONE CURRENT TARGET ASSIGNMENT
            --
            -- Do not guess which assignment should be replaced.
            ------------------------------------------------------------------
            ELSE

               l_skipped :=
                  l_skipped + 1;


               p_log(
                  'SKIPPED - Item [' ||
                  r_item.item_number ||
                  '] has ' ||
                  l_current_count ||
                  ' existing assignments in Category Set [' ||
                  c_target_set_name ||
                  ']. Manual review required.',
                  apps.fnd_log.level_error
               );

            END IF;

         END IF;


      
      EXCEPTION
         WHEN OTHERS THEN

            l_errors :=
               l_errors + 1;


            p_log(
               'UNEXPECTED ERROR - Item [' ||
               r_item.item_number ||
               '] inventory_item_id=' ||
               r_item.inventory_item_id ||
               ', SQLERRM=' ||
               SQLERRM ||
               ', BACKTRACE=' ||
               DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
               apps.fnd_log.level_error
            );

      END;


   END LOOP;


   ---------------------------------------------------------------------------
   -- 8. TRANSACTION CONTROL
   --
   ---------------------------------------------------------------------------
   COMMIT;


   ---------------------------------------------------------------------------
   -- 9. FINAL SUMMARY
   --
   -- FND_LOG is used so this diagnostic information can remain available   
   ---------------------------------------------------------------------------
   p_log(
      'COMPLETE - PRODUCTION RUN - COMMIT EXECUTED. ' ||
      'Total eligible=' ||
      l_total ||
      ', Created YES=' ||
      l_created ||
      ', Updated to YES=' ||
      l_updated ||
      ', Already YES=' ||
      l_already_yes ||
      ', Skipped=' ||
      l_skipped ||
      ', Errors=' ||
      l_errors,
      apps.fnd_log.level_event
   );


   ---------------------------------------------------------------------------
   -- SINGLE SCREEN MESSAGE ONLY
   --
   -- Avoids APEX SQL Scripts maximum-output errors.
   ---------------------------------------------------------------------------
   DBMS_OUTPUT.PUT_LINE(
      'VALIDATION COMPLETE - COMMIT EXECUTED. ' ||
      'Total=' ||
      l_total ||
      ', Created=' ||
      l_created ||
      ', Updated=' ||
      l_updated ||
      ', Already YES=' ||
      l_already_yes ||
      ', Skipped=' ||
      l_skipped ||
      ', Errors=' ||
      l_errors
   );


EXCEPTION
   WHEN OTHERS THEN

      ------------------------------------------------------------------------
      -- ALWAYS ROLLBACK ON FATAL ERROR
      ------------------------------------------------------------------------
      ROLLBACK;


      p_log(
         'FATAL ERROR - Entire transaction rolled back. ' ||
         'SQLERRM=' ||
         SQLERRM ||
         ', BACKTRACE=' ||
         DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
         apps.fnd_log.level_error
      );
          
END;
/