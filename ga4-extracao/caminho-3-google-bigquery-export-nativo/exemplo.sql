-- Caminho 3: export nativo GA4 -> BigQuery.
--
-- Troque:
--   SEU_PROJETO         pelo id do projeto GCP
--   analytics_XXXXXXXXX pelo dataset do export (analytics_<ID_DA_PROPRIEDADE>)

-- ============================================================================
-- 1) Formato do dado: pegar um parametro de dentro de event_params (array).
--    page_location e ga_session_id do page_view de ontem.
-- ============================================================================
SELECT
  TIMESTAMP_MICROS(event_timestamp)                                                AS quando,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS pagina,
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS sessao_id
FROM `SEU_PROJETO.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'page_view'
ORDER BY quando
LIMIT 50;


-- ============================================================================
-- 2) fato_sessoes por SQL: mesmo schema dos caminhos 2, 5 e 6, mas sem o teto
--    de 9 dimensoes da Data API (aqui daria pra por quantas quisesse).
--    Ultimos 28 dias, tabelas diarias fechadas (sem intraday).
--
--    Aproximacoes assumidas:
--      - novos usuarios = sessao com ga_session_number = 1
--      - key events = eventos cujo nome esta na sua lista (ajuste KEY_EVENTS)
--      - sessao engajada = parametro session_engaged = '1' em algum evento
-- ============================================================================
DECLARE KEY_EVENTS ARRAY<STRING> DEFAULT ['purchase', 'generate_lead', 'sign_up'];

WITH ev AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')     AS session_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number') AS session_number,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'session_engaged')   AS session_engaged,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')     AS page_location,
    event_name,
    event_timestamp,
    device.operating_system                                                    AS operating_system,
    geo.city                                                                   AS city,
    session_traffic_source_last_click.cross_channel_campaign.default_channel_group AS channel,
    COALESCE(session_traffic_source_last_click.manual_campaign.source,
             session_traffic_source_last_click.cross_channel_campaign.source)  AS source,
    COALESCE(session_traffic_source_last_click.manual_campaign.medium,
             session_traffic_source_last_click.cross_channel_campaign.medium)  AS medium,
    COALESCE(session_traffic_source_last_click.manual_campaign.campaign_id,
             session_traffic_source_last_click.cross_channel_campaign.campaign_id) AS campaign_id,
    session_traffic_source_last_click.manual_campaign.content                   AS ad_content
  FROM `SEU_PROJETO.analytics_XXXXXXXXX.events_*`
  WHERE _TABLE_SUFFIX NOT LIKE 'intraday%'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY))
),

sess AS (                                        -- uma linha por sessao
  SELECT
    user_pseudo_id, session_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)))                               AS date,
    ANY_VALUE(channel)         AS channel,
    ANY_VALUE(source)          AS source,
    ANY_VALUE(medium)          AS medium,
    ANY_VALUE(ad_content)      AS ad_content,
    ANY_VALUE(campaign_id)     AS campaign_id,
    ANY_VALUE(operating_system) AS operating_system,
    ANY_VALUE(city)            AS city,
    -- landing page: page_location do primeiro page_view da sessao
    ARRAY_AGG(
      IF(event_name = 'page_view', page_location, NULL) IGNORE NULLS
      ORDER BY event_timestamp LIMIT 1
    )[SAFE_OFFSET(0)]                                                          AS landing_page,
    MAX(session_number = 1)                                                    AS is_new_user,
    MAX(session_engaged = '1')                                                 AS is_engaged,
    COUNTIF(event_name = 'page_view')                                          AS page_views,
    COUNT(*)                                                                   AS events,
    COUNTIF(event_name IN UNNEST(KEY_EVENTS))                                  AS key_events,
    (MAX(event_timestamp) - MIN(event_timestamp)) / 1e6                        AS duration_seconds
  FROM ev
  WHERE session_id IS NOT NULL
  GROUP BY user_pseudo_id, session_id
)

SELECT
  FORMAT_DATE('%Y%m%d', date)                        AS date,
  channel                                            AS sessionDefaultChannelGroup,
  source                                             AS sessionSource,
  medium                                             AS sessionMedium,
  IFNULL(ad_content, '(not set)')                    AS sessionManualAdContent,
  IFNULL(campaign_id, '(not set)')                   AS sessionCampaignId,
  operating_system                                   AS operatingSystem,
  city                                               AS city,
  landing_page                                       AS landingPagePlusQueryString,
  COUNT(*)                                           AS sessions,
  COUNT(DISTINCT user_pseudo_id)                     AS totalUsers,
  COUNT(DISTINCT IF(is_new_user, user_pseudo_id, NULL)) AS newUsers,
  COUNTIF(is_engaged)                                AS engagedSessions,
  SAFE_DIVIDE(COUNTIF(is_engaged), COUNT(*))         AS engagementRate,
  SUM(page_views)                                    AS screenPageViews,
  SAFE_DIVIDE(SUM(events), COUNT(*))                 AS eventsPerSession,
  SUM(key_events)                                    AS keyEvents,
  SAFE_DIVIDE(COUNTIF(key_events > 0), COUNT(*))     AS sessionKeyEventRate,
  AVG(duration_seconds)                              AS averageSessionDuration
FROM sess
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
ORDER BY sessions DESC;
