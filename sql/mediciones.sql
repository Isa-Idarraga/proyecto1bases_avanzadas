-- =============================================
-- EAFITSHOP - Mediciones Incrementales
-- Correr después de cada paso de optimización
-- y guardar los resultados en la tabla
-- mediciones_resultados
-- =============================================

-- Tabla para guardar resultados
CREATE TABLE IF NOT EXISTS mediciones_resultados (
    id          SERIAL PRIMARY KEY,
    etapa       VARCHAR(100),  -- 'linea_base', 'paso1', 'paso2', etc
    query_id    VARCHAR(10),   -- 'Q1', 'Q2', etc
    tiempo_ms   NUMERIC(10,3),
    tipo_scan   VARCHAR(100),  -- 'Seq Scan', 'Index Scan', etc
    costo       NUMERIC(10,2),
    notas       TEXT,
    fecha       TIMESTAMP DEFAULT NOW()
);

-- =============================================
-- MEDIR Q1 - Órdenes de un cliente
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.order_id, o.status, o.total, o.created_at
FROM orders o
WHERE o.customer_id = 500;

-- =============================================
-- MEDIR Q2 - Detalle completo de una orden
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.order_id, c.first_name, c.last_name,
       p.name AS product, oi.quantity, oi.unit_price
FROM orders o
JOIN customer c ON c.customer_id = o.customer_id
JOIN order_item oi ON oi.order_id = o.order_id
JOIN product p ON p.product_id = oi.product_id
WHERE o.order_id = 1000;

-- =============================================
-- MEDIR Q3 - Total ventas por categoría
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT p.category,
       COUNT(oi.item_id) AS total_items,
       SUM(oi.quantity * oi.unit_price) AS total_ventas
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.category
ORDER BY total_ventas DESC;

-- =============================================
-- MEDIR Q4 - Órdenes por rango de fechas
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*), SUM(total)
FROM orders
WHERE created_at BETWEEN '2023-01-01' AND '2023-12-31';

-- =============================================
-- MEDIR Q5 - Clientes con más compras
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT c.customer_id, c.first_name, c.last_name,
       COUNT(o.order_id) AS total_ordenes,
       SUM(o.total) AS total_gastado
FROM customer c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_gastado DESC
LIMIT 10;

-- =============================================
-- MEDIR Q6 - Pagos pendientes
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT p.payment_id, o.order_id, c.email,
       p.amount, p.method, p.payment_date
FROM payment p
JOIN orders o ON o.order_id = p.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE p.status = 'pending'
ORDER BY p.payment_date DESC
LIMIT 100;

-- =============================================
-- MEDIR Q7 - Productos más vendidos
-- =============================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT p.product_id, p.name, p.category,
       SUM(oi.quantity) AS unidades_vendidas,
       SUM(oi.quantity * oi.unit_price) AS ingresos
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.name, p.category
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- =============================================
-- MONITOREO DEL SERVIDOR
-- =============================================

-- Queries más lentas actualmente
SELECT query, calls, 
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS promedio_ms,
       round(stddev_exec_time::numeric, 2) AS desviacion_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Uso de caché (hit rate debe ser > 99%)
SELECT 
    sum(heap_blks_read) AS heap_read,
    sum(heap_blks_hit) AS heap_hit,
    round(sum(heap_blks_hit) * 100.0 / 
    nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) 
    AS cache_hit_rate
FROM pg_statio_user_tables;

-- Conexiones activas
SELECT state, COUNT(*) 
FROM pg_stat_activity 
GROUP BY state;

-- Tablas con más Seq Scans (candidatas a índices)
SELECT relname, seq_scan, seq_tup_read,
       idx_scan, idx_tup_fetch
FROM pg_stat_user_tables
ORDER BY seq_scan DESC;

-- =============================================
-- TABLA COMPARATIVA FINAL
-- Llenar manualmente con los resultados
-- =============================================
/*
| Query | Línea Base | Paso 1 | Paso 2 | Paso 3 | Paso 4 | Paso 5 | Paso 6 |
|-------|-----------|--------|--------|--------|--------|--------|--------|
| Q1    |           |        |        |        |        |        |        |
| Q2    |           |        |        |        |        |        |        |
| Q3    |           |        |        |        |        |        |        |
| Q4    |           |        |        |        |        |        |        |
| Q5    |           |        |        |        |        |        |        |
| Q6    |           |        |        |        |        |        |        |
| Q7    |           |        |        |        |        |        |        |

Etapas:
- Línea Base: sin ninguna optimización
- Paso 1: índices en FK
- Paso 2: índices en columnas de filtro
- Paso 3: índices compuestos
- Paso 4: particionamiento
- Paso 5: reescritura de queries
- Paso 6: performance tuning servidor
*/