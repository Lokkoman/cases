# Ferramentas e conceitos

Glossário do que os cases usam. Marca de onde cada termo aparece:

`[G]` GitHub Actions · `[SH]` Google Sheets · `[BQ]` BigQuery · `[DBX]` Azure Databricks (caminho 5) · `[FAB]` Fabric + Airflow (caminho 6)

---

## APIs de origem

| Termo | O que é |
|---|---|
| **GA4 Data API** `[G] [SH] [DBX] [FAB]` | API de leitura oficial do Google Analytics 4 (`analyticsdata.googleapis.com`). Você faz um `runReport` pedindo dimensões e métricas e recebe JSON. Limite rígido: **9 dimensões e 10 métricas por chamada** — por isso a tabela de mídia dos cases tem exatamente 9 dims. |
| **GA4 Reports Builder (add-on do Sheets)** `[SH]` | Complemento oficial do Google pro Google Sheets. Roda a Data API por baixo; a config vai numa aba `Report Configuration` e o resultado numa aba de saída. `Schedule reports` roda no lado do Google, sem infra. |
| **Export nativo GA4 → BigQuery** `[BQ]` | Link no Admin do GA4 que faz o Google gravar o **evento cru** (`events_*`) num dataset do BigQuery. Nenhum código. É a matéria-prima mais completa que existe. |
| **Data Transfer Service** `[BQ]` | Conector "Google Analytics 4" no BigQuery que puxa as **tabelas de relatório prontas** do GA4 (Aquisição de tráfego, Páginas, Eventos…), a cada 24h. Cada relatório é um agregado de tema único. |
| **Service account (Google)** `[G] [DBX] [FAB]` | Identidade de máquina do Google Cloud. Tem uma chave JSON que assina um JWT, trocado por um access token pra chamar a Data API. A chave nunca vai pro código — entra por secret. |

---

## Modelo de dados

| Termo | O que é |
|---|---|
| **`fato_sessoes` (tabela de mídia)** `[SH] [DBX] [FAB]` | Uma linha por combinação das 9 dimensões mais úteis pra mídia (`date`, canal, origem, mídia, `sessionManualAdContent`, `sessionCampaignId`, `operatingSystem`, `city`, `landingPagePlusQueryString`) + 10 métricas. É o teto de uma chamada `runReport`. Os caminhos 2, 5 e 6 pegam essa tabela pronta; no caminho 3 ela é um `GROUP BY` sobre o evento vetorizado. |
| **Evento vetorizado (`dados_tratados.eventos`)** `[BQ]` | A saída do caminho 3: o `events_*` achatado numa view, um registro por evento, sem agregar. Cada `STRUCT` vira `<caminho>_<campo>`, cada chave de `event_params` vira `param_<chave>`, cada `event_name` vira um indicador `evento_<nome>` (1 na linha daquele evento). Somar os indicadores num `GROUP BY` dá qualquer recorte sem pivô e sem join. |
| **Chave de atribuição** `[SH] [DBX] [FAB] [BQ]` | As 5 primeiras dimensões da tabela: `date, sessionDefaultChannelGroup, sessionSource, sessionMedium, sessionCampaignName` (ou `sessionCampaignId`). É o recorte de "de onde veio a sessão". Na sessionização por SQL (caminho 3) sai do `session_traffic_source_last_click`. |
| **Grão (granularidade)** `[todos]` | O nível de detalhe de uma linha. O `fato_sessoes` é grão de 9 dimensões (uma linha por combinação). O evento cru é grão de evento — o mais fino possível, dá pra `GROUP BY` qualquer coisa. Quanto mais fino o grão, mais linhas e mais detalhe. |
| **Camada / medallion (bronze, prata, ouro)** `[DBX] [FAB]` | Convenção de lakehouse: bronze = cru, prata = tratado/cruzado, ouro = recortes de negócio. **Estes cases param na extração** — o `fato_sessoes` já é uma tabela de consumo, sem camadas por cima. A modelagem em camadas seria o passo seguinte, igual pra qualquer fonte. |
| **Delta Lake** `[DBX] [FAB]` | Formato de tabela sobre Parquet com transação ACID, `MERGE`, time travel e evolução de schema. É o formato do `fato_sessoes` nos dois lakehouses. `overwriteSchema` deixa reescrever a tabela quando as colunas mudam. |

---

## Compute

| Termo | O que é |
|---|---|
| **Cluster Spark** `[DBX] [FAB]` | Conjunto de máquinas que rodam o job como um sistema só: 1 **driver** (coordena, roda o Python — a chamada à GA4 API acontece aqui) + N **executores** (fazem o trabalho em paralelo — a gravação Delta é distribuída entre eles). No fim, o cluster é destruído. |
| **PySpark** `[DBX] [FAB]` | API Python do Apache Spark. Aqui só `spark.createDataFrame(...)` + `.write...saveAsTable(...)`: transforma a resposta JSON da API numa tabela Delta. |
| **Serverless SQL Warehouse** `[DBX]` | Motor SQL gerenciado do Databricks pra consulta ad-hoc. Sobe em segundos, cobra por uso, desliga sozinho. Usado pra validar a `fato_sessoes` e ligar num Power BI. |
| **Capacidade / SKU (F2, F64, FTL4)** `[FAB]` | No Fabric o compute vem de uma "capacidade" com um tamanho (SKU). A avaliação gratuita é uma FTL4, pequena — cabe ~um cluster por vez. Rodar dois ao mesmo tempo dá `430 TooManyRequestsForCapacity`. |
| **Sessão Livy** `[FAB]` | A sessão Spark que o Fabric abre pra rodar um notebook agendado. Se a capacidade está cheia, ela nem sobe. |
| **Environment (Fabric)** `[FAB]` | Item do Fabric que empacota bibliotecas e configuração de Spark. O cluster já sobe com elas. Serve pra ter `google-analytics-data` num notebook agendado, já que `%pip install` é bloqueado fora do modo interativo. |

