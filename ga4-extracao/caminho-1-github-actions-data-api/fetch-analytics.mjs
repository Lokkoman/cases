#!/usr/bin/env node
// Puxa números de acesso pela GA4 Data API e imprime o JSON que um
// dashboard leve consome. Sem dependências: assina o JWT da service
// account com node:crypto e troca por um access token.
//
// Janela de reprocessamento: a série `daily` é histórico acumulado no
// próprio analytics.json. A cada execução só os últimos
// HISTORY_REFRESH_DAYS dias são buscados de novo e sobrescritos, o resto
// do histórico é preservado (o GA4 ainda corrige dado recente por alguns
// dias). Os totais e os rankings são uma janela móvel de RANGE_DAYS dias,
// sempre refeitos por inteiro.
//
// Uso:
//   GA4_PROPERTY_ID=123456789 \
//   GA_SA_KEY="$(cat service-account.json)" \
//   node fetch-analytics.mjs > analytics.json

import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';

const PROPERTY_ID = process.env.GA4_PROPERTY_ID;
const PROPERTY_LABEL = process.env.GA4_PROPERTY_LABEL || '';
const RANGE_DAYS = 28; // janela móvel dos totais e rankings
const HISTORY_REFRESH_DAYS = 7; // dias da série diária reprocessados a cada run

// analytics.json fica ao lado deste script
const OUT_URL = new URL('./analytics.json', import.meta.url);

function fail(msg) {
  console.error(`fetch-analytics: ${msg}`);
  process.exit(1);
}

if (!PROPERTY_ID) fail('variável GA4_PROPERTY_ID ausente');

const rawKey = process.env.GA_SA_KEY;
if (!rawKey) fail('variável GA_SA_KEY ausente');

let sa;
try {
  sa = JSON.parse(rawKey);
} catch {
  fail('GA_SA_KEY não é um JSON válido');
}
if (!sa.client_email || !sa.private_key) fail('JSON da service account incompleto');

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function getAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/analytics.readonly',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const signature = b64url(
    crypto.sign('RSA-SHA256', Buffer.from(`${header}.${claim}`), sa.private_key),
  );
  const assertion = `${header}.${claim}.${signature}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const data = await res.json();
  if (!data.access_token) fail(`falha no token OAuth: ${JSON.stringify(data)}`);
  return data.access_token;
}

async function runReport(token, body) {
  const res = await fetch(
    `https://analyticsdata.googleapis.com/v1beta/properties/${PROPERTY_ID}:runReport`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    },
  );
  const data = await res.json();
  if (data.error) fail(`Data API: ${data.error.message}`);
  return data.rows || [];
}

const windowRange = { startDate: `${RANGE_DAYS}daysAgo`, endDate: 'today' };
const dailyRange = { startDate: `${HISTORY_REFRESH_DAYS}daysAgo`, endDate: 'today' };
const num = (row, i) => Number(row.metricValues[i].value || 0);

const token = await getAccessToken();

const [totalsRows, dailyRows, pageRows, countryRows] = await Promise.all([
  runReport(token, {
    dateRanges: [windowRange],
    metrics: [
      { name: 'activeUsers' },
      { name: 'sessions' },
      { name: 'screenPageViews' },
      { name: 'averageSessionDuration' },
      { name: 'newUsers' },
    ],
  }),
  runReport(token, {
    dateRanges: [dailyRange],
    dimensions: [{ name: 'date' }],
    metrics: [{ name: 'screenPageViews' }, { name: 'activeUsers' }],
    orderBys: [{ dimension: { dimensionName: 'date' } }],
  }),
  runReport(token, {
    dateRanges: [windowRange],
    dimensions: [{ name: 'pagePath' }],
    metrics: [{ name: 'screenPageViews' }],
    orderBys: [{ metric: { metricName: 'screenPageViews' }, desc: true }],
    limit: 6,
  }),
  runReport(token, {
    dateRanges: [windowRange],
    dimensions: [{ name: 'country' }],
    metrics: [{ name: 'activeUsers' }],
    orderBys: [{ metric: { metricName: 'activeUsers' }, desc: true }],
    limit: 5,
  }),
]);

const t = totalsRows[0];
const activeUsers = t ? num(t, 0) : 0;
const newUsers = t ? num(t, 4) : 0;

// série diária: histórico já salvo + os últimos HISTORY_REFRESH_DAYS dias refeitos
const freshDaily = dailyRows.map((r) => ({
  date: `${r.dimensionValues[0].value.slice(0, 4)}-${r.dimensionValues[0].value.slice(4, 6)}-${r.dimensionValues[0].value.slice(6, 8)}`,
  screenPageViews: num(r, 0),
  activeUsers: num(r, 1),
}));

let priorDaily = [];
try {
  priorDaily = JSON.parse(readFileSync(OUT_URL, 'utf8')).daily ?? [];
} catch {
  priorDaily = [];
}

const byDate = new Map(priorDaily.map((d) => [d.date, d]));
for (const d of freshDaily) byDate.set(d.date, d);
const daily = [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date));

const out = {
  updatedAt: new Date().toISOString().slice(0, 10),
  generatedAt: new Date().toISOString(),
  range: `Últimos ${RANGE_DAYS} dias`,
  property: PROPERTY_LABEL,
  totals: {
    activeUsers,
    sessions: t ? num(t, 1) : 0,
    screenPageViews: t ? num(t, 2) : 0,
    avgEngagementSeconds: t ? Math.round(num(t, 3)) : 0,
    newUsersPct: activeUsers ? Math.round((newUsers / activeUsers) * 100) : 0,
  },
  daily,
  topPages: pageRows.map((r) => ({ path: r.dimensionValues[0].value, views: num(r, 0) })),
  topCountries: countryRows.map((r) => ({ country: r.dimensionValues[0].value, users: num(r, 0) })),
};

process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
