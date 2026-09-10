-- ============================================================================
-- eventos  --  o events_* do GA4 vetorizado: uma coluna por valor, um registro
--             por evento. Nada agregado, nada sessionizado.
--
--   Origem:  raulpavao-com-br.analytics_552236564.events_*   (export nativo GA4)
--   Destino: raulpavao-com-br.dados_tratados.eventos
--   Grao:    uma linha por evento (o mesmo do events_*).
--   Janela:  ultimos 28 dias, tabelas diarias fechadas (sem intraday).
--
-- Colunas = as que a propriedade 552236564 preenche. Cada STRUCT abre em
-- <caminho>_<campo>; cada chave de event_params abre em param_<chave>; cada
-- event_name vira um indicador evento_<nome> (1 na linha daquele evento, 0 nas
-- outras) -- e-vetoriza o nome do evento sem sessionizar. O array items sai em
-- dados_tratados.eventos_itens.
--
-- Ajuste antes de usar:
--   1) a janela de dias no filtro _TABLE_SUFFIX (fim do arquivo);
--   2) a lista de colunas evento_<nome>: rode um SELECT DISTINCT event_name na
--      janela e crie uma coluna por valor. Aqui: click, first_visit, page_view,
--      scroll, session_start, user_engagement;
--   3) numa propriedade com Google Ads / SA360 / DV360 linkados ou com
--      e-commerce, some as colunas dessas sub-structs / desses params.
-- ============================================================================
CREATE OR REPLACE VIEW `raulpavao-com-br.dados_tratados.eventos` AS
SELECT
  CONCAT('analytics_552236564.events_', _TABLE_SUFFIX)  AS registro_origem,

  event_date,
  event_timestamp,
  event_name,
  IF(event_name = 'click',           1, 0)  AS evento_click,
  IF(event_name = 'first_visit',     1, 0)  AS evento_first_visit,
  IF(event_name = 'page_view',       1, 0)  AS evento_page_view,
  IF(event_name = 'scroll',          1, 0)  AS evento_scroll,
  IF(event_name = 'session_start',   1, 0)  AS evento_session_start,
  IF(event_name = 'user_engagement', 1, 0)  AS evento_user_engagement,
  batch_event_index,
  batch_ordering_id,
  batch_page_id,

  device.category                       AS device_category,
  device.is_limited_ad_tracking         AS device_is_limited_ad_tracking,
  device.language                       AS device_language,
  device.mobile_brand_name              AS device_mobile_brand_name,
  device.mobile_marketing_name          AS device_mobile_marketing_name,
  device.mobile_model_name              AS device_mobile_model_name,
  device.mobile_os_hardware_model       AS device_mobile_os_hardware_model,
  device.operating_system               AS device_operating_system,
  device.operating_system_version       AS device_operating_system_version,
  device.web_info.browser               AS device_web_info_browser,
  device.web_info.browser_version       AS device_web_info_browser_version,
  device.web_info.hostname              AS device_web_info_hostname,

  event_bundle_sequence_id,

  geo.city           AS geo_city,
  geo.continent      AS geo_continent,
  geo.country        AS geo_country,
  geo.metro          AS geo_metro,
  geo.region         AS geo_region,
  geo.sub_continent  AS geo_sub_continent,

  is_active_user,

  (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING)) FROM UNNEST(event_params) p WHERE p.key = 'anonymize_ip')          AS param_anonymize_ip,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'batch_ordering_id')     AS param_batch_ordering_id,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'batch_page_id')         AS param_batch_page_id,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'engaged_session_event') AS param_engaged_session_event,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'engagement_time_msec')  AS param_engagement_time_msec,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'entrances')             AS param_entrances,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'ga_session_id')         AS param_ga_session_id,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'ga_session_number')     AS param_ga_session_number,
  (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING)) FROM UNNEST(event_params) p WHERE p.key = 'ignore_referrer')       AS param_ignore_referrer,
  (SELECT p.value.string_value FROM UNNEST(event_params) p WHERE p.key = 'page_location')         AS param_page_location,
  (SELECT p.value.string_value FROM UNNEST(event_params) p WHERE p.key = 'page_path')             AS param_page_path,
  (SELECT p.value.string_value FROM UNNEST(event_params) p WHERE p.key = 'page_referrer')         AS param_page_referrer,
  (SELECT p.value.string_value FROM UNNEST(event_params) p WHERE p.key = 'page_title')            AS param_page_title,
  (SELECT p.value.int_value    FROM UNNEST(event_params) p WHERE p.key = 'percent_scrolled')      AS param_percent_scrolled,
  (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING)) FROM UNNEST(event_params) p WHERE p.key = 'session_engaged')       AS param_session_engaged,

  platform,
  privacy_info.uses_transient_token     AS privacy_info_uses_transient_token,

  session_traffic_source_last_click.cm360_campaign.account_id               AS session_traffic_source_last_click_cm360_campaign_account_id,
  session_traffic_source_last_click.cm360_campaign.account_name             AS session_traffic_source_last_click_cm360_campaign_account_name,
  session_traffic_source_last_click.cm360_campaign.advertiser_id            AS session_traffic_source_last_click_cm360_campaign_advertiser_id,
  session_traffic_source_last_click.cm360_campaign.advertiser_name          AS session_traffic_source_last_click_cm360_campaign_advertiser_name,
  session_traffic_source_last_click.cm360_campaign.campaign_id              AS session_traffic_source_last_click_cm360_campaign_campaign_id,
  session_traffic_source_last_click.cm360_campaign.campaign_name            AS session_traffic_source_last_click_cm360_campaign_campaign_name,
  session_traffic_source_last_click.cm360_campaign.creative_format          AS session_traffic_source_last_click_cm360_campaign_creative_format,
  session_traffic_source_last_click.cm360_campaign.creative_id              AS session_traffic_source_last_click_cm360_campaign_creative_id,
  session_traffic_source_last_click.cm360_campaign.creative_name            AS session_traffic_source_last_click_cm360_campaign_creative_name,
  session_traffic_source_last_click.cm360_campaign.creative_type            AS session_traffic_source_last_click_cm360_campaign_creative_type,
  session_traffic_source_last_click.cm360_campaign.creative_type_id         AS session_traffic_source_last_click_cm360_campaign_creative_type_id,
  session_traffic_source_last_click.cm360_campaign.creative_version         AS session_traffic_source_last_click_cm360_campaign_creative_version,
  session_traffic_source_last_click.cm360_campaign.medium                   AS session_traffic_source_last_click_cm360_campaign_medium,
  session_traffic_source_last_click.cm360_campaign.placement_cost_structure AS session_traffic_source_last_click_cm360_campaign_placement_cost_structure,
  session_traffic_source_last_click.cm360_campaign.placement_id             AS session_traffic_source_last_click_cm360_campaign_placement_id,
  session_traffic_source_last_click.cm360_campaign.placement_name           AS session_traffic_source_last_click_cm360_campaign_placement_name,
  session_traffic_source_last_click.cm360_campaign.rendering_id             AS session_traffic_source_last_click_cm360_campaign_rendering_id,
  session_traffic_source_last_click.cm360_campaign.site_id                  AS session_traffic_source_last_click_cm360_campaign_site_id,
  session_traffic_source_last_click.cm360_campaign.site_name                AS session_traffic_source_last_click_cm360_campaign_site_name,
  session_traffic_source_last_click.cm360_campaign.source                   AS session_traffic_source_last_click_cm360_campaign_source,
  session_traffic_source_last_click.cross_channel_campaign.campaign_name          AS session_traffic_source_last_click_cross_channel_campaign_campaign_name,
  session_traffic_source_last_click.cross_channel_campaign.default_channel_group  AS session_traffic_source_last_click_cross_channel_campaign_default_channel_group,
  session_traffic_source_last_click.cross_channel_campaign.medium                 AS session_traffic_source_last_click_cross_channel_campaign_medium,
  session_traffic_source_last_click.cross_channel_campaign.primary_channel_group  AS session_traffic_source_last_click_cross_channel_campaign_primary_channel_group,
  session_traffic_source_last_click.cross_channel_campaign.source                 AS session_traffic_source_last_click_cross_channel_campaign_source,
  session_traffic_source_last_click.cross_channel_campaign.source_platform        AS session_traffic_source_last_click_cross_channel_campaign_source_platform,
  session_traffic_source_last_click.manual_campaign.campaign_id      AS session_traffic_source_last_click_manual_campaign_campaign_id,
  session_traffic_source_last_click.manual_campaign.campaign_name    AS session_traffic_source_last_click_manual_campaign_campaign_name,
  session_traffic_source_last_click.manual_campaign.content          AS session_traffic_source_last_click_manual_campaign_content,
  session_traffic_source_last_click.manual_campaign.creative_format  AS session_traffic_source_last_click_manual_campaign_creative_format,
  session_traffic_source_last_click.manual_campaign.marketing_tactic AS session_traffic_source_last_click_manual_campaign_marketing_tactic,
  session_traffic_source_last_click.manual_campaign.medium           AS session_traffic_source_last_click_manual_campaign_medium,
  session_traffic_source_last_click.manual_campaign.source           AS session_traffic_source_last_click_manual_campaign_source,
  session_traffic_source_last_click.manual_campaign.source_platform  AS session_traffic_source_last_click_manual_campaign_source_platform,
  session_traffic_source_last_click.manual_campaign.term             AS session_traffic_source_last_click_manual_campaign_term,

  stream_id,
  traffic_source.medium  AS traffic_source_medium,
  traffic_source.name    AS traffic_source_name,
  traffic_source.source  AS traffic_source_source,
  user_first_touch_timestamp,
  user_pseudo_id

FROM `raulpavao-com-br.analytics_552236564.events_*`
WHERE _TABLE_SUFFIX NOT LIKE 'intraday%'
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY));
