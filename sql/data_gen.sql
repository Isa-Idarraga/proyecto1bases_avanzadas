-- =============================================
-- EAFITSHOP - Generación de Datos Masivos
-- =============================================

-- Extensión para datos aleatorios
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================
-- 100,000 Clientes
-- =============================================
INSERT INTO customer (first_name, last_name, email, phone, city)
SELECT
    left(md5(i::text), 8),
    left(md5((i*2)::text), 10),
    'user' || i || '@mail.com',
    '300' || lpad((random()*9999999)::int::text, 7, '0'),
    (ARRAY['Medellín','Bogotá','Cali','Barranquilla','Cartagena'])[ceil(random()*5)::int]
FROM generate_series(1, 100000) AS i;

-- =============================================
-- 10,000 Productos
-- =============================================
INSERT INTO product (name, category, price, stock)
SELECT
    'Producto ' || i,
    (ARRAY['Electrónica','Ropa','Hogar','Deportes','Libros'])[ceil(random()*5)::int],
    round((random() * 1000000 + 5000)::numeric, 2),
    (random() * 1000)::int
FROM generate_series(1, 10000) AS i;

-- =============================================
-- 1,000,000 Órdenes
-- =============================================
INSERT INTO orders (customer_id, status, total, created_at)
SELECT
    (random() * 99999 + 1)::int,
    (ARRAY['pending','completed','cancelled','refunded'])[ceil(random()*4)::int],
    round((random() * 5000000)::numeric, 2),
    NOW() - (random() * interval '3 years')
FROM generate_series(1, 1000000) AS i;

-- =============================================
-- 3,000,000 Items de Órdenes
-- =============================================
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT
    (random() * 999999 + 1)::int,
    (random() * 9999 + 1)::int,
    (random() * 10 + 1)::int,
    round((random() * 1000000 + 5000)::numeric, 2)
FROM generate_series(1, 3000000) AS i;

-- =============================================
-- 1,000,000 Pagos
-- =============================================
INSERT INTO payment (order_id, method, status, amount, payment_date)
SELECT
    (random() * 999999 + 1)::int,
    (ARRAY['credit_card','debit_card','PSE','nequi','daviplata'])[ceil(random()*5)::int],
    (ARRAY['approved','rejected','pending'])[ceil(random()*3)::int],
    round((random() * 5000000)::numeric, 2),
    NOW() - (random() * interval '3 years')
FROM generate_series(1, 1000000) AS i;

-- =============================================
-- Verificar conteos
-- =============================================
SELECT 'customer'   AS tabla, COUNT(*) FROM customer
UNION ALL
SELECT 'product'    AS tabla, COUNT(*) FROM product
UNION ALL
SELECT 'orders'     AS tabla, COUNT(*) FROM orders
UNION ALL
SELECT 'order_item' AS tabla, COUNT(*) FROM order_item
UNION ALL
SELECT 'payment'    AS tabla, COUNT(*) FROM payment;