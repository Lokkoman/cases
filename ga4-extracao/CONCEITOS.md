# Ferramentas e conceitos

Glossário do que os cases usam. Marca de onde cada termo aparece:

`[G]` git · `[BQ]` BigQuery · `[DBX]` Azure / Databricks · `[FAB]` Fabric + Airflow

---

## APIs de origem

| Termo | O que é |
|---|---|
| **GA4 Data API** `[G] [DBX] [FAB]` | API de leitura oficial do Google Analytics 4 (`analyticsdata.googleapis.com`). Você faz um `runReport` pedindo dimensões e métricas e recebe JSON. Limite rígido: **9 dimensões e 10 métricas por chamada** — por isso os cases dividem a extração em várias chamadas com uma chave comum. |
| **Export nativo GA4 → BigQuery** `[BQ]` | Link no Admin do GA4 que faz o Google gravar o **evento cru** (`events_*`) num dataset do BigQuery. Nenhum código. É a matéria-prima mais completa que existe. |
| **Data Transfer Service** `[BQ]` | Conector "Google Analytics 4" no BigQuery que puxa as **tabelas de relatório prontas** do GA4 (Aquisição de tráfego, Páginas, Eventos…), a cada 24h. |
| **Service account (Google)** `[G] [DBX] [FAB]` | Identidade de máquina do Google Cloud. Tem uma chave JSON que assina um JWT, trocado por um access token pra chamar a Data API. A chave nunca vai pro código — entra por secret. |

---

## Padrões de modelagem

| Termo | O que é |
|---|---|
| **Camada / medallion (bronze, prata, ouro)** `[DBX] [FAB]` | Bronze = dado quase cru, um relatório por tabela. Prata = agregado, limpo e cruzado numa tabela larga pronta pra consumo. Ouro = recortes de negócio. Bronze e prata montados à mão só aparecem nos caminhos 4 e 5 (o Databricks tem prata; o Fabric, só bronze). Os outros pousam o dado noutro formato: o 2 é evento cru (antes de qualquer camada), o 3 já vem agregado pelo Google (não é bronze), o 1 é um snapshot JSON num arquivo. |
| **Chave de atribuição** `[DBX] [FAB]` | As 5 dimensões que toda tabela bronze carrega nas primeiras posições: `date, sessionDefaultChannelGroup, sessionSource, sessionMedium, sessionCampaignName`. É a "espinha" que deixa agregar cada bronze e juntar tudo na prata sem duplicar. |
| **Grão (granularidade)** `[todos]` | O nível de detalhe de uma linha. A tratada do BigQuery é grão de 16 dimensões (uma linha por combinação). A prata do Databricks é grão de 5 (a chave de atribuição). Quanto mais fino o grão, mais linhas e mais detalhe. |
| **Pivô de evento (linha → coluna)** `[DBX] [FAB]` | A Data API devolve `eventName` como dimensão (uma linha por tipo de evento). Na prata isso vira uma coluna por evento (`rolagens`, `cliques_saida`, `downloads`…), cada uma com a soma de `eventCount`. Equivale ao `COUNTIF(event_name = '...')` do SQL do BigQuery. |
| **Delta Lake** `[DBX] [FAB]` | Formato de tabela sobre Parquet com transação ACID, `MERGE`, time travel e evolução de schema. É o formato das tabelas nos dois lakehouses. `overwriteSchema` deixa reescrever a tabela quando as colunas mudam. |

---

## Compute

| Termo | O que é |
|---|---|
| **Cluster Spark** `[DBX] [FAB]` | Conjunto de máquinas que rodam o job como um sistema só: 1 **driver** (coordena, roda o Python — as chamadas à GA4 API acontecem aqui) + N **executores** (fazem o trabalho em paralelo — a gravação Delta é distribuída entre eles). No fim, o cluster é destruído. |
| **PySpark** `[DBX] [FAB]` | API Python do Apache Spark. `spark.createDataFrame(...)`, `.write...saveAsTable(...)`, `groupBy().agg()`, `pivot()`. É o que transforma o JSON da API em tabela Delta. |
| **Serverless SQL Warehouse** `[DBX]` | Motor SQL gerenciado do Databricks pra consulta ad-hoc. Sobe em segundos, cobra por uso, desliga sozinho. Usado pra validar a tabela prata. |
| **Capacidade / SKU (F2, F64, FTL4)** `[FAB]` | No Fabric o compute vem de uma "capacidade" com um tamanho (SKU). A avaliação gratuita é uma FTL4, pequena — cabe ~um cluster por vez. Rodar dois ao mesmo tempo dá `430 TooManyRequestsForCapacity`. |
| **Sessão Livy** `[FAB]` | A sessão Spark que o Fabric abre pra rodar um notebook agendado. Se a capacidade está cheia, ela nem sobe. |
| **Environment (Fabric)** `[FAB]` | Item do Fabric que empacota bibliotecas e configuração de Spark. O cluster já sobe com elas. Serve pra ter `google-analytics-data` num notebook agendado, já que `%pip install` é bloqueado fora do modo interativo. |

---

## Governança e catálogo

| Termo | O que é |
|---|---|
| **Unity Catalog** `[DBX]` | Camada de governança do Databricks: catálogo → schema → tabela, com permissões e linhagem. As tabelas ficam em `raulpavao.bronze.*` e `raulpavao.silver.*`. |
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
| **REST / API REST** `[FAB]` | Estilo de API sobre HTTP: recursos por URL, verbos (`GET` lê, `POST` cria/dispara, `PATCH`/`PUT` atualiza, `DELETE` remove), resposta em JSON com status code (`2xx` ok, `401` sem token, `403` sem permissão, `404` não existe, `429`/`430` limite). O padrão assíncrono: `POST` volta `202` + header `Location`, você faz `GET` nesse `Location` até virar `Completed`/`Failed`. Detalhe no README do case Fabric. |
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
| **Evento cru (BQ export nativo)** | ilimitado — todo parâmetro está em toda linha, dá pra `GROUP BY` qualquer combinação |
| **GA4 Data API** (git, Databricks, Fabric) | 9 dims / 10 métricas por chamada. Pra cobrir tudo, divide em várias chamadas com a chave de atribuição comum. A tratada de 16 dimensões numa tabela só **não** sai de uma chamada — a prata fica num grão mais estreito ou vira tabelas de breakdown separadas. |
| **Tabelas de relatório (Data Transfer Service)** | fixo no que o Google entrega — sem cruzamento livre, sem pivô de evento custom |
