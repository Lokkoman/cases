# Cases

Estudos de caso de engenharia analítica: como o dado é coletado, tratado e
entregue. Cada linha abaixo é um case, seja uma pasta deste repositório ou um
repositório próprio quando o projeto é maior.

| Case | Tema | Stack |
|---|---|---|
| [`ga4-extracao/`](ga4-extracao/) | Cinco pipelines de extração do Google Analytics 4, um por stack. Via GA4 Data API: GitHub Actions (JSON no repo) e Microsoft Azure — Azure Databricks (bronze + prata) e Fabric + Airflow. Via BigQuery, no Google Cloud: export nativo (evento cru) e Data Transfer Service (relatório pronto). Glossário em [`CONCEITOS.md`](ga4-extracao/CONCEITOS.md). | Node.js, GA4 Data API, GitHub Actions, BigQuery, SQL, Azure Databricks, PySpark, Delta Lake, Unity Catalog, Microsoft Fabric, Lakehouse/OneLake, Apache Airflow, Docker, Entra ID service principal, Azure Key Vault, REST |
| [`arquitetou`](https://github.com/Lokkoman/arquitetou) | Agregador de vagas com coleta multi-fonte: via API onde a fonte oferece (Gupy, LinkedIn via Bright Data) e scraping HTML no resto. Classificação por IA com o Gemini. Site estático no GitHub Pages. Repositório próprio. | Node.js, Bright Data, Google Gemini, GitHub Pages |

Mais cases entram como novas pastas ou links para repositórios próprios.

---

Raul Macedo Pavão · [raulpavao.com.br](https://raulpavao.com.br)