---

## Governança e catálogo

| Termo | O que é |
|---|---|
| **Unity Catalog** `[DBX]` | Camada de governança do Databricks: catálogo → schema → tabela, com permissões e linhagem. A tabela fica em `raulpavao.ga4.fato_sessoes`. |
| **Lakehouse / OneLake** `[FAB]` | Lakehouse é o item do Fabric que junta armazenamento de arquivos + tabelas Delta. OneLake é o "disco" único do tenant onde tudo isso mora. |
| **SQL analytics endpoint** `[FAB]` | Endpoint T-SQL somente-leitura criado automático sobre o Lakehouse. Deixa consultar as tabelas Delta com SQL e ligar num Power BI. |

---

## Segredos e identidade

| Termo | O que é |
|---|---|
| **Secret scope (Databricks)** `[DBX]` | Cofre de segredos do workspace Databricks. A chave da service account entra por `dbutils.secrets.get("ga4", "service-account-key")`. |
| **Azure Key Vault** `[FAB]` | Cofre de segredos do Azure. O notebook do Fabric lê a chave por `notebookutils.credentials.getSecret(vaultUri, nome)`. A identidade que roda o notebook precisa de permissão `get`/`list` no cofre. |
| **Service principal / App registration (Entra ID)** `[FAB]` | Identidade de máquina do Microsoft Entra ID. Tem `client_id` + `client_secret`. O Airflow usa isso pra se autenticar na API do Fabric sem usuário humano. |
| **OAuth2 client credentials** `[FAB]` | Fluxo de autenticação máquina-a-máquina: manda `client_id` + `client_secret` + `scope` no endpoint de token do Entra ID e recebe um `Bearer token` de curta duração. O Airflow refaz isso a cada execução. |

---

## Orquestração

| Termo | O que é |
|---|---|
| **REST / API REST** `[FAB]` | Estilo de API sobre HTTP: recursos por URL, verbos (`GET` lê, `POST` cria/dispara, `PATCH`/`PUT` atualiza, `DELETE` remove), resposta em JSON com status code (`2xx` ok, `401` sem token, `403` sem permissão, `404` não existe, `429`/`430` limite). O padrão assíncrono: `POST` volta `202` + header `Location`, você faz `GET` nesse `Location` até virar `Completed`/`Failed`. Detalhe no README do caminho 6. |
| **Airflow** `[FAB]` | Orquestrador de workflows. Não move dado: agenda, dispara e lê status. Roda local via Docker neste case. |
| **DAG** `[FAB]` | O grafo de tarefas do Airflow (arquivo Python). Aqui tem uma tarefa só: disparar o notebook e esperar. |
| **LocalExecutor** `[FAB]` | Modo do Airflow que roda as tarefas em processos locais (sem fila Celery). Suficiente pra um DAG pequeno. |
| **MSFabricRunJobOperator / deferrable** `[FAB]` | Operador do provider oficial do Fabric pro Airflow. Faz o `POST` que dispara o notebook e o `GET` em loop que acompanha. Em modo `deferrable` ele libera o worker entre as checagens. |
| **Job Scheduler (Fabric)** `[FAB]` | O serviço do Fabric que recebe o `POST .../jobs/instances?jobType=RunNotebook` e executa o item. |
| **GitHub Actions** `[G]` | CI do GitHub. Roda o coletor Node a cada 3h e commita o JSON se mudou. |

---

## O limite estrutural entre os caminhos

| | Teto de completude |
|---|---|
| **Evento cru (BQ export nativo)** | ilimitado: todo parâmetro está em toda linha, dá pra `GROUP BY` qualquer combinação. A view `dados_tratados.eventos` abre isso em colunas numa consulta só; o `fato_sessoes`, ou qualquer recorte, é um `GROUP BY` por cima, sem teto de dimensão. |
| **GA4 Data API** (GitHub Actions, Sheets, Databricks, Fabric) | 9 dimensões / 10 métricas por chamada. O `fato_sessoes` usa exatamente esse teto, numa única `runReport`. Pra cobrir mais numa tabela só, tem que ir pro evento cru: rodar duas chamadas e juntar espalha a métrica de um recorte pelo outro. |
| **Tabelas de relatório (Data Transfer Service)** | fixo no que o Google entrega, cada relatório num tema. Juntar dois pela data cola números de sessões diferentes na mesma linha e enviesa. Não monta o `fato_sessoes`. |
