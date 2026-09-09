import json
from datetime import datetime, timezone

from google.oauth2 import service_account
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import DateRange, Dimension, Metric, RunReportRequest

LAKEHOUSE = "lh_ga4_portfolio"
PROPERTY_ID = "552236564"
RANGE_DAYS = 28
KEY_VAULT_URL = "https://kv-raulpavao-fabric.vault.azure.net/"

ATTRIBUTION_KEY = ["date", "sessionDefaultChannelGroup", "sessionSource", "sessionMedium", "sessionCampaignName"]

sa_key_json = notebookutils.credentials.getSecret(KEY_VAULT_URL, "ga4-service-account-key")
sa_info = json.loads(sa_key_json)

credentials = service_account.Credentials.from_service_account_info(sa_info, scopes=["https://www.googleapis.com/auth/analytics.readonly"])
client = BetaAnalyticsDataClient(credentials=credentials)

window = DateRange(start_date=f"{RANGE_DAYS}daysAgo", end_date="today")
ingested_at = datetime.now(timezone.utc).isoformat()


def run_report(dimensions, metrics, date_range):
    request = RunReportRequest(property=f"properties/{PROPERTY_ID}", dimensions=[Dimension(name=d) for d in dimensions], metrics=[Metric(name=m) for m in metrics], date_ranges=[date_range])
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


def save_table(name, extra_dimensions, metrics):
    dimensions = ATTRIBUTION_KEY + extra_dimensions
    assert len(dimensions) <= 9, name
    assert len(metrics) <= 10, name
    rows = run_report(dimensions, metrics, window)
    if rows:
        df = spark.createDataFrame(rows)
    else:
        schema = ", ".join(f"{c} string" for c in [*dimensions, *metrics, "ingested_at"])
        df = spark.createDataFrame([], schema=schema)
    df.write.mode("overwrite").option("overwriteSchema", "true").format("delta").saveAsTable(name)
    return df


save_table(
    "bronze_sessions_daily",
    ["sessionCampaignId", "sessionPrimaryChannelGroup", "sessionManualAdContent", "sessionManualTerm"],
    ["sessions", "totalUsers", "newUsers", "engagedSessions", "screenPageViews", "keyEvents", "userEngagementDuration"],
)
save_table(
    "bronze_first_touch_daily",
    ["firstUserDefaultChannelGroup", "firstUserSource", "firstUserMedium", "firstUserCampaignName"],
    ["sessions", "totalUsers", "newUsers", "engagedSessions"],
)
save_table(
    "bronze_key_events_daily",
    ["eventName"],
    ["keyEvents", "eventCount"],
)
save_table(
    "bronze_device_daily",
    ["deviceCategory", "operatingSystem", "browser"],
    ["sessions", "totalUsers", "activeUsers", "newUsers", "engagedSessions", "screenPageViews", "userEngagementDuration"],
)
save_table(
    "bronze_geo_daily",
    ["country", "region", "city"],
    ["sessions", "totalUsers", "activeUsers", "newUsers", "engagedSessions", "screenPageViews", "userEngagementDuration"],
)
save_table(
    "bronze_landing_page_daily",
    ["landingPagePlusQueryString"],
    ["sessions", "totalUsers", "engagedSessions", "screenPageViews", "keyEvents", "userEngagementDuration"],
)
save_table(
    "bronze_events_daily",
    ["eventName"],
    ["eventCount", "activeUsers"],
)
save_table(
    "bronze_ecommerce_daily",
    [],
    ["transactions", "purchaseRevenue", "ecommercePurchases", "totalRevenue", "itemsPurchased"],
)
save_table(
    "bronze_pages_daily",
    ["pagePathPlusQueryString"],
    ["screenPageViews", "sessions", "activeUsers", "userEngagementDuration"],
)

tables = [
    "bronze_sessions_daily",
    "bronze_first_touch_daily",
    "bronze_key_events_daily",
    "bronze_device_daily",
    "bronze_geo_daily",
    "bronze_landing_page_daily",
    "bronze_events_daily",
    "bronze_ecommerce_daily",
    "bronze_pages_daily",
]
for t in tables:
    print(f"{t}: {spark.table(t).count()} linhas")
