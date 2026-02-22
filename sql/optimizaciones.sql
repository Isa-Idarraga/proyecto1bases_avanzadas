-- ============================================================
-- EAFITSHOP - OPTIMIZACIONES COMPLETAS EN AWS RDS
-- Incluye: índices básicos, índices adicionales, 
--          reescrituras y particionamiento
-- ============================================================

-- ============================================================
-- PASO 1: OPTIMIZACIONES BÁSICAS (igual que EC2)
-- ============================================================

-- Q1: Índice compuesto para filtro por fecha + join
CREATE INDEX idx_orders_orderdate_customer 
ON orders (order_date, customer_id);

-- Q3: Índice compuesto con orden para dashboard cliente
CREATE INDEX idx_orders_customer_date 
ON orders (customer_id, order_date DESC);

-- Q4: GIN + pg_trgm para búsquedas ILIKE
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_product_name_trgm 
ON product USING gin (name gin_trgm_ops);

-- Q5: Índice en order_date para reescritura de rango
CREATE INDEX idx_orders_orderdate 
ON orders (order_date);

-- Q6: Índice compuesto en payment para filtro + join
CREATE INDEX idx_payment_status_order 
ON payment (payment_status, order_id);

-- ============================================================
-- PASO 2: OPTIMIZACIONES ADICIONALES
-- ============================================================

-- Q1: Índice covering para evitar heap fetch
CREATE INDEX idx_orders_covering_q1
ON orders (order_date, customer_id, total_amount);

-- Q2: Índices en FK de order_item para join y agregación
CREATE INDEX idx_orderitem_product_id
ON order_item (product_id);

CREATE INDEX idx_orderitem_product_qty
ON order_item (product_id, quantity);

-- Q3: Índice covering completo
CREATE INDEX idx_orders_covering_q3
ON orders (customer_id, order_date DESC, status, total_amount);

-- Q5: Índice funcional para date_trunc
CREATE INDEX idx_orders_date_trunc
ON orders (date_trunc('day', order_date));

-- Q6: Índices adicionales en orders y payment
CREATE INDEX idx_orders_status
ON orders (status);

CREATE INDEX idx_payment_order_id
ON payment (order_id);

-- ============================================================
-- PASO 3: PARTICIONAMIENTO DE ORDERS POR AÑO
-- ============================================================

CREATE TABLE orders_partitioned (
    order_id      BIGINT,
    customer_id   BIGINT NOT NULL,
    order_date    TIMESTAMPTZ NOT NULL,
    status        order_status NOT NULL,
    total_amount  NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2021 PARTITION OF orders_partitioned
FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');

CREATE TABLE orders_2022 PARTITION OF orders_partitioned
FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');

CREATE TABLE orders_2023 PARTITION OF orders_partitioned
FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE orders_2024 PARTITION OF orders_partitioned
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE orders_2025 PARTITION OF orders_partitioned
FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

CREATE TABLE orders_2026 PARTITION OF orders_partitioned
FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

INSERT INTO orders_partitioned SELECT * FROM orders;

-- Verificar distribución de particiones
SELECT tableoid::regclass AS particion, count(*) AS filas
FROM orders_partitioned 
GROUP BY tableoid::regclass
ORDER BY particion;


-- ============================================================
-- QUERIES OPTIMIZADOS - EJECUTAR CON EXPLAIN (ANALYZE, BUFFERS)
-- ============================================================

-- ------------------------------------------------------------
-- Q1 OPTIMIZADO: Ventas por ciudad en un año
-- Usa: idx_orders_covering_q1 (Index Only Scan)
-- Sobre tabla PARTICIONADA para partition pruning
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.city, SUM(o.total_amount) AS total_sales
FROM customer c
JOIN orders_partitioned o ON c.customer_id = o.customer_id
WHERE o.order_date >= TIMESTAMPTZ '2023-01-01'
  AND o.order_date <  TIMESTAMPTZ '2024-01-01'
GROUP BY c.city
ORDER BY total_sales DESC;

-- ------------------------------------------------------------
-- Q2 OPTIMIZADO: Top productos vendidos
-- Reescritura: agrega PRIMERO, luego hace join
-- Usa: idx_orderitem_product_qty
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.name, s.total_sold
FROM (
    SELECT product_id, SUM(quantity) AS total_sold
    FROM order_item
    GROUP BY product_id
) s
JOIN product p ON p.product_id = s.product_id
ORDER BY s.total_sold DESC
LIMIT 10;

-- ------------------------------------------------------------
-- Q3 OPTIMIZADO: Últimas órdenes de un cliente
-- Usa: idx_orders_covering_q3 (Index Only Scan sin Sort)
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE customer_id = 12345
ORDER BY order_date DESC
LIMIT 20;

-- ------------------------------------------------------------
-- Q4 OPTIMIZADO: LIKE con comodín inicial
-- Usa: idx_product_name_trgm (GIN trigram)
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM product
WHERE name ILIKE '%42%'
LIMIT 50;

-- ------------------------------------------------------------
-- Q5 OPTIMIZADO: Conteo por fecha
-- Reescritura: WHERE en forma de rango (sargable)
-- Usa: idx_orders_orderdate (Index Only Scan)
-- También funciona con idx_orders_date_trunc
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM orders
WHERE order_date >= TIMESTAMPTZ '2023-11-15 00:00:00'
  AND order_date <  TIMESTAMPTZ '2023-11-16 00:00:00';

-- Con tabla particionada (partition pruning a orders_2023):
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM orders_partitioned
WHERE order_date >= TIMESTAMPTZ '2023-11-15 00:00:00'
  AND order_date <  TIMESTAMPTZ '2023-11-16 00:00:00';

-- ------------------------------------------------------------
-- Q6 OPTIMIZADO: Join + filtro por status
-- Usa: idx_payment_status_order + idx_orders_status
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.status, count(*) AS n
FROM orders o
JOIN payment p ON p.order_id = o.order_id
WHERE p.payment_status = 'APPROVED'
GROUP BY o.status
ORDER BY n DESC;