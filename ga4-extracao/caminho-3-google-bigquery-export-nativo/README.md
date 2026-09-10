# Caminho 3 — Export nativo GA4 → BigQuery

O link nativo do GA4 pro BigQuery. O Google escreve o **evento cru** direto num
dataset seu, sem você programar nada. É o grão mais fino possível: um registro
por evento, com todo parâmetro em toda linha.

A extração aqui é **uma consulta só** sobre `events_*`, sem juntar tabela com
tabela. Cada `STRUCT` aninhado abre numa coluna, cada chave de `event_params`
abre numa coluna `param_<chave>`, e cada `event_name` vira um indicador
`evento_<nome>` (1 na linha daquele evento). Nada é agregado nem sessionizado,
então nenhum número é atribuído ao balde errado. Sessão, atribuição e funil se
montam **depois**, a partir dessa base, somando os indicadores no grão que
quiser.

Este caminho não tem código: é configuração de console mais um `.sql`.

## Arquivos

| Arquivo | O que é |
|---|---|
| `exemplo.sql` | como o evento cru se parece: `UNNEST` em `event_params`, eventos por dia/nome |
| `eventos.sql` | `CREATE OR REPLACE VIEW dados_tratados.eventos` — o `events_*` vetorizado: uma linha por evento, uma coluna por valor, nenhum STRUCT ou array numa célula. **Todo** bloco aninhado do schema do export (`device`, `geo`, `privacy_info`, `user_ltv`, `app_info`, `collected_traffic_source`, `traffic_source`, as 6 sub-structs de `session_traffic_source_last_click`, `ecommerce`, `publisher`) abre em `<caminho>_<campo>` e fica `NULL` onde a propriedade não usa; cada chave de `event_params` em `param_<chave>`; cada `event_name` num indicador `evento_<nome>`. Aqui isso dá ~179 colunas. Primeira coluna `registro_origem` = `analytics_<id>.events_<AAAAMMDD>`. |

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
5. Rodar o `eventos.sql` (ajustando o `_TABLE_SUFFIX` e a lista de
   `evento_<nome>` pra sua propriedade). Sai a view `dados_tratados.eventos`.

## O que sai do `events_*`

Um registro por evento, no schema padrão do GA4 (em inglês):

| Campo | Conteúdo |
|---|---|
| `event_name`, `event_date`, `event_timestamp` | qual evento, quando |
| `event_params` | array aninhado de `key` / `value` — os parâmetros do evento (`page_location`, `ga_session_id`, etc.). Pega com `UNNEST` |
| `user_pseudo_id` | identificador do dispositivo |
| `device`, `geo` | blocos de dispositivo e geografia |
| `traffic_source`, `collected_traffic_source`, `session_traffic_source_last_click` | atribuição em três recortes |
| `ecommerce`, `items` | receita e itens |

## O que o `eventos.sql` faz

Achata tudo isso numa view sem mudar o grão:

1. **Todo STRUCT vira coluna**: `device.web_info.browser` →
   `device_web_info_browser`, `geo.city` → `geo_city`,
   `session_traffic_source_last_click.google_ads_campaign.campaign_id` →
   `session_traffic_source_last_click_google_ads_campaign_campaign_id`. Os blocos
   que a propriedade não usa (e-commerce, Google Ads, SA360/CM360/DV360, app)
   viram colunas `NULL`, não somem.
2. **`event_params` vira `param_<chave>`**: uma coluna por chave distinta da
   propriedade (`SELECT DISTINCT key FROM …, UNNEST(event_params)`), tipada pelo
   slot de `value` que ela usa.
3. **`event_name` vira indicador**: `evento_page_view`, `evento_scroll`,
   `evento_session_start`… com `1` na linha daquele evento e `0` nas outras.
   Somar esses indicadores dá a contagem de cada evento em qualquer recorte, sem
   pivô e sem join.
4. **`registro_origem`**: a tabela diária de onde a linha veio.

`user_properties` seria `user_prop_<chave>` pelo mesmo critério; nesta
propriedade não há nenhuma, então não gera coluna.

`items` (linha de produto do e-commerce) muda o grão, então fica de fora da
view principal — abra num `CROSS JOIN UNNEST(items)` à parte quando precisar.

## Do evento pra sessão

`dados_tratados.eventos` é a matéria-prima. Uma tabela por sessão sai daí com um
`GROUP BY user_pseudo_id, param_ga_session_id` somando os `evento_<nome>` e os
`param_*` — cada número vem de eventos que **de fato** aconteciam naquela sessão,
sem `ANY_VALUE` chutando atributo nem join de agregado. Essa modelagem é o passo
seguinte e fica fora do escopo deste case (que para na extração).

## Custo

Só armazenamento no BigQuery. Streaming tem um custo pequeno de inserção; a
exportação diária é grátis. A view relê `events_*` a cada consulta; pra um BI
que consulta muito, materialize: `CREATE TABLE … AS SELECT * FROM
dados_tratados.eventos` + uma consulta programada diária.

## Serve para

Quando você quer o dado no grão do evento pra modelar do seu jeito, sem herdar
nenhuma decisão de modelagem do Google. É a base com mais informação entre os 6
caminhos. Consultar exige `UNNEST` e `_TABLE_SUFFIX` pra filtrar as tabelas
diárias.
