-- Caminho 3: a base "sem teto" — o fato_sessoes com TODAS as dimensões e
-- métricas de sessão que dá pra tirar do evento cru. É o que os caminhos
-- 2/5/6 (Data API) não conseguem: lá o limite é 9 dimensões por chamada.
--
-- Grão: uma linha por combinação das dimensões abaixo (na prática, ~1 por
-- sessão neste site). Últimos 28 dias, tabelas diárias fechadas.
--
-- Troque:  SEU_PROJETO  analytics_XXXXXXXXX  (dataset do export)
-- Ajuste:  KEY_EVENTS   (os eventos marcados como principais na sua propriedade)

DECLARE KEY_EVENTS ARRAY<STRING> DEFAULT ['purchase', 'generate_lead', 'sign_up', 'contact'];

WITH ev AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')       AS session_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number')   AS session_number,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'session_engaged')     AS session_engaged,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'engagement_time_msec')AS engagement_time_msec,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')       AS page_location,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer')       AS page_referrer,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'entrances')           AS entrances,
    event_name,
    event_date,
    event_timestamp,
    -- device
    device.category, device.mobile_brand_name, device.mobile_model_name,
    device.operating_system, device.operating_system_version, device.language,
    device.web_info.browser, device.web_info.browser_version, device.web_info.hostname,
    -- geo
    geo.continent, geo.sub_continent, geo.country, geo.region, geo.city, geo.metro,
    -- atribuição last-click da sessão
    s.cross_channel_campaign.default_channel_group AS lc_channel,
    s.cross_channel_campaign.primary_channel_group AS lc_primary_channel,
    COALESCE(s.manual_campaign.source,   s.cross_channel_campaign.source)      AS lc_source,
    COALESCE(s.manual_campaign.medium,   s.cross_channel_campaign.medium)      AS lc_medium,
    COALESCE(s.manual_campaign.campaign_name, s.cross_channel_campaign.campaign_name) AS lc_campaign,
    COALESCE(s.manual_campaign.campaign_id,   s.cross_channel_campaign.campaign_id)   AS lc_campaign_id,
    s.manual_campaign.content         AS lc_content,
    s.manual_campaign.term            AS lc_term,
    s.manual_campaign.source_platform AS lc_source_platform,
    s.google_ads_campaign.campaign_name AS gads_campaign,
    s.google_ads_campaign.ad_group_name AS gads_ad_group,
    -- ecommerce (só relevante em eventos de compra)
    ecommerce.transaction_id,
    ecommerce.purchase_revenue,
    ecommerce.total_item_quantity,
    ecommerce.refund_value,
    stream_id, platform
  FROM `SEU_PROJETO.analytics_XXXXXXXXX.events_*` AS e,
       UNNEST([e.session_traffic_source_last_click]) AS s
  WHERE _TABLE_SUFFIX NOT LIKE 'intraday%'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY))
),

sess AS (                                  -- uma linha por sessão, com todos os atributos e os ingredientes das métricas
  SELECT
    user_pseudo_id, session_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)))                              AS date,
    -- atributos constantes da sessão
    ANY_VALUE(lc_channel)          AS channel,
    ANY_VALUE(lc_primary_channel)  AS primary_channel,
    ANY_VALUE(lc_source)           AS source,
    ANY_VALUE(lc_medium)           AS medium,
    ANY_VALUE(lc_campaign)         AS campaign,
    ANY_VALUE(lc_campaign_id)      AS campaign_id,
    ANY_VALUE(lc_content)          AS ad_content,
    ANY_VALUE(lc_term)             AS ad_term,
    ANY_VALUE(lc_source_platform)  AS source_platform,
    ANY_VALUE(gads_campaign)       AS google_ads_campaign,
    ANY_VALUE(gads_ad_group)       AS google_ads_ad_group,
    ANY_VALUE(category)            AS device_category,
    ANY_VALUE(mobile_brand_name)  AS device_brand,
    ANY_VALUE(mobile_model_name)  AS device_model,
    ANY_VALUE(operating_system)   AS operating_system,
    ANY_VALUE(operating_system_version) AS operating_system_version,
    ANY_VALUE(browser)            AS browser,
    ANY_VALUE(browser_version)    AS browser_version,
    ANY_VALUE(hostname)           AS hostname,
    ANY_VALUE(language)           AS language,
    ANY_VALUE(continent)          AS continent,
    ANY_VALUE(sub_continent)      AS sub_continent,
    ANY_VALUE(country)            AS country,
    ANY_VALUE(region)             AS region,
    ANY_VALUE(city)               AS city,
    ANY_VALUE(metro)              AS metro,
    ANY_VALUE(platform)           AS platform,
    ANY_VALUE(stream_id)          AS stream_id,
    -- landing page = page_location do primeiro page_view; referrer da entrada
    ARRAY_AGG(IF(event_name = 'page_view', page_location, NULL) IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS landing_page,
    ARRAY_AGG(IF(entrances = 1, page_referrer, NULL) IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]           AS entry_referrer,
    -- ingredientes das métricas
    MAX(session_number = 1)                              AS is_new_user,
    MAX(session_engaged = '1')                           AS is_engaged,
    SUM(IFNULL(engagement_time_msec, 0)) / 1000.0        AS engagement_time_sec,
    (MAX(event_timestamp) - MIN(event_timestamp)) / 1e6  AS session_duration_sec,
    COUNT(*)                                             AS event_count,
    COUNTIF(event_name = 'page_view')                    AS page_views,
    COUNTIF(event_name = 'first_visit')                  AS first_visits,
    COUNTIF(event_name = 'scroll')                       AS scrolls,
    COUNTIF(event_name = 'click')                        AS outbound_clicks,
    COUNTIF(event_name = 'view_search_results')          AS site_searches,
    COUNTIF(event_name = 'file_download')                AS file_downloads,
    COUNTIF(event_name = 'video_start')                  AS video_starts,
    COUNTIF(event_name = 'form_start')                   AS form_starts,
    COUNTIF(event_name = 'form_submit')                  AS form_submits,
    COUNTIF(event_name = 'view_item')                    AS item_views,
    COUNTIF(event_name = 'add_to_cart')                  AS add_to_carts,
    COUNTIF(event_name = 'begin_checkout')               AS checkouts,
    COUNTIF(event_name = 'purchase')                     AS transactions,
    COUNTIF(event_name IN UNNEST(KEY_EVENTS))            AS key_events,
    SUM(IF(event_name = 'purchase', IFNULL(purchase_revenue, 0), 0))     AS purchase_revenue,
    SUM(IF(event_name = 'purchase', IFNULL(total_item_quantity, 0), 0))  AS items_purchased,
    SUM(IFNULL(refund_value, 0))                                          AS refund_value
  FROM ev
  WHERE session_id IS NOT NULL
  GROUP BY user_pseudo_id, session_id
)

