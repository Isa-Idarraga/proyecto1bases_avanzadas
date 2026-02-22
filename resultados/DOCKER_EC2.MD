# Análisis de Optimización - EC2 con Docker (PostgreSQL)
## EafitShop - Comparación Antes vs Después por Query

> **Ambiente:** EC2 con Docker | PostgreSQL  
> **Dataset:** 1M customers, 100K products, 5M orders, 20M order_items, 4M payments  
> **Fecha:** Febrero 2026

---

## Resumen General

| Query | Descripción | Antes | Después | Mejora |
|-------|-------------|-------|---------|--------|
| Q1 | Ventas por ciudad en un año | 3147 ms | 2999 ms | 5% |
| Q2 | Top productos vendidos | 42216 ms | 20803 ms | **51%** |
| Q3 | Últimas órdenes de un cliente | 1610 ms | 0.166 ms | **99.99%** |
| Q4 | LIKE con comodín inicial | 1.352 ms | 1.635 ms | ~0% |
| Q5 | Función sobre columna en WHERE | 649 ms | 75.593 ms | **88%** |
| Q6 | Join + filtro por status | 7228 ms | 6626 ms | 8% |

---

## Q1 - Ventas por ciudad en un año

```sql
SELECT c.city, SUM(o.total_amount) AS total_sales
FROM customer c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_date >= TIMESTAMPTZ '2023-01-01'
  AND o.order_date <  TIMESTAMPTZ '2024-01-01'
GROUP BY c.city
ORDER BY total_sales DESC;
```

### Sin optimizar
| Nodo | Detalle |
|------|---------|
| Scan principal | Parallel Seq Scan on orders |
| Rows removed | 1.333.233 filas descartadas |
| Buffers read | 41667 páginas leídas desde disco |
| Join | Hash Inner Join |
| Paralelismo | Parallel workers activos |

![alt text](imagenes_docker\image.png)

**⏱ Tiempo total: 3147 ms**  
**Problema:** Lectura completa de orders sin índice en `order_date`. Alto costo de I/O leyendo millones de páginas para luego descartar la mayoría por el filtro de fechas.

---

### Optimizado
**Optimización aplicada:**
```sql
CREATE INDEX idx_orders_orderdate_customer 
ON orders (order_date, customer_id);
```

| Nodo | Detalle |
|------|---------|
| Scan principal | **Parallel Index Only Scan** |
| Heap Fetches | **0** (eliminados completamente) |
| Buffers | shared hit=1128 read=11065 |
| Join | Hash Inner Join |

![alt text](image-6.png)

**⏱ Tiempo total: 2999 ms → Mejora del 5%**  
**Clave:** PostgreSQL ya no lee la tabla orders, solo el índice (más pequeño), eliminando todos los heap fetches.  
**Cuello restante:** El filtro del año devuelve ~1M registros que igual hay que procesar en el join y la agregación, por eso la mejora es limitada.

---

## Q2 - Top productos vendidos

### Sin optimizar
```sql
SELECT p.name, SUM(oi.quantity) AS total_sold
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
GROUP BY p.name
ORDER BY total_sold DESC
LIMIT 10;
```

| Nodo | Detalle |
|------|---------|
| Scan principal | Parallel Seq Scan on order_item |
| Filas leídas | ~6.6M × 3 workers = **~20M filas** |
| Buffers read | 166.667 páginas desde disco |
| Join | Hash Inner Join (~28.4 s) |

![alt text](image-1.png)

**⏱ Tiempo total: 42216 ms**  
**Problema:** Lectura completa de 20M filas de order_item antes del join. El join recibe un volumen masivo de datos.

---

### Optimizado
**Optimización aplicada:** Reescritura del query — agrega primero, luego hace join

```sql
SELECT p.name, s.total_sold
FROM (
    SELECT product_id, SUM(quantity) AS total_sold
    FROM order_item
    GROUP BY product_id
) s
JOIN product p ON p.product_id = s.product_id
ORDER BY s.total_sold DESC
LIMIT 10;
```

