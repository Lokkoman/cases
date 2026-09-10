# Caminho 4 — Google BigQuery + Data Transfer Service

O BigQuery tem um conector **"Google Analytics 4"** no Data Transfer Service que
puxa as **tabelas de relatório prontas** do GA4 — as mesmas da biblioteca de
relatórios: Aquisição de tráfego, Páginas e telas, Eventos, Dados demográficos,
Tecnologia, e outras. Já vêm agregadas, sem SQL de modelagem.

Sem código: é configuração de console. O `exemplo.sql` mostra como consultar.

## Arquivos

| Arquivo | O que é |
|---|---|
| `exemplo.sql` | aquisição de tráfego por canal e páginas mais vistas, lendo as views deduplicadas |

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

Cada relatório é um **agregado de um tema só**, com as dimensões daquele tema e
nada além. Alguns dos que aparecem:

| View | Dimensões | Métricas típicas |
|---|---|---|
| `ga4_TrafficAcquisition_<ID>` | `sessionDefaultChannelGroup`, `sessionSource`, `sessionMedium`, `sessionCampaignName`, `sessionPrimaryChannelGroup`, `sessionSourceMedium`, `sessionSourcePlatform` | sessions, engagedSessions, engagementRate, keyEvents, sessionKeyEventRate, eventsPerSession, totalRevenue |
| `ga4_TechDetails_<ID>` | `deviceCategory`, `operatingSystem`, `browser`, `platform`, `screenResolution`, … | activeUsers, engagedSessions, eventCount, keyEvents, newUsers |
| `ga4_LandingPage_<ID>` | **só `landingPage`** | sessions, activeUsers, newUsers, keyEvents, sessionKeyEventRate |
| `ga4_DemographicDetails_<ID>` | `country`, `region`, `city`, `language`, `userAgeBracket`, `userGender` | activeUsers, engagedSessions, … |
| `ga4_Events_<ID>` | `eventName` | eventCount, keyEvents, totalUsers |

## Não dá pra montar o `fato_sessoes` aqui

O `fato_sessoes` dos caminhos 2, 5 e 6 traz aquisição, device, cidade e landing
page na mesma linha porque a Data API agrega **depois** de saber a que sessão
cada evento pertence. No Data Transfer Service cada tema já chega agregado
sozinho, e a única coisa em comum entre as tabelas é a data.

Juntar `TrafficAcquisition` com `TechDetails` por data não é só explosão
cartesiana. As 100 sessões de `Organic` do dia e os 40 de `iOS` do dia viram
linhas `Organic × iOS`, `Organic × Android`, e a métrica de um recorte é
repetida em cada valor do outro. Você passa a contar a sessão de um usuário no
balde de outro. O número sai plausível e errado. `sessionCampaignId` e
`sessionManualAdContent` nem existem no DTS.

Uma linha com muitas dimensões só sai do evento cru, onde cada dimensão está
presa à sessão certa antes de qualquer soma
([caminho 3](../caminho-3-google-bigquery-export-nativo/)).

## Custo

Fontes do próprio Google no Data Transfer Service não têm taxa de transferência.
Só o armazenamento das tabelas.

## Serve para

Ter rápido, sem escrever SQL de modelagem, os números que o GA4 já mostra na
tela, num lugar onde dá pra ligar com outras fontes por uma chave real (data,
campanha) num modelo de BI. **Não** te dá o evento cru, e os relatórios não se
cruzam entre si sem enviesar: é fixo no que o Google entrega.
