import os
from datetime import datetime

from airflow import DAG
from airflow.providers.microsoft.fabric.operators.run_item import MSFabricRunJobOperator

WORKSPACE_ID = os.environ["FABRIC_WORKSPACE_ID"]
NOTEBOOK_ITEM_ID = os.environ["FABRIC_NOTEBOOK_ITEM_ID"]

with DAG(
    dag_id="ga4_fato_sessoes_fabric",
    description="Dispara o notebook nb_ga4_fato_sessoes no Fabric e espera terminar.",
    schedule="0 6 * * *",
    start_date=datetime(2026, 9, 1),
    catchup=False,
    tags=["ga4", "fabric"],
):
    MSFabricRunJobOperator(
        task_id="run_fato_sessoes",
        workspace_id=WORKSPACE_ID,
        item_id=NOTEBOOK_ITEM_ID,
        fabric_conn_id="fabric_conn",
        job_type="RunNotebook",
        wait_for_termination=True,
        deferrable=True,
    )
