DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS category_translation;

CREATE TABLE customers (
  customer_id                TEXT PRIMARY KEY,
  customer_unique_id         TEXT NOT NULL,
  customer_zip_code_prefix   TEXT,
  customer_city              TEXT,
  customer_state             TEXT
);

CREATE TABLE orders (
  order_id                     TEXT PRIMARY KEY,
  customer_id                  TEXT NOT NULL,
  order_status                 TEXT NOT NULL,
  order_purchase_timestamp     TEXT,
  order_approved_at            TEXT,
  order_delivered_carrier_date TEXT,
  order_delivered_customer_date TEXT,
  order_estimated_delivery_date TEXT
);

CREATE TABLE order_items (
  order_id          TEXT NOT NULL,
  order_item_id     INTEGER NOT NULL,
  product_id        TEXT NOT NULL,
  seller_id         TEXT NOT NULL,
  shipping_limit_date TEXT,
  price             REAL,
  freight_value     REAL
);

CREATE TABLE order_payments (
  order_id             TEXT NOT NULL,
  payment_sequential   INTEGER,
  payment_type         TEXT,
  payment_installments INTEGER,
  payment_value        REAL
);

CREATE TABLE order_reviews (
  review_id               TEXT,
  order_id                TEXT NOT NULL,
  review_score            INTEGER,
  review_comment_title    TEXT,
  review_comment_message  TEXT,
  review_creation_date    TEXT,
  review_answer_timestamp TEXT
);

CREATE TABLE products (
  product_id                 TEXT PRIMARY KEY,
  product_category_name      TEXT,
  product_name_lenght        INTEGER,
  product_description_lenght INTEGER,
  product_photos_qty         INTEGER,
  product_weight_g           INTEGER,
  product_length_cm          INTEGER,
  product_height_cm          INTEGER,
  product_width_cm           INTEGER
);

CREATE TABLE sellers (
  seller_id              TEXT PRIMARY KEY,
  seller_zip_code_prefix TEXT,
  seller_city            TEXT,
  seller_state           TEXT
);

CREATE TABLE category_translation (
  product_category_name         TEXT PRIMARY KEY,
  product_category_name_english TEXT
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_purchase ON orders(order_purchase_timestamp);
CREATE INDEX idx_items_order ON order_items(order_id);
CREATE INDEX idx_items_product ON order_items(product_id);
CREATE INDEX idx_payments_order ON order_payments(order_id);
CREATE INDEX idx_reviews_order ON order_reviews(order_id);

-- One analytical order population for every monetary comparison.
CREATE VIEW valid_orders AS
SELECT * FROM orders WHERE order_status NOT IN ('canceled', 'unavailable');

-- Reviews are not unique by order. Keep the latest completed response, with
-- deterministic tie breakers, before joining to the order grain.
CREATE VIEW latest_reviews AS
SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY order_id ORDER BY review_answer_timestamp DESC,
    review_creation_date DESC, review_id DESC, rowid DESC
  ) AS review_rank
  FROM order_reviews
) WHERE review_rank = 1;