| Nodo | Detalle |
|------|---------|
| Orden lógico | order_item → **aggregate** → join product |
| Buffers read | **847** (vs 166.667 antes) |
| JIT | Activado (Functions: 43, Total 135 ms) |

![alt text](image-7.png)

**⏱ Tiempo total: 20803 ms → Mejora del 51%**  
**Clave:** Al agregar primero, el join recibe solo 100K filas (una por producto) en lugar de 20M. La reducción de buffers de 166.667 a 847 confirma el impacto.  
**Conclusión:** La optimización lógica (reescritura) tuvo mayor impacto que cualquier índice en este caso.

---

## Q3 - Últimas órdenes de un cliente

### Sin optimizar
```sql
SELECT *
FROM orders
WHERE customer_id = 12345
ORDER BY order_date DESC
LIMIT 20;
```

| Nodo | Detalle |
|------|---------|
| Scan | Parallel Seq Scan on orders |
| Filas descartadas | 1.666.663 filas removidas por filtro |
| Buffers read | 41.667 páginas |
| Sort | Sort costoso por order_date DESC |

![alt text](image-2.png)

**⏱ Tiempo total: 1610 ms**  
**Problema:** El motor revisa TODA la tabla para encontrar las órdenes de un solo cliente, luego ordena las pocas filas encontradas.

---

### Optimizado
**Optimización aplicada:**
```sql
CREATE INDEX idx_orders_customer_date 
ON orders (customer_id, order_date DESC);
```

| Nodo | Detalle |
|------|---------|
| Scan | **Index Scan** |
| Buffers | hit=3 read=14 (solo 17 páginas!) |
| Sort | **Eliminado** |
| Heap Fetches | Mínimos |

![alt text](image-8.png)

**⏱ Tiempo total: 0.166 ms → Mejora del 99.99%**  
**Clave:** El índice compuesto satisface simultáneamente el filtro por `customer_id` y el ordenamiento por `order_date DESC`, sin necesidad de leer la tabla ni hacer Sort. De 41.667 páginas a solo 17.

---

## Q4 - LIKE con comodín inicial

### Sin optimizar
```sql
SELECT *
FROM product
WHERE name ILIKE '%42%'
LIMIT 50;
```

| Nodo | Detalle |
|------|---------|
| Scan | Seq Scan on product |
| Problema | `%texto%` no puede usar índice B-Tree |

![alt text](image-3.png)

**⏱ Tiempo total: 1.352 ms**  
**Problema:** El comodín inicial `%` impide que el motor sepa dónde comienza la cadena, bloqueando el uso de índices B-Tree.

---

### Optimizado
**Optimización aplicada:**
```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_product_name_trgm 
ON product USING gin (name gin_trgm_ops);
```

| Nodo | Detalle |
|------|---------|
| Scan | Seq Scan (sigue igual) |
| Buffers | hit=1 |

![alt text](image-9.png)

**⏱ Tiempo total: 1.635 ms → Sin mejora visible**  
**Nota:** El optimizador sigue eligiendo Seq Scan porque la tabla product es pequeña (100K filas). El índice GIN descompone cada nombre en trigramas de 3 caracteres y está listo para cuando la tabla crezca a millones de registros, momento en que el motor lo adoptará automáticamente.

---

## Q5 - Función sobre columna en WHERE (anti-pattern)

### Sin optimizar
```sql
SELECT count(*)
FROM orders
WHERE date_trunc('day', order_date) = TIMESTAMPTZ '2023-11-15';
```

| Nodo | Detalle |
|------|---------|
| Scan | Parallel Seq Scan on orders |
| Filas descartadas | 1.665.739 por filtro |
| Por qué falla | `date_trunc()` sobre columna rompe el índice B-Tree |

![alt text](image-4.png)

**⏱ Tiempo total: 649 ms**  
**Problema:** Aplicar una función sobre la columna en el WHERE hace el predicado no sargable — el motor calcula `date_trunc()` fila por fila en lugar de usar el índice.

