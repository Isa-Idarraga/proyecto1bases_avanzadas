-- =============================================
-- EAFITSHOP - Optimizaciones Incrementales
-- Aplicar una por una y medir después de cada
-- una con mediciones.sql
-- =============================================

-- =============================================
-- PASO 1: ÍNDICES EN FOREIGN KEYS
-- =============================================

-- orders.customer_id
CREATE INDEX idx_orders_customer_id 
ON orders(customer_id);

-- order_item.order_id
CREATE INDEX idx_order_item_order_id 
ON order_item(order_id);

-- order_item.product_id
CREATE INDEX idx_order_item_product_id 
ON order_item(product_id);

-- payment.order_id
CREATE INDEX idx_payment_order_id 
ON payment(order_id);

-- =============================================
-- PASO 2: ÍNDICES POR COLUMNAS DE FILTRO
-- =============================================

-- orders por status (Q6 pagos pendientes)
CREATE INDEX idx_orders_status 
ON orders(status);

-- orders por fecha (Q4 rango de fechas)
CREATE INDEX idx_orders_created_at 
ON orders(created_at);

-- payment por status
CREATE INDEX idx_payment_status 
ON payment(status);

-- product por category (Q3 ventas por categoría)
CREATE INDEX idx_product_category 
ON product(category);

-- =============================================
-- PASO 3: ÍNDICES COMPUESTOS
-- =============================================

-- orders por customer_id + status juntos
CREATE INDEX idx_orders_customer_status 
ON orders(customer_id, status);

-- payment por status + payment_date
CREATE INDEX idx_payment_status_date 
ON payment(status, payment_date DESC);

-- order_item por order_id + product_id
CREATE INDEX idx_order_item_order_product 
ON order_item(order_id, product_id);

-- =============================================
-- PASO 4: PARTICIONAMIENTO
-- Particionar orders por año
-- =============================================

-- Crear tabla particionada
CREATE TABLE orders_partitioned (
    order_id    SERIAL,
    customer_id INTEGER,
    status      VARCHAR(50) DEFAULT 'pending',
    total       NUMERIC(10,2),
    created_at  TIMESTAMP DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Crear particiones por año
CREATE TABLE orders_2022 
PARTITION OF orders_partitioned
FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');

CREATE TABLE orders_2023 
PARTITION OF orders_partitioned
FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE orders_2024 
PARTITION OF orders_partitioned
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE orders_2025 
PARTITION OF orders_partitioned
FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Migrar datos de orders a orders_partitioned
INSERT INTO orders_partitioned 
SELECT * FROM orders;

-- =============================================
-- PASO 5: REESCRITURA DE QUERIES
-- =============================================

-- Q3 original: join masivo
-- Q3 optimizada: usando CTE
EXPLAIN ANALYZE
WITH ventas AS (
    SELECT product_id,
           SUM(quantity * unit_price) AS total_ventas,
           COUNT(*) AS total_items
    FROM order_item
    GROUP BY product_id
)
SELECT p.category,
       SUM(v.total_items) AS total_items,
       SUM(v.total_ventas) AS total_ventas
FROM ventas v
JOIN product p ON p.product_id = v.product_id
GROUP BY p.category
ORDER BY total_ventas DESC;

-- Q5 original: GROUP BY masivo
-- Q5 optimizada: con LIMIT anticipado
EXPLAIN ANALYZE
WITH top_orders AS (
    SELECT customer_id,
           COUNT(*) AS total_ordenes,
           SUM(total) AS total_gastado
    FROM orders
    GROUP BY customer_id
    ORDER BY total_gastado DESC
    LIMIT 10
)
SELECT t.customer_id, c.first_name, c.last_name,
       t.total_ordenes, t.total_gastado
FROM top_orders t
JOIN customer c ON c.customer_id = t.customer_id
ORDER BY t.total_gastado DESC;

-- =============================================
-- PASO 6: PERFORMANCE TUNING DEL SERVIDOR
-- =============================================

-- Ver configuración actual
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW max_connections;
SHOW effective_cache_size;

-- Parámetros recomendados para EC2 con 4GB RAM
-- (modificar en docker-compose.yml o postgresql.conf)
/*
shared_buffers = 1GB                 -- 25% de RAM
work_mem = 32MB                      -- para sorts y hashes
maintenance_work_mem = 256MB         -- para VACUUM, índices
effective_cache_size = 3GB           -- 75% de RAM
max_connections = 100
random_page_cost = 1.1               -- si usas SSD
log_min_duration_statement = 500     -- loguear queries > 500ms
track_io_timing = on
*/

-- Actualizar estadísticas después de cargar datos
ANALYZE customer;
ANALYZE product;
ANALYZE orders;
ANALYZE order_item;
ANALYZE payment;

-- Ver estadísticas de uso de índices
SELECT schemaname, tablename, indexname,
       idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Ver tamaño de tablas e índices
SELECT
    relname AS tabla,
    pg_size_pretty(pg_total_relation_size(relid)) AS tamaño_total,
    pg_size_pretty(pg_relation_size(relid)) AS tamaño_tabla,
    pg_size_pretty(pg_total_relation_size(relid) - 
                   pg_relation_size(relid)) AS tamaño_indices
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;