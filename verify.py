"""Independent checks against raw CSV (Python standard library only)."""
import csv
import json
import sqlite3
import unittest
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read(name):
    with (ROOT / 'data' / name).open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


class AnalysisChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.orders = read('olist_orders_dataset.csv')
        cls.items = read('olist_order_items_dataset.csv')
        cls.customers = read('olist_customers_dataset.csv')
        cls.reviews = read('olist_order_reviews_dataset.csv')
        cls.result = json.loads((ROOT / 'results/results.json').read_text(encoding='utf-8'))
        cls.db = sqlite3.connect(f'{(ROOT / "olist.db").as_uri()}?mode=ro', uri=True)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_input_scale_and_unique_order_keys(self):
        self.assertEqual(len(self.orders), 99441)
        self.assertEqual(len({r['order_id'] for r in self.orders}), len(self.orders))
        self.assertEqual(len(self.items), 112650)
        self.assertEqual(len(self.reviews), 99224)

    def test_gmv_from_raw_decimal_amounts(self):
        valid = {r['order_id'] for r in self.orders if r['order_status'] not in ('canceled','unavailable')}
        total = sum(Decimal(r['price']) + Decimal(r['freight_value']) for r in self.items if r['order_id'] in valid)
        monthly = sum(Decimal(str(r['gmv'])) for r in self.result['q05_monthly_gmv_cum'])
        self.assertEqual(total, monthly)
        # The common join grain also covers every item product / seller reference.
        n = self.db.execute('SELECT COUNT(*) FROM order_items i LEFT JOIN products p USING(product_id) LEFT JOIN sellers s USING(seller_id) WHERE p.product_id IS NULL OR s.seller_id IS NULL').fetchone()[0]
        self.assertEqual(n, 0)

    def test_delivery_counts_and_rates_against_csv(self):
        latest = {}
        for i, r in enumerate(self.reviews):
            key=(r['review_answer_timestamp'],r['review_creation_date'],r['review_id'],i)
            if r['order_id'] not in latest or key > latest[r['order_id']][0]:
                latest[r['order_id']] = (key, int(r['review_score']))
        buckets = defaultdict(list)
        for o in self.orders:
            if not o['order_delivered_customer_date'] or o['order_id'] not in latest:
                continue
            days=(datetime.fromisoformat(o['order_delivered_customer_date'])-datetime.fromisoformat(o['order_purchase_timestamp'])).total_seconds()/86400
            score=latest[o['order_id']][1]
            if days < 0 or not 1 <= score <= 5:
                continue
            b=0 if days<=7 else 1 if days<=14 else 2 if days<=21 else 3
            buckets[b].append(score)
        for i,row in enumerate(self.result['q09_delivery_vs_review']):
            self.assertEqual(row['orders'],len(buckets[i]))
            self.assertAlmostEqual(row['bad_review_pct'],100*sum(s<=2 for s in buckets[i])/len(buckets[i]),delta=0.0051)

    def test_fixed_next_month_cohort_against_csv(self):
        customer={r['customer_id']:r['customer_unique_id'] for r in self.customers}
        months=defaultdict(set)
        for o in self.orders:
            months[customer[o['customer_id']]].add(o['order_purchase_timestamp'][:7])
        cohorts=defaultdict(lambda:[0,0])
        for values in months.values():
            first=min(values)
            if first > '2018-07':
                continue
            y,m=map(int,first.split('-'))
            nxt=f'{y+(m==12):04d}-{1 if m==12 else m+1:02d}'
            cohorts[first][0]+=1
            cohorts[first][1]+=nxt in values
        for row in self.result['q07_cohort_return']:
            self.assertEqual([row['cohort_users'],row['returned_users']],cohorts[row['cohort_month']])

    def test_rfm_single_buyers_are_never_high_frequency(self):
        single=self.db.execute('SELECT COUNT(*) FROM (SELECT c.customer_unique_id FROM valid_orders o JOIN customers c USING(customer_id) JOIN order_items i USING(order_id) GROUP BY c.customer_unique_id HAVING COUNT(DISTINCT o.order_id)=1)').fetchone()[0]
        self.assertEqual(single,sum(r['users'] for r in self.result['q08_rfm'] if r['f_score']==1))

    def test_html_and_export_share_corrected_kpi(self):
        html=(ROOT/'dashboard/index.html').read_text(encoding='utf-8')
        self.assertIn('38.21%',html)
        with (ROOT/'dashboard/tableau/kpi_summary.csv').open(encoding='utf-8-sig',newline='') as f:
            row=next(csv.DictReader(f))
        self.assertEqual(int(row['customers']),self.result['q02_repeat_users'][0]['total_users'])
        self.assertEqual(float(row['late_delivery_bad_review_pct']),self.result['q09_delivery_vs_review'][3]['bad_review_pct'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
