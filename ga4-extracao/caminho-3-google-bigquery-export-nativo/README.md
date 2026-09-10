# Caminho 3 — Export nativo GA4 → BigQuery

O link nativo do GA4 pro BigQuery. O Google escreve o **evento cru** direto num
dataset seu, sem você programar nada. É o grão mais fino possível — a base pra
qualquer modelagem (sessão, atribuição, funil).

Este caminho não tem código: é configuração de console. Os `.sql` mostram o
formato do dado e montam a tabela de mídia por SQL — aqui **nenhum limite de
dimensão se aplica**, todo campo está em toda linha.

## Arquivos

| Arquivo | O que é |
|---|---|
| `exemplo.sql` | como o evento cru se parece: `UNNEST` em `event_params`, eventos por dia/nome |
| `fato_sessoes.sql` | a base **sem teto**, montada por SQL: `CREATE OR REPLACE VIEW dados_tratados.fato_sessoes` — ~50 dimensões (atribuição last-click completa + Google Ads + primeiro toque, device e browser com versão, geo até `metro`, landing/exit page + referrer, hora local) e ~50 métricas (engajamento, funil completo, eventos padrão, e-commerce nível transação). Cada linha traz `_source_dataset` / `_source_table` / `_extracted_at`. |

## Como montar

1. Projeto no Google Cloud com **faturamento** e a **API do BigQuery** ativa.
2. No Admin do GA4: **Administração → Vinculações de produtos → Vinculações do
   BigQuery → Vincular**.
3. Escolher o projeto, a **região** do dataset e o **tipo de exportação**:
   - **streaming** — segundos de atraso, custo pequeno de inserção
   - **diária** — a tabela do dia fecha depois que o dia termina no fuso da
     propriedade, de graça
   - ou as duas
4. Em algumas horas aparece o dataset `analytics_<ID_DA_PROPRIEDADE>` com
   `events_YYYYMMDD` (dia fechado) e `events_intraday_YYYYMMDD` (dia corrente).

## O que sai

Um registro por evento, no schema padrão do GA4 (em inglês):

| Campo | Conteúdo |
|---|---|
| `event_name`, `event_date`, `event_timestamp` | qual evento, quando |
| `event_params` | array aninhado de `key` / `value` — os parâmetros do evento (page_location, ga_session_id, etc.). Pega com `UNNEST` |
| `user_pseudo_id` | identificador do dispositivo |
| `device`, `geo` | blocos de dispositivo e geografia |
| `traffic_source`, `collected_traffic_source`, `session_traffic_source_last_click` | atribuição em três recortes |
| `ecommerce`, `items` | receita e itens |

## Do evento cru pro `fato_sessoes`

Os caminhos 2, 5 e 6 pegam o `fato_sessoes` pronto da Data API — **9 dimensões**,
o teto de uma chamada. Aqui você **constrói** com SQL, e a única fronteira é o
schema do evento cru. Passos (o `fato_sessoes.sql` faz tudo):

1. **Sessioniza** — agrupa por `user_pseudo_id` + `ga_session_id`.
2. **Last click** — `session_traffic_source_last_click` (`manual_campaign.*`,
   `cross_channel_campaign.*`, `google_ads_campaign.*`).
3. **Primeiro toque** — `traffic_source` (user-scoped, constante).
4. **Device / geo** — constantes na sessão; `ANY_VALUE`.
5. **Páginas** — `page_location` do primeiro `page_view` (landing), do último
   (exit), `page_referrer` da entrada.
6. **Métricas** — `sessions` = 1; engajamento de `session_engaged` /
   `engagement_time_msec`; funil e e-commerce por `COUNTIF(event_name = '...')`
   e `SUM(ecommerce.*)`.

Resultado: `dados_tratados.fato_sessoes` — ~50 dimensões, ~50 métricas numa
tabela só. É a resposta pra "qual base junta mais informação".

É uma **view** (sem armazenamento, sempre fresca). Pra alimentar um BI que
consulta muito, materialize: `CREATE TABLE ... AS SELECT * FROM
dados_tratados.fato_sessoes` + uma consulta programada diária.

## Custo

Só armazenamento no BigQuery. Streaming tem um custo pequeno de inserção; a
exportação diária é grátis.

## Serve para

Quando você quer o dado no grão do evento pra modelar do seu jeito, ou uma
tabela de mídia com **mais de 9 dimensões**. Nada do Google vem "pronto" aqui —
é matéria-prima. Consultar exige `UNNEST` e `_TABLE_SUFFIX` pra filtrar as
tabelas diárias.
