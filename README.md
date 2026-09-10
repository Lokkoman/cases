# Cases

Estudos de caso de engenharia analítica: como o dado é coletado, tratado e
entregue. Cada linha abaixo é um case, seja uma pasta deste repositório ou um
repositório próprio quando o projeto é maior.

| Case | Tema | Stack |
|---|---|---|
| [`ga4-extracao/`](ga4-extracao/) | Seis pipelines de extração do Google Analytics 4, um por stack, do mais leve ao mais pesado. Via GA4 Data API: GitHub Actions (snapshot JSON no repo), e Google Sheets, Azure Databricks e Fabric + Airflow, que entregam a mesma tabela de mídia `fato_sessoes` numa chamada só. Via BigQuery, no Google Cloud: export nativo (evento cru achatado numa view `dados_tratados.eventos` — 1 linha por evento, cada valor em coluna, cada `event_name` num indicador — de onde o `fato_sessoes` sai por `GROUP BY`) e Data Transfer Service (relatórios de tema, que não se cruzam sem enviesar). Glossário em [`CONCEITOS.md`](ga4-extracao/CONCEITOS.md). | Node.js, GA4 Data API, Google Sheets, BigQuery, SQL, Azure Databricks, PySpark, Delta Lake, Unity Catalog, Microsoft Fabric, Lakehouse/OneLake, Apache Airflow, Docker, Entra ID service principal, Azure Key Vault, REST |
| [`arquitetou`](https://github.com/Lokkoman/arquitetou) | Agregador de vagas com coleta multi-fonte: via API onde a fonte oferece (Gupy, LinkedIn via Bright Data) e scraping HTML no resto. Classificação por IA com o Gemini. Site estático no GitHub Pages. Repositório próprio. | Node.js, Bright Data, Google Gemini, GitHub Pages |

Mais cases entram como novas pastas ou links para repositórios próprios.

---

Raul Macedo Pavão · [raulpavao.com.br](https://raulpavao.com.br)
