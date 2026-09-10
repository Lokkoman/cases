# Caminho 3 — Export nativo GA4 → BigQuery

O link nativo do GA4 pro BigQuery. O Google escreve o **evento cru** direto num
dataset seu, sem você programar nada. É o grão mais fino possível — a base pra
qualquer modelagem (sessão, atribuição, funil).

Este caminho não tem código: é configuração de console. O `exemplo.sql` mostra o
formato do dado e monta o `fato_sessoes` (o mesmo dos caminhos 2, 5 e 6) por
SQL, já que aqui **nenhum limite de dimensão se aplica** — todo campo está em
toda linha.

## Arquivos

| Arquivo | O que é |
|---|---|
| `exemplo.sql` | leitura do cru (`UNNEST` em `event_params`) + a query de sessionização que reproduz o `fato_sessoes` |

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

Os caminhos 2, 5 e 6 pegam o `fato_sessoes` pronto da Data API (limitado a 9
dimensões). Aqui você **constrói** o mesmo com SQL, e sem teto de dimensão:

1. **Sessioniza** — agrupa por `user_pseudo_id` + `ga_session_id` (parâmetro de
   `event_params`).
2. **Last click** — pega `session_traffic_source_last_click.manual_campaign.*` e
   `.cross_channel_campaign.*` (canal, origem, mídia, campanha, `campaign_id`,
   `manual_content`).
3. **Device / geo** — são constantes na sessão; pega de qualquer evento dela.
4. **Landing page** — o `page_location` do primeiro `page_view` da sessão.
5. **Métricas** — `sessions` = 1 por sessão; `engagedSessions` de
   `session_engaged`; `screenPageViews` = contagem de `page_view`; `keyEvents` de
   `is_key_event`; etc.

A query completa está no `exemplo.sql`.

## Custo

Só armazenamento no BigQuery. Streaming tem um custo pequeno de inserção; a
exportação diária é grátis.

## Serve para

Quando você quer o dado no grão do evento pra modelar do seu jeito, ou uma
tabela de mídia com **mais de 9 dimensões**. Nada do Google vem "pronto" aqui —
é matéria-prima. Consultar exige `UNNEST` e `_TABLE_SUFFIX` pra filtrar as
tabelas diárias.
