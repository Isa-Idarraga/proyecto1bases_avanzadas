-- =============================================
-- EAFITSHOP - Queries Línea Base
-- Ejecutar con EXPLAIN ANALYZE para medir
-- rendimiento ANTES de optimizaciones
-- =============================================

-- =============================================
-- Q1: Órdenes de un cliente específico
-- (simula consulta operativa frecuente)
-- =============================================
EXPLAIN ANALYZE
SELECT o.order_id, o.status, o.total, o.created_at
FROM orders o
WHERE o.customer_id = 500;

-- =============================================
-- Q2: Detalle completo de una orden
-- (join sin índices en FK)
-- =============================================
EXPLAIN ANALYZE
SELECT o.order_id, c.first_name, c.last_name,
       p.name AS product, oi.quantity, oi.unit_price
FROM orders o
JOIN customer c ON c.customer_id = o.customer_id
JOIN order_item oi ON oi.order_id = o.order_id
JOIN product p ON p.product_id = oi.product_id
WHERE o.order_id = 1000;

-- =============================================
-- Q3: Total de ventas por categoría
-- (agregación masiva - reporte)
-- =============================================
EXPLAIN ANALYZE
SELECT p.category,
       COUNT(oi.item_id) AS total_items,
       SUM(oi.quantity * oi.unit_price) AS total_ventas
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.category
ORDER BY total_ventas DESC;

-- =============================================
-- Q4: Órdenes por rango de fechas
-- (consulta histórica sin partición)
-- =============================================
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(total)
FROM orders
WHERE created_at BETWEEN '2023-01-01' AND '2023-12-31';

-- =============================================
-- Q5: Clientes con más compras
-- (reporte que afecta OLTP)
-- =============================================
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, c.last_name,
       COUNT(o.order_id) AS total_ordenes,
       SUM(o.total) AS total_gastado
FROM customer c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_gastado DESC
LIMIT 10;

-- =============================================
-- Q6: Pagos pendientes con detalle
-- (operativa diaria)
-- =============================================
EXPLAIN ANALYZE
SELECT p.payment_id, o.order_id, c.email,
       p.amount, p.method, p.payment_date
FROM payment p
JOIN orders o ON o.order_id = p.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE p.status = 'pending'
ORDER BY p.payment_date DESC
LIMIT 100;

-- =============================================
-- Q7: Productos más vendidos
-- (reporte de inteligencia de negocio)
-- =============================================
EXPLAIN ANALYZE
SELECT p.product_id, p.name, p.category,
       SUM(oi.quantity) AS unidades_vendidas,
       SUM(oi.quantity * oi.unit_price) AS ingresos
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.name, p.category
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- =============================================
-- RESUMEN: Guardar tiempos de cada query
-- para comparar después de optimizar
-- =============================================
/*
| Query | Tiempo Línea Base | Tipo Scan | Costo |
|-------|------------------|-----------|-------|
| Q1    |                  |           |       |
| Q2    |                  |           |       |
| Q3    |                  |           |       |
| Q4    |                  |           |       |
| Q5    |                  |           |       |
| Q6    |                  |           |       |
| Q7    |                  |           |       |
*/