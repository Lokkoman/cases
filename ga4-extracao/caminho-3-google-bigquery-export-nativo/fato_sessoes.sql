-- ============================================================================
-- fato_sessoes  —  a base de sessão "sem teto", montada do evento cru.
--
--   Origem:  raulpavao-com-br.analytics_552236564.events_*   (export nativo GA4)
--   Destino: raulpavao-com-br.dados_tratados.fato_sessoes
--   Grão:    uma linha por combinação das dimensões abaixo (~1 por sessão).
--   Janela:  últimos 28 dias, tabelas diárias fechadas (sem intraday).
--
-- É o que a GA4 Data API (caminhos 1, 2, 5, 6) não consegue: lá o limite é
-- 9 dimensões por chamada. Aqui a única fronteira é o schema do evento cru.
--
-- Ajuste antes de usar:
--   PROP_TZ      fuso da propriedade GA4 (para a hora local da sessão)
--   KEY_EVENTS   os eventos marcados como principais na sua propriedade
-- ============================================================================
CREATE OR REPLACE VIEW `raulpavao-com-br.dados_tratados.fato_sessoes` AS

WITH
  const AS (
    SELECT
      'raulpavao-com-br.analytics_552236564' AS source_dataset,
      'events_*'                             AS source_table,
      'America/Sao_Paulo'                    AS prop_tz,
      ['purchase', 'generate_lead', 'sign_up', 'contact'] AS key_events
  ),

  ev AS (                                    -- eventos achatados, últimos 28 dias
    SELECT
      e.user_pseudo_id,
      (SELECT value.int_value    FROM UNNEST(e.event_params) WHERE key = 'ga_session_id')        AS session_id,
      (SELECT value.int_value    FROM UNNEST(e.event_params) WHERE key = 'ga_session_number')    AS session_number,
      (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'session_engaged')      AS session_engaged,
      (SELECT value.int_value    FROM UNNEST(e.event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
      (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'page_location')        AS page_location,
      (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'page_title')           AS page_title,
      (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'page_referrer')        AS page_referrer,
      (SELECT value.int_value    FROM UNNEST(e.event_params) WHERE key = 'entrances')            AS entrances,
      e.event_name,
      e.event_timestamp,
      e.is_active_user,
      -- device
      e.device.category, e.device.mobile_brand_name, e.device.mobile_model_name,
      e.device.mobile_marketing_name, e.device.operating_system, e.device.operating_system_version,
      e.device.language, e.device.is_limited_ad_tracking,
      e.device.web_info.browser, e.device.web_info.browser_version, e.device.web_info.hostname,
      -- geo
      e.geo.continent, e.geo.sub_continent, e.geo.country, e.geo.region, e.geo.city, e.geo.metro,
      -- primeiro toque do usuário (user-scoped, constante)
      e.traffic_source.source AS fu_source,
      e.traffic_source.medium AS fu_medium,
      e.traffic_source.name   AS fu_campaign,
      -- click ids coletados no evento
      e.collected_traffic_source.gclid   AS gclid,
      e.collected_traffic_source.dclid   AS dclid,
      e.collected_traffic_source.srsltid AS srsltid,
      -- atribuição last-click da sessão
      s.cross_channel_campaign.default_channel_group AS lc_channel,
      s.cross_channel_campaign.primary_channel_group AS lc_primary_channel,
      COALESCE(s.manual_campaign.source,        s.cross_channel_campaign.source)        AS lc_source,
      COALESCE(s.manual_campaign.medium,        s.cross_channel_campaign.medium)        AS lc_medium,
      COALESCE(s.manual_campaign.campaign_name, s.cross_channel_campaign.campaign_name) AS lc_campaign,
      COALESCE(s.manual_campaign.campaign_id,   s.cross_channel_campaign.campaign_id)   AS lc_campaign_id,
      s.manual_campaign.content          AS lc_content,
      s.manual_campaign.term             AS lc_term,
      s.manual_campaign.source_platform  AS lc_source_platform,
      s.manual_campaign.creative_format  AS lc_creative_format,
      s.manual_campaign.marketing_tactic AS lc_marketing_tactic,
      s.google_ads_campaign.campaign_name AS gads_campaign,
      s.google_ads_campaign.campaign_id   AS gads_campaign_id,
      s.google_ads_campaign.ad_group_name AS gads_ad_group,
      s.google_ads_campaign.account_name  AS gads_account,
      -- ecommerce (relevante nos eventos de compra/reembolso)
      e.ecommerce.purchase_revenue,
      e.ecommerce.shipping_value,
      e.ecommerce.tax_value,
      e.ecommerce.refund_value,
      e.ecommerce.total_item_quantity,
      e.ecommerce.unique_items,
      e.stream_id, e.platform
    FROM `raulpavao-com-br.analytics_552236564.events_*` AS e,
         UNNEST([e.session_traffic_source_last_click]) AS s
    WHERE _TABLE_SUFFIX NOT LIKE 'intraday%'
      AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY))
  ),

  sess AS (                                  -- uma linha por sessão
    SELECT
      user_pseudo_id, session_id,
      MIN(event_timestamp) AS session_start_ts,
      -- atributos constantes
      ANY_VALUE(session_number)      AS session_number,
      ANY_VALUE(lc_channel)          AS channel,
      ANY_VALUE(lc_primary_channel)  AS primary_channel,
      ANY_VALUE(lc_source)           AS source,
      ANY_VALUE(lc_medium)           AS medium,
      ANY_VALUE(lc_campaign)         AS campaign,
      ANY_VALUE(lc_campaign_id)      AS campaign_id,
      ANY_VALUE(lc_content)          AS ad_content,
      ANY_VALUE(lc_term)             AS ad_term,
      ANY_VALUE(lc_source_platform)  AS source_platform,
      ANY_VALUE(lc_creative_format)  AS creative_format,
      ANY_VALUE(lc_marketing_tactic) AS marketing_tactic,
      ANY_VALUE(gads_campaign)       AS google_ads_campaign,
      ANY_VALUE(gads_campaign_id)    AS google_ads_campaign_id,
      ANY_VALUE(gads_ad_group)       AS google_ads_ad_group,
      ANY_VALUE(gads_account)        AS google_ads_account,
      ANY_VALUE(fu_source)           AS first_user_source,
      ANY_VALUE(fu_medium)           AS first_user_medium,
      ANY_VALUE(fu_campaign)         AS first_user_campaign,
      LOGICAL_OR(gclid   IS NOT NULL) AS has_gclid,
      LOGICAL_OR(dclid   IS NOT NULL) AS has_dclid,
      LOGICAL_OR(srsltid IS NOT NULL) AS has_srsltid,
      ANY_VALUE(category)                  AS device_category,
      ANY_VALUE(mobile_brand_name)        AS device_brand,
      ANY_VALUE(mobile_model_name)        AS device_model,
      ANY_VALUE(mobile_marketing_name)    AS device_marketing_name,
      ANY_VALUE(operating_system)         AS operating_system,
      ANY_VALUE(operating_system_version) AS operating_system_version,
      ANY_VALUE(browser)                  AS browser,
      ANY_VALUE(browser_version)          AS browser_version,
      ANY_VALUE(hostname)                 AS hostname,
      ANY_VALUE(language)                 AS language,
      ANY_VALUE(is_limited_ad_tracking)   AS is_limited_ad_tracking,
      ANY_VALUE(continent)     AS continent,
      ANY_VALUE(sub_continent) AS sub_continent,
      ANY_VALUE(country)       AS country,
      ANY_VALUE(region)        AS region,
      ANY_VALUE(city)          AS city,
      ANY_VALUE(metro)         AS metro,
      ANY_VALUE(platform)      AS platform,
      ANY_VALUE(stream_id)     AS stream_id,
      -- páginas de entrada / saída
      ARRAY_AGG(IF(event_name = 'page_view', page_location, NULL) IGNORE NULLS ORDER BY event_timestamp)[SAFE_OFFSET(0)]                          AS landing_page,
      ARRAY_AGG(IF(event_name = 'page_view', page_title,    NULL) IGNORE NULLS ORDER BY event_timestamp)[SAFE_OFFSET(0)]                          AS landing_page_title,
      ARRAY_AGG(IF(event_name = 'page_view', page_location, NULL) IGNORE NULLS ORDER BY event_timestamp DESC)[SAFE_OFFSET(0)]                     AS exit_page,
      ARRAY_AGG(IF(entrances = 1, page_referrer, NULL)            IGNORE NULLS ORDER BY event_timestamp)[SAFE_OFFSET(0)]                          AS entry_referrer,
      -- ingredientes das métricas
      MAX(session_number = 1)                             AS is_first_session,
      MAX(is_active_user)                                 AS is_active_user,
      MAX(session_engaged = '1')                          AS is_engaged,
      SUM(IFNULL(engagement_time_msec, 0)) / 1000.0       AS engagement_time_sec,
      (MAX(event_timestamp) - MIN(event_timestamp)) / 1e6 AS session_duration_sec,
      COUNT(*)                                            AS event_count,
      COUNTIF(event_name = 'page_view')          AS page_views,
      COUNTIF(IFNULL(entrances, 0) = 1)          AS entrances,
      COUNTIF(event_name = 'first_visit')        AS first_visits,
      COUNTIF(event_name = 'scroll')             AS scrolls,
      COUNTIF(event_name = 'click')              AS outbound_clicks,
      COUNTIF(event_name = 'view_search_results') AS site_searches,
      COUNTIF(event_name = 'file_download')      AS file_downloads,
      COUNTIF(event_name = 'video_start')        AS video_starts,
      COUNTIF(event_name = 'video_progress')     AS video_progress,
      COUNTIF(event_name = 'video_complete')     AS video_completes,
      COUNTIF(event_name = 'form_start')         AS form_starts,
      COUNTIF(event_name = 'form_submit')        AS form_submits,
      COUNTIF(event_name = 'view_promotion')     AS promotion_views,
      COUNTIF(event_name = 'select_promotion')   AS promotion_clicks,
      COUNTIF(event_name = 'view_item')          AS item_views,
      COUNTIF(event_name = 'add_to_cart')        AS add_to_carts,
      COUNTIF(event_name = 'remove_from_cart')   AS remove_from_carts,
      COUNTIF(event_name = 'view_cart')          AS cart_views,
      COUNTIF(event_name = 'begin_checkout')     AS checkouts,
      COUNTIF(event_name = 'add_shipping_info')  AS add_shipping_info,
      COUNTIF(event_name = 'add_payment_info')   AS add_payment_info,
      COUNTIF(event_name = 'purchase')           AS transactions,
      COUNTIF(event_name = 'refund')             AS refunds,
      COUNTIF(event_name IN UNNEST((SELECT key_events FROM const))) AS key_events,
      SUM(IF(event_name = 'purchase', IFNULL(purchase_revenue, 0), 0)) AS purchase_revenue,
      SUM(IF(event_name = 'purchase', IFNULL(shipping_value, 0), 0))   AS shipping_value,
      SUM(IF(event_name = 'purchase', IFNULL(tax_value, 0), 0))        AS tax_value,
      SUM(IF(event_name = 'purchase', IFNULL(total_item_quantity, 0), 0)) AS items_purchased,
      SUM(IF(event_name = 'purchase', IFNULL(unique_items, 0), 0))     AS unique_items,
      SUM(IFNULL(refund_value, 0))                                     AS refund_value
    FROM ev
    WHERE session_id IS NOT NULL
    GROUP BY user_pseudo_id, session_id
  )

