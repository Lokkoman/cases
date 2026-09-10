# Cópia versionada do código que roda no Notebook `nb_ga4_fato_sessoes`
# do Microsoft Fabric (Lakehouse `lh_ga4_portfolio`). O Airflow dispara este
# notebook pela REST API do Fabric; o notebook em si só chama a GA4 Data API
# e grava uma tabela Delta.
#
# Mesmo schema do caminho 2 (Sheets) e do caminho 5 (Databricks):
# 9 dimensões de mídia, 10 métricas — o teto de uma chamada `runReport`.

import json
from datetime import datetime, timezone

from google.oauth2 import service_account
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import DateRange, Dimension, Metric, RunReportRequest

TABLE = "fato_sessoes"
PROPERTY_ID = "552236564"
RANGE_DAYS = 28
KEY_VAULT_URL = "https://kv-raulpavao-fabric.vault.azure.net/"

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

assert len(DIMENSIONS) <= 9 and len(METRICS) <= 10

sa_key_json = notebookutils.credentials.getSecret(KEY_VAULT_URL, "ga4-service-account-key")
sa_info = json.loads(sa_key_json)

credentials = service_account.Credentials.from_service_account_info(
    sa_info, scopes=["https://www.googleapis.com/auth/analytics.readonly"]
)
client = BetaAnalyticsDataClient(credentials=credentials)

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

if rows:
    df = spark.createDataFrame(rows)
else:
    schema = ", ".join(f"{c} string" for c in [*DIMENSIONS, *METRICS, "ingested_at"])
    df = spark.createDataFrame([], schema=schema)

df.write.mode("overwrite").option("overwriteSchema", "true").format("delta").saveAsTable(TABLE)

print(f"{TABLE}: {df.count()} linhas")