---

### Optimizado
**Optimización aplicada:** Reescritura del WHERE en forma de rango + índice en order_date

```sql
CREATE INDEX idx_orders_orderdate ON orders (order_date);

-- Query reescrito (sargable)
SELECT count(*)
FROM orders
WHERE order_date >= TIMESTAMPTZ '2023-11-15 00:00:00'
  AND order_date <  TIMESTAMPTZ '2023-11-16 00:00:00';
```

| Nodo | Detalle |
|------|---------|
| Scan | **Index Scan** |
| Buffers | hit=5661 read=2675 |
| Heap Fetches | 0 |

![alt text](image-10.png)

**⏱ Tiempo total: 75.593 ms → Mejora del 88%**  
**Clave:** Al reescribir como rango, el predicado se vuelve sargable y PostgreSQL puede usar el índice B-Tree directamente. De leer millones de filas a leer solo las del día requerido.

---

## Q6 - Join + filtro por status

### Sin optimizar
```sql
SELECT o.status, count(*) AS n
FROM orders o
JOIN payment p ON p.order_id = o.order_id
WHERE p.payment_status = 'APPROVED'
GROUP BY o.status
ORDER BY n DESC;
```

| Nodo | Detalle |
|------|---------|
| Scan payment | Parallel Seq Scan |
| Scan orders | Parallel Seq Scan |
| Filas descartadas | ~1.000.275 por worker en payment |
| Join | Parallel Hash Join |

![alt text](image-5.png)

**⏱ Tiempo total: 7228 ms**  
**Problema:** Seq Scan completo en ambas tablas. Sin índice en `payment_status` ni en la FK `order_id`.

---

### Optimizado
**Optimización aplicada:**
```sql
CREATE INDEX idx_payment_status_order 
ON payment (payment_status, order_id);
```

| Nodo | Detalle |
|------|---------|
| Scan payment | **Parallel Index Only Scan** |
| Scan orders | Parallel Seq Scan (sigue igual) |
| Buffers | hit=12 |
| JIT | Activado (Functions: 48, Total 39.595 ms) |

![alt text](image-11.png)

**⏱ Tiempo total: 6626 ms → Mejora del 8%**  
**Clave:** El índice en payment fue adoptado correctamente (Index Only Scan), reduciendo el acceso a esa tabla.  
**Cuello restante:** El filtro `payment_status = 'APPROVED'` no es selectivo (~33% de registros). El volumen que llega al join sigue siendo enorme, y orders sigue con Seq Scan siendo el nuevo cuello de botella.

---

## Conclusiones Generales

### Lo que funcionó muy bien
- **Q3** fue la mejora más espectacular (99.99%): un índice compuesto correcto eliminó el Seq Scan, el Sort y redujo los buffers de 41.667 a 17 páginas. Demuestra que el índice adecuado puede cambiar radicalmente el plan.
- **Q5** con reescritura sargable bajó 88%: el problema no era falta de índices sino el anti-pattern de función sobre columna en el WHERE.
- **Q2** mejoró 51% solo con reescritura, sin agregar ningún índice.

### Lo que funcionó parcialmente
- **Q1** solo mejoró 5% porque aunque eliminó el heap fetch, el volumen de ~1M filas que devuelve el filtro anual sigue siendo el cuello de botella en el join y la agregación.
- **Q6** mejoró solo 8% porque el filtro no es selectivo y el cuello se trasladó a orders.

### Lo que no mejoró
- **Q4** el índice GIN está creado y preparado, pero la tabla product es aún pequeña para que el optimizador lo adopte.

### Lecciones aprendidas
- La optimización física (índices) y la optimización lógica (reescritura) son complementarias — Q2 y Q5 lo demuestran.
- Crear un índice no garantiza que el optimizador lo use: depende del tamaño de la tabla, la selectividad del filtro y el costo estimado.
- El EXPLAIN ANALYZE es la herramienta clave: permite identificar exactamente dónde está el cuello de botella antes de decidir la estrategia de optimización.