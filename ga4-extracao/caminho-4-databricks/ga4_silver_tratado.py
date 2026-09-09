# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze -> Silver: tabela tratada (`google_analytics_tratado`)
# MAGIC
# MAGIC Equivalente ao que `dados_tratados.google_analytics_export_nativo`
# MAGIC é no BigQuery: uma linha por combinação de
# MAGIC `data, canal, origem, midia, campanha`, com todas as metricas
# MAGIC juntas (sessoes, usuarios, eventos-chave, e-commerce, dispositivo,
# MAGIC geografia e cada tipo de evento como coluna propria).
# MAGIC
# MAGIC Cada uma das 9 tabelas bronze e agregada (somada) ate essa chave
# MAGIC comum antes de qualquer juncao — nunca junta sem agregar primeiro,
# MAGIC pra nao duplicar nem perder linha por causa das dimensoes extras
# MAGIC que cada bronze carrega.

# COMMAND ----------

from functools import reduce

from pyspark.sql import functions as F

CATALOG = "raulpavao"
KEY = ["date", "channel", "source", "medium", "campaign"]

RENAME = {
    "date": "date",
    "sessionDefaultChannelGroup": "channel",
    "sessionSource": "source",
    "sessionMedium": "medium",
    "sessionCampaignName": "campaign",
}


def load_aggregated(table, sum_cols):
    df = spark.table(f"{CATALOG}.bronze.{table}")
    for old, new in RENAME.items():
        df = df.withColumnRenamed(old, new)
    df = df.withColumn("date", F.to_date("date", "yyyyMMdd"))
    for c in sum_cols:
        df = df.withColumn(c, F.col(c).cast("double"))
    return df.groupBy(*KEY).agg(*[F.sum(c).alias(c) for c in sum_cols])

# COMMAND ----------

sessions = load_aggregated(
    "ga4_sessions_daily", ["sessions", "totalUsers", "newUsers", "engagedSessions", "screenPageViews"]
)
first_touch = load_aggregated("ga4_first_touch_daily", ["sessions", "totalUsers"]).select(
    *KEY,
    F.col("sessions").alias("ft_sessions"),
    F.col("totalUsers").alias("ft_totalUsers"),
)
key_events = load_aggregated("ga4_key_events_daily", ["keyEvents", "sessions"]).select(
    *KEY, "keyEvents"
)
ecommerce = load_aggregated("ga4_ecommerce_daily", ["transactions", "purchaseRevenue", "ecommercePurchases"])
device = load_aggregated("ga4_device_daily", ["sessions", "activeUsers", "engagedSessions", "screenPageViews"]).select(
    *KEY,
    F.col("sessions").alias("dev_sessions"),
    F.col("activeUsers").alias("dev_activeUsers"),
)
geo = load_aggregated("ga4_geo_daily", ["sessions", "activeUsers", "engagedSessions", "screenPageViews"]).select(
    *KEY,
    F.col("sessions").alias("geo_sessions"),
    F.col("activeUsers").alias("geo_activeUsers"),
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Eventos: pivo de linha pra coluna (igual ao BigQuery)
# MAGIC
# MAGIC `ga4_events_daily` traz `eventName` como dimensao (uma linha por
# MAGIC tipo de evento). Vira uma coluna por evento, cada uma com a soma de
# MAGIC `eventCount`, o mesmo que `COUNTIF(nome_evento = '...')` faz no SQL
# MAGIC do BigQuery.

# COMMAND ----------

# nomes em portugues so para os eventos padrao do GA4 e os eventos-chave
# confirmados via metadata da API. Qualquer evento fora dessa lista mantem
# o nome original (eventName) como coluna, para nunca ficar de fora do
# pivo e a soma sempre bater com o total.
EVENT_LABELS = {
    "page_view": "visualizacoes_pagina",
    "first_visit": "primeiras_visitas",
    "scroll": "rolagens",
    "session_start": "inicios_sessao",
    "user_engagement": "pings_engajamento",
    "click": "cliques_saida",
    "view_search_results": "buscas",
    "file_download": "downloads",
    "video_start": "videos_iniciados",
    "form_submit": "formularios_enviados",
    "purchase": "compras",
    "close_convert_lead": "leads_fechados",
    "qualify_lead": "leads_qualificados",
}

events_raw = spark.table(f"{CATALOG}.bronze.ga4_events_daily")
for old, new in RENAME.items():
    events_raw = events_raw.withColumnRenamed(old, new)
events_raw = (
    events_raw
    .withColumn("date", F.to_date("date", "yyyyMMdd"))
    .withColumn("eventCount", F.col("eventCount").cast("double"))
)

event_names_presentes = [r[0] for r in events_raw.select("eventName").distinct().collect()]

events_pivot = (
    events_raw.groupBy(*KEY)
    .pivot("eventName", event_names_presentes)
    .agg(F.sum("eventCount"))
)
for original in event_names_presentes:
    renamed = EVENT_LABELS.get(original, original)
    events_pivot = events_pivot.withColumnRenamed(original, renamed)

# total geral de eventos, todos os tipos (inclui os que não viraram coluna própria)
events_total = load_aggregated("ga4_events_daily", ["eventCount"]).select(
    *KEY, F.col("eventCount").alias("total_eventos")
)

events = events_pivot.join(events_total, on=KEY, how="outer")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Junta tudo pela chave de 5

# COMMAND ----------

tables = [sessions, first_touch, key_events, ecommerce, device, geo, events]
df_unified = reduce(lambda a, b: a.join(b, on=KEY, how="left"), tables)

df_unified = df_unified.fillna(0, subset=[c for c in df_unified.columns if c not in KEY])

df_unified.write.mode("overwrite").option("overwriteSchema", "true").format("delta").saveAsTable(
    f"{CATALOG}.silver.google_analytics_tratado"
)

n = df_unified.count()
top_row = df_unified.orderBy(F.desc("sessions")).limit(1).toPandas().to_dict(orient="records")

event_cols = [EVENT_LABELS.get(e, e) for e in event_names_presentes]
linha_soma = sum(F.col(c) for c in event_cols)
check = df_unified.select(
    F.sum("total_eventos").alias("total_eventos"),
    F.sum(linha_soma).alias("soma_colunas_evento"),
).toPandas().to_dict(orient="records")[0]

import json as _json
dbutils.notebook.exit(_json.dumps({"linhas": n, "exemplo": top_row, "conferencia": check}, default=str))