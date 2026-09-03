-- Caminho 2: leitura do evento cru do export nativo GA4 -> BigQuery.
-- Sem modelagem, só para mostrar o formato do dado.
--
-- Troque:
--   SEU_PROJETO         pelo id do projeto GCP
--   analytics_XXXXXXXXX pelo dataset do export (analytics_<ID_DA_PROPRIEDADE>)

-- 1) Eventos por dia e por nome, últimos 7 dias.
SELECT
  PARSE_DATE('%Y%m%d', event_date)        AS dia,
  event_name,
  COUNT(*)                                AS eventos,
  COUNT(DISTINCT user_pseudo_id)          AS usuarios
FROM `SEU_PROJETO.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX NOT LIKE 'intraday%'
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
GROUP BY dia, event_name
ORDER BY dia DESC, eventos DESC;


-- 2) Como pegar um parâmetro de dentro de event_params (array aninhado).
--    Aqui: page_location e ga_session_id do evento page_view de ontem.
SELECT
  TIMESTAMP_MICROS(event_timestamp)                                             AS quando,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS pagina,
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS sessao_id
FROM `SEU_PROJETO.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'page_view'
ORDER BY quando
LIMIT 50;
