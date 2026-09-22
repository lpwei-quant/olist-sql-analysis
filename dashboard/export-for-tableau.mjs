// Export the same query results used in the HTML dashboard.
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const out = join(root, 'dashboard/tableau');
mkdirSync(out, {recursive:true});
const q = JSON.parse(readFileSync(join(root, 'results/results.json'), 'utf8'));
const f = q.q06_funnel[0], r = q.q02_repeat_users[0];
const monthly = q.q05_monthly_gmv_cum.filter(r => r.ym < '2018-09');
const tables = {
 monthly_gmv: monthly.map(r => ({month:r.ym, gmv:r.gmv})),
 delivery_review: q.q09_delivery_vs_review.map(r => ({...r, bucket:r.delivery_bucket})),
 category_gmv:q.q10_category_share,
 state_gmv:q.q01_state_gmv,
 funnel:['placed','approved','shipped','delivered'].map((k,i)=>({step_order:i+1,stage:['下单','支付通过','已发货','已签收'][i],orders:f[k]})),
 cohort_return:q.q07_cohort_return,
 kpi_summary:[{total_gmv:Math.round(monthly.reduce((a,r)=>a+r.gmv,0)*100)/100,orders:f.placed,delivered_rate_pct:f.delivered_rate_pct,repeat_rate_pct:r.repeat_rate_pct,repeat_users:r.repeat_users,customers:r.total_users,late_delivery_bad_review_pct:q.q09_delivery_vs_review[3].bad_review_pct}]
};
const esc = v => '"'+String(v??'').replaceAll('"','""')+'"';
for (const [name,rows] of Object.entries(tables)) {
 const keys=Object.keys(rows[0]);
 writeFileSync(join(out,name+'.csv'),'\ufeff'+[keys.join(','),...rows.map(r=>keys.map(k=>esc(r[k])).join(','))].join('\n')+'\n');
 console.log(name, rows.length);
}
