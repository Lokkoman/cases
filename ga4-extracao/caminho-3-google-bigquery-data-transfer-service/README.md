# Caminho 3 — Google BigQuery + Data Transfer Service

O BigQuery tem um conector **"Google Analytics 4"** no Data Transfer Service que
puxa as **tabelas de relatório prontas** do GA4 — as mesmas da biblioteca de
relatórios: Aquisição de tráfego, Páginas e telas, Eventos, Dados demográficos,
Tecnologia, e outras. Já vêm agregadas, sem SQL de modelagem.

Sem código: é configuração de console. O `exemplo.sql` mostra como consultar.

## Arquivos

| Arquivo | O que é |
|---|---|
| `exemplo.sql` | aquisição de tráfego por canal (28 dias) e páginas mais vistas (7 dias), lendo as views deduplicadas |

## Como montar

1. **BigQuery → Transferências de dados → Criar transferência**.
2. Origem: **"Google Analytics 4"**.
3. Informar o **ID da propriedade**, o **dataset de destino**, a **frequência**
   (24h) e a **janela de atualização** — quantos dias reprocessar a cada
   execução, pra pegar dado que o GA4 ainda estava fechando. 7 é um bom padrão.
4. Autorizar com sua **conta Google** (OAuth, uma vez). A conta precisa ter
   acesso à propriedade GA4.
5. O serviço agenda sozinho um preenchimento (backfill) dos últimos dias.

## O que sai

Uma tabela por relatório, particionada por data, no schema do Google. Cada
relatório vem em **dupla**:

| Objeto | O que é |
|---|---|
| `p_ga4_<Relatorio>_<ID>` | tabela particionada com **todas** as cargas. Como a janela de 7 dias re-busca os mesmos dias, aqui há linhas repetidas. **Não consulte esta.** |
| `ga4_<Relatorio>_<ID>` | **view** deduplicada por cima. É a que você consulta. |

Exemplos de relatório: `ga4_TrafficAcquisition_<ID>`,
`ga4_PagesAndScreens_<ID>`, `ga4_Events_<ID>`. Os nomes das colunas variam por
relatório — confira no schema da tabela.

## Custo

Fontes do próprio Google no Data Transfer Service não têm taxa de transferência.
Só o armazenamento das tabelas.

## Serve para

Ter rápido, sem escrever SQL de modelagem, os números que o GA4 já mostra na
tela, num lugar onde dá pra juntar com outras fontes. **Não** te dá o evento
cru nem cruzamento livre de dimensões — é fixo no que o Google entrega.
