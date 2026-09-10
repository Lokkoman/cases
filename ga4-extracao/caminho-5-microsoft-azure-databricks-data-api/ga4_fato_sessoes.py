# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "5"
# ///
# MAGIC %md
# MAGIC # GA4 -> `fato_sessoes`: extração direta da API do Google Analytics
# MAGIC
# MAGIC Lê os dados do site raulpavao.com.br (propriedade GA4 552236564) direto
# MAGIC pela **GA4 Data API** — sem passar pelo BigQuery — e grava **uma tabela
# MAGIC Delta** governada pelo Unity Catalog: `raulpavao.ga4.fato_sessoes`.
# MAGIC
# MAGIC Uma linha por combinação das 9 dimensões de mídia; 10 métricas. É o
# MAGIC **teto de uma chamada `runReport`** (9 dims / 10 métricas). O mesmo
# MAGIC schema sai do caminho 2 (Sheets) e do caminho 6 (Fabric).
# MAGIC
# MAGIC A autenticação usa a service account que o site já usa no
# MAGIC `fetch-analytics.mjs` (`dashboard-ga4@raulpavao-com-br`), guardada como
# MAGIC secret Databricks em `ga4/service-account-key`.

# COMMAND ----------

# MAGIC %pip install google-analytics-data
# MAGIC dbutils.library.restartPython()

# COMMAND ----------

import json
from datetime import datetime, timezone

from google.oauth2 import service_account
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import DateRange, Dimension, Metric, RunReportRequest

CATALOG = "raulpavao"
SCHEMA = "ga4"
TABLE = "fato_sessoes"
PROPERTY_ID = "552236564"
RANGE_DAYS = 28

# 9 dimensões de mídia (o máximo por chamada)
DIMENSIONS = [
    "date",
    "sessionDefaultChannelGroup",
    "sessionSource",
    "sessionMedium",
    "sessionManualAdContent",
    "sessionCampaignId",
    "operatingSystem",
    "city",
    "landingPagePlusQueryString",
]

# 10 métricas (o máximo por chamada)
METRICS = [
    "sessions",
    "totalUsers",
    "newUsers",
    "engagedSessions",
    "engagementRate",
    "screenPageViews",
    "eventsPerSession",
    "keyEvents",
    "sessionKeyEventRate",
    "averageSessionDuration",
]

sa_key_json = dbutils.secrets.get("ga4", "service-account-key")
sa_info = json.loads(sa_key_json)

credentials = service_account.Credentials.from_service_account_info(
    sa_info, scopes=["https://www.googleapis.com/auth/analytics.readonly"]
)
client = BetaAnalyticsDataClient(credentials=credentials)

# COMMAND ----------

assert len(DIMENSIONS) <= 9, f"{len(DIMENSIONS)} dimensões, limite é 9"
assert len(METRICS) <= 10, f"{len(METRICS)} métricas, limite é 10"

request = RunReportRequest(
    property=f"properties/{PROPERTY_ID}",
    dimensions=[Dimension(name=d) for d in DIMENSIONS],
    metrics=[Metric(name=m) for m in METRICS],
    date_ranges=[DateRange(start_date=f"{RANGE_DAYS}daysAgo", end_date="today")],
)
response = client.run_report(request)

ingested_at = datetime.now(timezone.utc).isoformat()
rows = []
for row in response.rows:
    record = {DIMENSIONS[i]: v.value for i, v in enumerate(row.dimension_values)}
    record.update({METRICS[i]: v.value for i, v in enumerate(row.metric_values)})
    record["ingested_at"] = ingested_at
    rows.append(record)

# COMMAND ----------

if rows:
    df = spark.createDataFrame(rows)
else:
    schema = ", ".join(f"{c} string" for c in [*DIMENSIONS, *METRICS, "ingested_at"])
    df = spark.createDataFrame([], schema=schema)

df.write.mode("overwrite").option("overwriteSchema", "true").format("delta").saveAsTable(
    f"{CATALOG}.{SCHEMA}.{TABLE}"
)

print(f"{CATALOG}.{SCHEMA}.{TABLE}: {df.count()} linhas")