SELECT
  -- ===== dimensões (uma linha por combinação) =====
  FORMAT_DATE('%Y%m%d', date)          AS date,
  channel, primary_channel,
  source, medium, campaign,
  IFNULL(campaign_id, '(not set)')     AS campaign_id,
  IFNULL(ad_content, '(not set)')      AS ad_content,
  IFNULL(ad_term, '(not set)')         AS ad_term,
  source_platform,
  google_ads_campaign, google_ads_ad_group,
  device_category, device_brand, device_model,
  operating_system, operating_system_version,
  browser, browser_version, hostname, language,
  continent, sub_continent, country, region, city, metro,
  platform, stream_id,
  landing_page, entry_referrer,

  -- ===== métricas =====
  COUNT(*)                                             AS sessions,
  COUNT(DISTINCT user_pseudo_id)                       AS total_users,
  COUNT(DISTINCT IF(is_new_user, user_pseudo_id, NULL)) AS new_users,
  COUNTIF(is_engaged)                                  AS engaged_sessions,
  SAFE_DIVIDE(COUNTIF(is_engaged), COUNT(*))           AS engagement_rate,
  1 - SAFE_DIVIDE(COUNTIF(is_engaged), COUNT(*))       AS bounce_rate,
  SUM(engagement_time_sec)                             AS user_engagement_duration_sec,
  SAFE_DIVIDE(SUM(engagement_time_sec), COUNTIF(is_engaged)) AS avg_engagement_time_per_session_sec,
  AVG(session_duration_sec)                            AS avg_session_duration_sec,
  SUM(event_count)                                     AS event_count,
  SAFE_DIVIDE(SUM(event_count), COUNT(*))              AS events_per_session,
  SUM(page_views)                                      AS screen_page_views,
  SAFE_DIVIDE(SUM(page_views), COUNT(*))               AS pages_per_session,
  SUM(first_visits)                                    AS first_visits,
  SUM(scrolls)                                         AS scrolls,
  SUM(outbound_clicks)                                 AS outbound_clicks,
  SUM(site_searches)                                   AS site_searches,
  SUM(file_downloads)                                  AS file_downloads,
  SUM(video_starts)                                    AS video_starts,
  SUM(form_starts)                                     AS form_starts,
  SUM(form_submits)                                    AS form_submits,
  SUM(key_events)                                      AS key_events,
  SAFE_DIVIDE(COUNTIF(key_events > 0), COUNT(*))       AS session_key_event_rate,
  SUM(item_views)                                      AS item_views,
  SUM(add_to_carts)                                    AS add_to_carts,
  SUM(checkouts)                                       AS checkouts,
  SUM(transactions)                                    AS transactions,
  SUM(purchase_revenue)                                AS purchase_revenue,
  SUM(items_purchased)                                 AS items_purchased,
  SUM(refund_value)                                    AS refund_value,
  SAFE_DIVIDE(SUM(transactions), COUNT(*))             AS ecommerce_conversion_rate
FROM sess
GROUP BY
  date, channel, primary_channel, source, medium, campaign, campaign_id,
  ad_content, ad_term, source_platform, google_ads_campaign, google_ads_ad_group,
  device_category, device_brand, device_model, operating_system,
  operating_system_version, browser, browser_version, hostname, language,
  continent, sub_continent, country, region, city, metro, platform, stream_id,
  landing_page, entry_referrer
ORDER BY sessions DESC;
