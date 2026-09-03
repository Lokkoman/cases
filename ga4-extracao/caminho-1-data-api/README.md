# Caminho 1 — GA4 Data API

Coletor sem dependências: assina um JWT da service account com `node:crypto`,
troca por um access token e chama o `runReport` da GA4 Data API. Imprime o JSON
no stdout.

## Arquivos

| Arquivo | O que é |
|---|---|
| `fetch-analytics.mjs` | o coletor |
| `analytics-snapshot.yml` | workflow do GitHub Actions que roda o coletor a cada 3h e commita o JSON |
| `.env.example` | variáveis de ambiente necessárias |
| `analytics.sample.json` | formato do JSON de saída (números ilustrativos) |

## Pré-requisitos

1. **Projeto no Google Cloud** com a **Google Analytics Data API** ativada.
2. **Service account** nesse projeto, com uma **chave JSON**.
3. No **Admin do GA4** -> Administração -> **Acesso à propriedade**, adicionar o
   e-mail da service account como **Leitor**.

## Rodar local

```bash
export GA4_PROPERTY_ID=123456789
export GA_SA_KEY="$(cat service-account.json)"
node fetch-analytics.mjs > analytics.json
```

Requer Node 18+ (usa `fetch` nativo).

## Rodar em CI

1. Copie `analytics-snapshot.yml` para `.github/workflows/` e ajuste os caminhos.
2. No repositório: **Settings -> Secrets and variables -> Actions**
   - secret `GA_SA_KEY` = conteúdo do JSON da service account
   - variable `GA4_PROPERTY_ID` = ID da propriedade
3. O workflow roda a cada 3h (e no botão "Run workflow"). Se o JSON mudou, ele
   commita; se não, não faz nada.

## Notas

- A chave da service account **nunca** é commitada. Só entra por env/secret.
- O `runReport` aqui pede 4 relatórios (totais, série diária, top páginas, top
  países). Trocar as métricas e dimensões é só editar os `runReport` no script.
- A série `daily` acumula no `analytics.json`: a cada run só os últimos 7 dias
  são refeitos. Apague o arquivo para reconstruir do zero (limitado à janela de
  28 dias do relatório diário).
