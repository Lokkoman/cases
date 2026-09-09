# Caminho 2 — Export nativo GA4 → BigQuery

O link nativo do GA4 pro BigQuery. O Google escreve o **evento cru** direto num
dataset seu, sem você programar nada. É o grão mais fino possível — a base pra
qualquer modelagem séria (sessão, atribuição, funil) e a origem da tabela
`dados_tratados` que os caminhos 4 e 5 tentam reproduzir pela Data API.

Este caminho não tem código: é configuração de console. O `exemplo.sql` mostra
só como o dado se parece.

## Arquivos

| Arquivo | O que é |
|---|---|
| `exemplo.sql` | duas consultas de leitura do cru: eventos por dia/nome e como pegar um parâmetro de dentro de `event_params` com `UNNEST` |

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

## Custo

Só armazenamento no BigQuery. Streaming tem um custo pequeno de inserção; a
exportação diária é grátis.

## Serve para

Quando você quer o dado no grão do evento pra modelar do seu jeito. Nada do
Google vem "pronto" aqui — é matéria-prima. Consultar exige `UNNEST` e
`_TABLE_SUFFIX` pra filtrar as tabelas diárias.
