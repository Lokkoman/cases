-- Caminho 3: leitura das tabelas de relatório criadas pelo Data Transfer
-- Service (conector "Google Analytics 4").
--
-- Consulte sempre a VIEW  ga4_<Relatorio>_<ID>  (deduplicada),
-- nunca a tabela      p_ga4_<Relatorio>_<ID>  (tem cargas repetidas
-- por causa da janela de atualização de 7 dias).
--
-- Troque:
--   SEU_PROJETO  SEU_DATASET  XXXXXXXXX (id da propriedade)
-- Confira os nomes das colunas no schema da tabela: variam por relatório.

-- 1) Aquisição de tráfego por canal, últimos 28 dias.
SELECT
  date                            AS dia,
  session_default_channel_group   AS canal,
  SUM(sessions)                   AS sessoes,
  SUM(engaged_sessions)           AS sessoes_engajadas,
  SUM(total_users)                AS usuarios
FROM `SEU_PROJETO.SEU_DATASET.ga4_TrafficAcquisition_XXXXXXXXX`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
GROUP BY dia, canal
ORDER BY dia DESC, sessoes DESC;


-- 2) Páginas mais vistas, últimos 7 dias.
SELECT
  date                     AS dia,
  page_path,
  SUM(screen_page_views)   AS visualizacoes,
  SUM(total_users)         AS usuarios
FROM `SEU_PROJETO.SEU_DATASET.ga4_PagesAndScreens_XXXXXXXXX`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY dia, page_path
ORDER BY dia DESC, visualizacoes DESC;
