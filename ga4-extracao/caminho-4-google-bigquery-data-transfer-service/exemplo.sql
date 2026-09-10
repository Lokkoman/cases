-- Caminho 4: leitura das tabelas de relatório criadas pelo Data Transfer
-- Service (conector "Google Analytics 4").
--
-- Consulte sempre a VIEW  ga4_<Relatorio>_<ID>  (deduplicada),
-- nunca a tabela      p_ga4_<Relatorio>_<ID>  (tem cargas repetidas
-- por causa da janela de atualização de 7 dias).
--
-- As colunas vêm em camelCase e a data de partição é `_DATA_DATE`.
-- Troque:  SEU_PROJETO  SEU_DATASET  XXXXXXXXX (id da propriedade)
--
-- Cada consulta lê UMA tabela. Não junte duas por _DATA_DATE: colar
-- TrafficAcquisition com PagesAndScreens pela data repete a métrica de um
-- recorte em cada valor do outro e enviesa a leitura. Pra cruzar dimensões
-- numa linha só, é o evento cru do caminho 3.

-- 1) Aquisição de tráfego por canal, últimos 28 dias.
--    (Traffic Acquisition é session-scoped: não tem métrica de usuários.)
SELECT
  _DATA_DATE                      AS dia,
  sessionDefaultChannelGroup      AS canal,
  SUM(sessions)                   AS sessoes,
  SUM(engagedSessions)            AS sessoes_engajadas,
  SUM(keyEvents)                  AS eventos_chave
FROM `SEU_PROJETO.SEU_DATASET.ga4_TrafficAcquisition_XXXXXXXXX`
WHERE _DATA_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
GROUP BY dia, canal
ORDER BY dia DESC, sessoes DESC;


-- 2) Páginas mais vistas, últimos 7 dias.
SELECT
  _DATA_DATE                   AS dia,
  pagePathPlusQueryString      AS pagina,
  SUM(screenPageViews)         AS visualizacoes,
  SUM(activeUsers)             AS usuarios_ativos
FROM `SEU_PROJETO.SEU_DATASET.ga4_PagesAndScreens_XXXXXXXXX`
WHERE _DATA_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY dia, pagina
ORDER BY dia DESC, visualizacoes DESC;
