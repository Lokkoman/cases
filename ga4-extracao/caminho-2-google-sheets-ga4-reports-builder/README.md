# Caminho 2 — Google Sheets + GA4 Reports Builder

O add-on **"GA4 Reports Builder for Google Analytics"** (oficial, por Google) roda
a **GA4 Data API** por baixo — a mesma dos caminhos 1, 5 e 6 — só que o
"pipeline" é a planilha e o agendador é do Google. Zero infra, zero código, zero
service account.

Este caminho não tem código: é configuração no Sheets. O `report-config.tsv`
mostra os valores que vão na aba de configuração do add-on.

## Como montar

1. No Sheets: **Extensões → Instalar complementos**, buscar
   **"GA4 Reports Builder for Google Analytics"** e instalar. Autorizar com a
   conta Google que tem acesso à propriedade GA4 (papel **Leitor** basta — nada
   de chave JSON).
2. **Extensões → GA4 Reports Builder → Create new report**. O add-on cria a aba
   `Report Configuration` com uma coluna por relatório.
3. Preencher a coluna com os valores do `report-config.tsv` (nomes de métrica e
   dimensão são os nomes exatos da Data API).
4. **Extensões → GA4 Reports Builder → Run reports**. Cada relatório escreve numa
   aba própria: um cabeçalho (property, período, quota gasta) e a tabela abaixo.
5. **Schedule reports** pra rodar diário — roda no lado do Google mesmo com a
   planilha fechada.

## O que sai

Uma aba `fato_sessoes` com **uma linha por combinação das 9 dimensões de mídia**,
10 métricas. É o **teto de uma chamada `runReport`** (9 dims / 10 métricas), e o
**mesmo schema** dos caminhos 5 (Databricks) e 6 (Fabric).

| Dimensões (9) | Métricas (10) |
|---|---|
| `date` | `sessions` |
| `sessionDefaultChannelGroup` | `totalUsers` |
| `sessionSource` | `newUsers` |
| `sessionMedium` | `engagedSessions` |
| `sessionManualAdContent` (utm_content) | `engagementRate` |
| `sessionCampaignId` (utm_id) | `screenPageViews` |
| `operatingSystem` | `eventsPerSession` |
| `city` | `keyEvents` |
| `landingPagePlusQueryString` | `sessionKeyEventRate` |
| | `averageSessionDuration` |

`date` volta como texto `AAAAMMDD`. `sessionManualAdContent` / `sessionCampaignId`
vêm `(not set)` em tráfego sem UTM de campanha. As taxas (`engagementRate`,
`sessionKeyEventRate`) aparecem formatadas com o separador de milhar do locale;
o valor por baixo está certo.

## Custo

Grátis. Sujeito às cotas da Data API (tokens por propriedade por hora/dia); o
estouro aparece no cabeçalho do relatório. Sem armazenamento além da planilha.

## Serve para

Relatório de mídia recorrente pra um analista, protótipo rápido, alimentar um
Looker Studio ou uma consulta `IMPORTRANGE` sem subir infra. Não serve pra
histórico longo, junção de muitas fontes ou volume — aí é BigQuery
([caminho 3](../caminho-3-google-bigquery-export-nativo/)) ou os pipelines em
Spark (caminhos 5 e 6).

## Arquivos

| Arquivo | O que é |
|---|---|
| `report-config.tsv` | os valores da aba `Report Configuration` do add-on (nome, property, período, métricas, dimensões, limite) |
