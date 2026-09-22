// 建库 → 导入 CSV → 执行 sql/queries.sql → 输出 results/results.md
// 运行：node run.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createHash } from 'node:crypto';

const root = dirname(fileURLToPath(import.meta.url));
const dataDir = join(root, 'data');
const sqlDir = join(root, 'sql');
const outDir = join(root, 'results');
const dbPath = join(root, 'olist.db');

if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else { inQuotes = false; }
      } else field += ch;
    } else if (ch === '"') inQuotes = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (ch === '\r') { /* skip */ }
    else field += ch;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  if (inQuotes) throw new Error('Unclosed CSV quote');
  return rows;
}

const files = [
  ['olist_customers_dataset.csv', 'customers'],
  ['olist_orders_dataset.csv', 'orders'],
  ['olist_order_items_dataset.csv', 'order_items'],
  ['olist_order_payments_dataset.csv', 'order_payments'],
  ['olist_order_reviews_dataset.csv', 'order_reviews'],
  ['olist_products_dataset.csv', 'products'],
  ['olist_sellers_dataset.csv', 'sellers'],
  ['product_category_name_translation.csv', 'category_translation'],
];

// Validate every required input before replacing the derived database.
for (const [file] of files) {
  if (!existsSync(join(dataDir, file))) throw new Error(`Missing required input: data/${file}. See README.md`);
}
if (existsSync(dbPath)) rmSync(dbPath);
const db = new DatabaseSync(dbPath);
db.exec(readFileSync(join(sqlDir, 'schema.sql'), 'utf8'));

const counts = [];
const hashes = {};
for (const [file, table] of files) {
  const path = join(dataDir, file);
  const bytes = readFileSync(path);
  hashes[file] = createHash('sha256').update(bytes).digest('hex');
  const rows = parseCsv(bytes.toString('utf8'));
  const header = rows[0].map(h => h.trim());
  const body = rows.slice(1).filter(r => r.some(v => v !== ''));
  if (body.some(r => r.length !== header.length)) throw new Error(`Malformed CSV row in ${file}`);
  const expected = db.prepare(`PRAGMA table_info(${table})`).all().map(r => r.name);
  if (JSON.stringify(header) !== JSON.stringify(expected)) throw new Error(`Unexpected CSV columns in ${file}`);
  const cols = header.map(h => h.trim()).join(', ');
  const ph = header.map(() => '?').join(', ');
  const stmt = db.prepare(`INSERT INTO ${table} (${cols}) VALUES (${ph})`);
  db.exec('BEGIN');
  for (const r of body) stmt.run(...r.map(v => (v === '' ? null : v)));
  db.exec('COMMIT');
  counts.push([table, body.length]);
  console.log(`loaded ${table}: ${body.length} rows`);
}

const queriesText = readFileSync(join(sqlDir, 'queries.sql'), 'utf8');
const blocks = [];
let current = null;
for (const line of queriesText.split(/\r?\n/)) {
  const m = line.match(/^--\s*@query:\s*(\w+)/);
  if (m) { current = { name: m[1], comments: [], sql: [] }; blocks.push(current); continue; }
  if (!current) continue;
  if (line.trim().startsWith('--')) current.comments.push(line.replace(/^--\s?/, ''));
  else if (line.trim()) current.sql.push(line);
}

function toMarkdownTable(rows) {
  if (!rows.length) return '（无结果）';
  const cols = Object.keys(rows[0]);
  const head = `| ${cols.join(' | ')} |`;
  const sep = `| ${cols.map(() => '---').join(' | ')} |`;
  const body = rows.map(r => `| ${cols.map(c => (r[c] === null ? '' : r[c])).join(' | ')} |`);
  return [head, sep, ...body].join('\n');
}

const md = [];
const results = {};
let failures = 0;
md.push('# Olist 电商数据 SQL 分析结果');
md.push('');
md.push(`生成时间：${new Date().toISOString()}`);
md.push('');
md.push('## 数据规模');
md.push('');
md.push('| 表 | 行数 |');
md.push('| --- | --- |');
for (const [t, n] of counts) md.push(`| ${t} | ${n} |`);
md.push('');
md.push('## 查询结果');
md.push('');

for (const b of blocks) {
  const sql = b.sql.join('\n').trim().replace(/;$/, '');
  if (!sql) continue;
  md.push(`### ${b.name}`);
  md.push('');
  if (b.comments.length) { md.push(b.comments.join(' ')); md.push(''); }
  try {
    const rows = db.prepare(sql).all();
    results[b.name] = rows;
    md.push(toMarkdownTable(rows));
    console.log('ok', b.name, rows.length, 'rows');
  } catch (e) {
    failures++;
    md.push(`查询失败：${e.message}`);
    console.log('fail', b.name, e.message);
  }
  md.push('');
}

writeFileSync(join(outDir, 'results.md'), md.join('\n'), 'utf8');
if (failures) throw new Error(`${failures} queries failed; output is incomplete`);
writeFileSync(join(outDir, 'results.json'), JSON.stringify(results, null, 2));
writeFileSync(join(outDir, 'source-manifest.json'), JSON.stringify({node: process.version, sha256: hashes, counts}, null, 2));
db.close();
console.log('written results/results.md');