SELECT
  -- ===== referência de origem =====
  (SELECT source_dataset FROM const) AS _source_dataset,
  (SELECT source_table   FROM const) AS _source_table,
  CURRENT_TIMESTAMP()                AS _extracted_at,

  -- ===== dimensões =====
  FORMAT_DATE('%Y%m%d', DATE(TIMESTAMP_MICROS(session_start_ts), (SELECT prop_tz FROM const))) AS date,
  EXTRACT(HOUR FROM TIMESTAMP_MICROS(session_start_ts) AT TIME ZONE (SELECT prop_tz FROM const)) AS session_start_hour,
  session_number,
  IFNULL(channel, '(not set)')          AS channel,
  IFNULL(primary_channel, '(not set)')  AS primary_channel,
  source, medium, campaign,
  IFNULL(campaign_id, '(not set)')      AS campaign_id,
  IFNULL(ad_content, '(not set)')       AS ad_content,
  IFNULL(ad_term, '(not set)')          AS ad_term,
  source_platform, creative_format, marketing_tactic,
  google_ads_campaign, google_ads_campaign_id, google_ads_ad_group, google_ads_account,
  first_user_source, first_user_medium, first_user_campaign,
  has_gclid, has_dclid, has_srsltid,
  device_category, device_brand, device_model, device_marketing_name,
  operating_system, operating_system_version,
  browser, browser_version, hostname, language, is_limited_ad_tracking,
  continent, sub_continent, country, region, city, metro,
  platform, stream_id,
  landing_page, landing_page_title, exit_page, entry_referrer,

  -- ===== métricas =====
  COUNT(*)                                              AS sessions,
  COUNT(DISTINCT user_pseudo_id)                        AS total_users,
  COUNT(DISTINCT IF(is_first_session, user_pseudo_id, NULL)) AS new_users,
  COUNT(DISTINCT IF(is_active_user, user_pseudo_id, NULL))   AS active_users,
  COUNTIF(is_engaged)                                   AS engaged_sessions,
  SAFE_DIVIDE(COUNTIF(is_engaged), COUNT(*))            AS engagement_rate,
  1 - SAFE_DIVIDE(COUNTIF(is_engaged), COUNT(*))        AS bounce_rate,
  SUM(engagement_time_sec)                              AS user_engagement_duration_sec,
  SAFE_DIVIDE(SUM(engagement_time_sec), COUNTIF(is_engaged)) AS avg_engagement_time_per_session_sec,
  AVG(session_duration_sec)                             AS avg_session_duration_sec,
  SUM(event_count)                                      AS event_count,
  SAFE_DIVIDE(SUM(event_count), COUNT(*))               AS events_per_session,
  SUM(page_views)                                       AS screen_page_views,
  SAFE_DIVIDE(SUM(page_views), COUNT(*))                AS pages_per_session,
  SUM(entrances)                                        AS entrances,
  SUM(first_visits)                                     AS first_visits,
  SUM(scrolls)                                          AS scrolls,
  SUM(outbound_clicks)                                  AS outbound_clicks,
  SUM(site_searches)                                    AS site_searches,
  SUM(file_downloads)                                   AS file_downloads,
  SUM(video_starts)                                     AS video_starts,
  SUM(video_progress)                                   AS video_progress,
  SUM(video_completes)                                  AS video_completes,
  SUM(form_starts)                                      AS form_starts,
  SUM(form_submits)                                     AS form_submits,
  SUM(promotion_views)                                  AS promotion_views,
  SUM(promotion_clicks)                                 AS promotion_clicks,
  SUM(key_events)                                       AS key_events,
  SAFE_DIVIDE(COUNTIF(key_events > 0), COUNT(*))        AS session_key_event_rate,
  SUM(item_views)                                       AS item_views,
  SUM(add_to_carts)                                     AS add_to_carts,
  SUM(remove_from_carts)                                AS remove_from_carts,
  SUM(cart_views)                                       AS cart_views,
  SUM(checkouts)                                        AS checkouts,
  SUM(add_shipping_info)                                AS add_shipping_info,
  SUM(add_payment_info)                                 AS add_payment_info,
  SUM(transactions)                                     AS transactions,
  SUM(refunds)                                          AS refunds,
  SAFE_DIVIDE(SUM(transactions), COUNT(*))              AS ecommerce_conversion_rate,
  SUM(purchase_revenue)                                 AS purchase_revenue,
  SUM(shipping_value)                                   AS shipping_value,
  SUM(tax_value)                                        AS tax_value,
  SUM(refund_value)                                     AS refund_value,
  SUM(items_purchased)                                  AS items_purchased,
  SUM(unique_items)                                     AS unique_items
FROM sess
GROUP BY
  date, session_start_hour, session_number, channel, primary_channel, source, medium,
  campaign, campaign_id, ad_content, ad_term, source_platform, creative_format,
  marketing_tactic, google_ads_campaign, google_ads_campaign_id, google_ads_ad_group,
  google_ads_account, first_user_source, first_user_medium, first_user_campaign,
  has_gclid, has_dclid, has_srsltid, device_category, device_brand, device_model,
  device_marketing_name, operating_system, operating_system_version, browser,
  browser_version, hostname, language, is_limited_ad_tracking, continent, sub_continent,
  country, region, city, metro, platform, stream_id, landing_page, landing_page_title,
  exit_page, entry_referrer
ORDER BY sessions DESC;
