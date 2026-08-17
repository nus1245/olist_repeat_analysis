DROP DATABASE IF EXISTS olist_db;
CREATE DATABASE olist_db;
USE olist_db;

SHOW GLOBAL VARIABLES LIKE 'local_infile';

SET GLOBAL local_infile = 1;

SHOW GLOBAL VARIABLES LIKE 'local_infile';
-- =========================================
-- 2) geolocation
-- =========================================

DROP TABLE IF EXISTS geolocation;
CREATE TABLE geolocation (
    zip_code_prefix CHAR(5) NOT NULL,
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),
    city VARCHAR(100),
    state VARCHAR(10)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_geolocation_dataset.csv'
INTO TABLE geolocation
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(zip_code_prefix, latitude, longitude, city, state);


-- =========================================
-- 3) customers
-- =========================================

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    zip_code_prefix CHAR(5) NOT NULL,
    city VARCHAR(100),
    state VARCHAR(10)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, customer_unique_id, zip_code_prefix, city, state);


-- =========================================
-- 4) sellers
-- =========================================

DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
    seller_id VARCHAR(50) PRIMARY KEY,
    zip_code_prefix INT,
    city VARCHAR(100),
    state VARCHAR(10)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_sellers_dataset.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(seller_id, zip_code_prefix, city, state);


-- =========================================
-- 5) orders
-- =========================================

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    status VARCHAR(30),
    purchase_timestamp DATETIME,
    approval_timestamp DATETIME,
    delivered_carrier_date DATETIME,
    delivered_customer_date DATETIME,
    estimated_delivery_date DATETIME,
    CONSTRAINT fk_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, status, purchase_timestamp, approval_timestamp,
 delivered_carrier_date, delivered_customer_date, estimated_delivery_date);


-- =========================================
-- 6) order_reviews
-- =========================================

DROP TABLE IF EXISTS order_reviews;
CREATE TABLE order_reviews (
    review_id VARCHAR(50),
    order_id VARCHAR(50) NOT NULL,
    rating INT,
    review_title TEXT,
    review_content TEXT,
    creation_timestamp DATETIME,
    answer_timestamp DATETIME,
    CONSTRAINT fk_reviews
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(review_id, order_id, rating, review_title, review_content,
 creation_timestamp, answer_timestamp);


-- =========================================
-- 7) order_payments
-- =========================================

DROP TABLE IF EXISTS order_payments;
CREATE TABLE order_payments (
    order_id VARCHAR(50) NOT NULL,
    payment_sequential INT,
    payment_type VARCHAR(30),
    payment_installments INT,
    payment_value DECIMAL(10,2),
    CONSTRAINT fk_payments
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_order_payments_dataset.csv'
INTO TABLE order_payments
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, payment_sequential, payment_type, payment_installments, payment_value);


-- =========================================
-- 8) category_names_english
-- =========================================

DROP TABLE IF EXISTS category_names_english;
CREATE TABLE category_names_english (
    product_category VARCHAR(100) PRIMARY KEY,
    product_category_eng VARCHAR(100)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/product_category_name_translation.csv'
INTO TABLE category_names_english
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_category, product_category_eng);


-- =========================================
-- 9) products
-- =========================================

DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category VARCHAR(100),
    name_length INT,
    description_length INT,
    photos_quantity INT,
    weight_g INT,
    length_cm INT,
    height_cm INT,
    width_cm INT,
    CONSTRAINT fk_category_eng
        FOREIGN KEY (product_category) REFERENCES category_names_english(product_category)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, product_category, name_length, description_length,
 photos_quantity, weight_g, length_cm, height_cm, width_cm);


-- =========================================
-- 10) order_items
-- =========================================

DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    order_id VARCHAR(50) NOT NULL,
    item_id INT,
    product_id VARCHAR(50) NOT NULL,
    seller_id VARCHAR(50) NOT NULL,
    shipping_limit_date DATETIME,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    CONSTRAINT fk_products
        FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT fk_orders
        FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_sellers
        FOREIGN KEY (seller_id) REFERENCES sellers(seller_id)
);

LOAD DATA LOCAL INFILE 'C:/Users/82103/Desktop/olist/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, item_id, product_id, seller_id, shipping_limit_date, price, freight_value);