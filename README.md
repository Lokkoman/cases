# Cases

Estudos de caso de engenharia analítica: como o dado é coletado, tratado e
entregue. Cada linha abaixo é um case, seja uma pasta deste repositório ou um
repositório próprio quando o projeto é maior.

| Case | Tema | Stack |
|---|---|---|
| [`ga4-extracao/`](ga4-extracao/) | As 5 formas de extrair os dados do Google Analytics 4. Caminhos 1–3: as saídas do GA4 (Data API, export nativo, Data Transfer Service). Caminhos 4–5: a Data API virada pipeline de engenharia, no Databricks (bronze + prata) e no Fabric orquestrado por Airflow. Glossário em [`CONCEITOS.md`](ga4-extracao/CONCEITOS.md). | Node.js, GA4 Data API, GitHub Actions, BigQuery, SQL, Azure Databricks, PySpark, Delta Lake, Unity Catalog, Microsoft Fabric, Lakehouse/OneLake, Apache Airflow, Docker, Entra ID service principal, Azure Key Vault, REST |
| [`arquitetou`](https://github.com/Lokkoman/arquitetou) | Agregador de vagas com coleta multi-fonte: via API onde a fonte oferece (Gupy, LinkedIn via Bright Data) e scraping HTML no resto. Classificação por IA com o Gemini. Site estático no GitHub Pages. Repositório próprio. | Node.js, Bright Data, Google Gemini, GitHub Pages |

Mais cases entram como novas pastas ou links para repositórios próprios.

---

Raul Macedo Pavão · [raulpavao.com.br](https://raulpavao.com.br)
