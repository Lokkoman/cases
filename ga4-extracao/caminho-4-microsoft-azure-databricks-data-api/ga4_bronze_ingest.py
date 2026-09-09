# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "5"
# ///
# MAGIC %md
# MAGIC # GA4 -> Bronze: extração direta da API do Google Analytics
# MAGIC
# MAGIC Lê os dados de acesso do site raulpavao.com.br (propriedade GA4
# MAGIC 552236564) direto pela GA4 Data API — sem passar pelo BigQuery — e
# MAGIC grava o resultado como tabelas Delta na camada bronze, governadas
# MAGIC pelo Unity Catalog. A autenticação usa a mesma service account que
# MAGIC o site já usa no pipeline `fetch-analytics.mjs`
# MAGIC (`dashboard-ga4@raulpavao-com-br`), guardada como secret Databricks
# MAGIC em `ga4/service-account-key`.
# MAGIC
# MAGIC ## Chave comum entre as tabelas
# MAGIC
# MAGIC A GA4 Data API aceita no máximo **9 dimensões e 10 métricas por
# MAGIC consulta** (confirmado na prática, não só na doc). Toda tabela
# MAGIC abaixo carrega a mesma **chave de atribuição** nas 5 primeiras
# MAGIC posições — `date`, `sessionDefaultChannelGroup`, `sessionSource`,
# MAGIC `sessionMedium`, `sessionCampaignName` — e usa o resto do orçamento
# MAGIC pra cobrir um tema. É o mesmo padrão que o pacote dbt oficial da
# MAGIC Fivetran usa pra modelar GA4 (traffic acquisition, user acquisition,
# MAGIC events, conversions como tabelas separadas, todas ancoradas na mesma
# MAGIC chave de atribuição).

# COMMAND ----------

# MAGIC %pip install google-analytics-data
# MAGIC dbutils.library.restartPython()

# COMMAND ----------

import json
from datetime import datetime, timezone

from google.oauth2 import service_account
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import (
    DateRange,
    Dimension,
    GetMetadataRequest,
    Metric,
    RunReportRequest,
)

CATALOG = "raulpavao"
SCHEMA = "bronze"
PROPERTY_ID = "552236564"
RANGE_DAYS = 28

ATTRIBUTION_KEY = [
    "date",
    "sessionDefaultChannelGroup",
    "sessionSource",
    "sessionMedium",
    "sessionCampaignName",
]

sa_key_json = dbutils.secrets.get("ga4", "service-account-key")
sa_info = json.loads(sa_key_json)

credentials = service_account.Credentials.from_service_account_info(
    sa_info, scopes=["https://www.googleapis.com/auth/analytics.readonly"]
)
client = BetaAnalyticsDataClient(credentials=credentials)

window = DateRange(start_date=f"{RANGE_DAYS}daysAgo", end_date="today")
ingested_at = datetime.now(timezone.utc).isoformat()


def run_report(dimensions, metrics, date_range, order_bys=None, limit=None):
    request = RunReportRequest(
        property=f"properties/{PROPERTY_ID}",
        dimensions=[Dimension(name=d) for d in dimensions],
        metrics=[Metric(name=m) for m in metrics],
        date_ranges=[date_range],
        order_bys=order_bys or [],
        limit=limit,
    )
    response = client.run_report(request)
    rows = []
    for row in response.rows:
        record = {}
        for i, dim in enumerate(dimensions):
            record[dim] = row.dimension_values[i].value
        for i, met in enumerate(metrics):
            record[met] = row.metric_values[i].value
        record["ingested_at"] = ingested_at
        rows.append(record)
    return rows


def save_report(name, extra_dimensions, metrics, **kwargs):
    dimensions = ATTRIBUTION_KEY + extra_dimensions
    assert len(dimensions) <= 9, f"{name}: {len(dimensions)} dimensões, limite é 9"
    assert len(metrics) <= 10, f"{name}: {len(metrics)} métricas, limite é 10"
    rows = run_report(dimensions, metrics, window, **kwargs)
    if rows:
        df = spark.createDataFrame(rows)
    else:
        schema = ", ".join(f"{c} string" for c in [*dimensions, *metrics, "ingested_at"])
        df = spark.createDataFrame([], schema=schema)
    df.write.mode("overwrite").option("overwriteSchema", "true").format("delta").saveAsTable(
        f"{CATALOG}.{SCHEMA}.{name}"
    )
    return df

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Sessões: chave + id de campanha + canal primário

# COMMAND ----------

save_report(
    "ga4_sessions_daily",
    extra_dimensions=["sessionCampaignId", "sessionPrimaryChannelGroup"],
    metrics=["sessions", "totalUsers", "newUsers", "engagedSessions", "screenPageViews"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Atribuição de primeiro toque

# COMMAND ----------

save_report(
    "ga4_first_touch_daily",
    extra_dimensions=["firstUserDefaultChannelGroup", "firstUserSource", "firstUserMedium"],
    metrics=["sessions", "totalUsers"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Eventos-chave (o que fecha negócio), tabela própria

# COMMAND ----------

save_report(
    "ga4_key_events_daily",
    extra_dimensions=[],
    metrics=["keyEvents", "sessions"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Dispositivo

# COMMAND ----------

save_report(
    "ga4_device_daily",
    extra_dimensions=["deviceCategory", "operatingSystem", "browser"],
    metrics=["sessions", "activeUsers", "engagedSessions", "screenPageViews"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Geografia

# COMMAND ----------

save_report(
    "ga4_geo_daily",
    extra_dimensions=["country", "region", "city"],
    metrics=["sessions", "activeUsers", "engagedSessions", "screenPageViews"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Página de entrada

# COMMAND ----------

save_report(
    "ga4_landing_page_daily",
    extra_dimensions=["landingPage"],
    metrics=["sessions", "activeUsers", "engagedSessions", "screenPageViews"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. Eventos (todos os tipos)

# COMMAND ----------

save_report(
    "ga4_events_daily",
    extra_dimensions=["eventName", "deviceCategory", "country"],
    metrics=["eventCount", "activeUsers"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8. E-commerce

# COMMAND ----------

save_report(
    "ga4_ecommerce_daily",
    extra_dimensions=[],
    metrics=["transactions", "purchaseRevenue", "ecommercePurchases"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 9. Páginas vistas

# COMMAND ----------

save_report(
    "ga4_pages_daily",
    extra_dimensions=["pagePath"],
    metrics=["screenPageViews", "activeUsers"],
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Resumo da carga

# COMMAND ----------

BRONZE_TABLES = [
    "ga4_sessions_daily",
    "ga4_first_touch_daily",
    "ga4_key_events_daily",
    "ga4_device_daily",
    "ga4_geo_daily",
    "ga4_landing_page_daily",
    "ga4_events_daily",
    "ga4_ecommerce_daily",
    "ga4_pages_daily",
]

for t in BRONZE_TABLES:
    n = spark.table(f"{CATALOG}.{SCHEMA}.{t}").count()
    print(f"{CATALOG}.{SCHEMA}.{t}: {n} linhas")