# Análisis de Optimización - AWS RDS PostgreSQL
## EafitShop - Comparación Antes vs Después por Query

> **Ambiente:** AWS RDS PostgreSQL 15 | db.t3.micro | 40 GB  
> **Dataset:** 1M customers, 100K products, 5M orders, 20M order_items, 4M payments  

---

## Resumen General

| Query | Descripción | Antes | Después | Mejora |
|-------|-------------|-------|---------|--------|
| Q1 | Ventas por ciudad en un año | 6.422 s | 1.944 s | **70%** |
| Q2 | Top productos vendidos | 23.463 s | 13.313 s | **43%** |
| Q3 | Últimas órdenes de un cliente | 1.633 s | 0.285 ms | **99.98%** |
| Q4 | LIKE con comodín inicial | 0.246 s | 0.208 s | ~15% |
| Q5 | Función sobre columna en WHERE | 1.844 s | 0.310 s | **83%** |
| Q6 | Join + filtro por status | 6.867 s | 7.151 s | Sin mejora |

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
| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 603.114 ms | 11.06% |
| Gather Merge | 1 | 1054.13 ms | 19.33% |
| Hash | 1 | 131.742 ms | 2.42% |
| Hash Inner Join | 1 | 2773.276 ms | 50.85% |
| Seq Scan | 2 | 828.862 ms | 15.2% |
| Sort | 2 | 63.518 ms | 1.17% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| customer | Seq Scan | 152.8 ms |
| orders | Seq Scan | 676.061 ms |

<img width="1206" height="306" alt="image" src="https://github.com/user-attachments/assets/1229decc-bbf1-4b51-91e3-4206e9a0e8dd" />
**⏱ Tiempo total: 6.422 s**  
**Problema:** Seq Scan completo sobre 5M filas de orders. Sin índice en `order_date`.

---

### Optimizado
**Optimización aplicada:**
```sql
CREATE INDEX idx_orders_covering_q1 ON orders (order_date, customer_id, total_amount);

-- Query sobre tabla particionada
SELECT c.city, SUM(o.total_amount) AS total_sales
FROM customer c
JOIN orders_partitioned o ON c.customer_id = o.customer_id
WHERE o.order_date >= TIMESTAMPTZ '2023-01-01'
  AND o.order_date <  TIMESTAMPTZ '2024-01-01'
GROUP BY c.city
ORDER BY total_sales DESC;
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 133.226 ms | 8.69% |
| Gather Merge | 1 | 89.292 ms | 5.83% |
| Hash | 1 | 369.433 ms | 24.09% |
| Hash Inner Join | 1 | 698.385 ms | 45.54% |
| Seq Scan | 2 | 237.883 ms | 15.51% |
| Sort | 2 | 5.638 ms | 0.37% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| customer | Seq Scan | 133.5 ms |
| **orders_2023** | Seq Scan | 104.383 ms |

<img width="1206" height="393" alt="image" src="https://github.com/user-attachments/assets/3820e079-15d7-4e4f-9676-56e5490683ff" />

**⏱ Tiempo total: 1.944 s → Mejora del 70%**  
**Clave:** El partition pruning redujo el escaneo a solo `orders_2023` en lugar de las 5M filas completas.

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

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 8850.133 ms | 38.76% |
| Gather Merge | 1 | 400.152 ms | 1.76% |
| Hash | 1 | 166.668 ms | 0.73% |
| Hash Inner Join | 1 | 9991.328 ms | 43.76% |
| Seq Scan | 2 | 1562.986 ms | 6.85% |
| Sort | 2 | 1864.275 ms | 8.17% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| order_item | Seq Scan | 1533.365 ms |
| product | Seq Scan | 29.621 ms |


<img width="1206" height="432" alt="image" src="https://github.com/user-attachments/assets/89c59b04-e1a4-46a3-93e3-a904e382ca30" />

**⏱ Tiempo total: 23.463 s**  
**Problema:** 20M filas de order_item leídas completas antes del join.

---

### Optimizado
**Optimización aplicada:** Reescritura — agrega primero, luego hace join + índice en FK

```sql
CREATE INDEX idx_orderitem_product_id ON order_item (product_id);

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

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 9823.94 ms | 77.37% |
| Gather Merge | 1 | 157.392 ms | 1.24% |
| Index Scan | 1 | 29.576 ms | 0.24% |
| Merge Inner Join | 1 | 28.296 ms | 0.23% |
| Seq Scan | 1 | 2471.777 ms | 19.47% |
| Sort | 2 | 186.981 ms | 1.48% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| order_item | Seq Scan | 2471.777 ms |
| **product** | **Index Scan** | 29.576 ms |


<img width="1206" height="335" alt="image" src="https://github.com/user-attachments/assets/e446d5c3-a307-4dab-892e-6ee288f8fece" />

**⏱ Tiempo total: 13.313 s → Mejora del 43%**  
**Clave:** Al agregar primero, el join recibe solo 100K filas en lugar de 20M. Product ahora usa Index Scan.  
**Cuello de botella restante:** order_item sigue con Seq Scan — es inevitable porque hay que leer todos los registros para sumar las cantidades.

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

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Gather Merge | 1 | 91.088 ms | 7.58% |
| Limit | 1 | 0.007 ms | 0.01% |
| Seq Scan | 1 | 370.138 ms | 30.8% |
| Sort | 1 | 740.564 ms | 61.63% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| orders | Seq Scan | 370.138 ms |


<img width="1206" height="404" alt="image" src="https://github.com/user-attachments/assets/4b46d07d-c304-43c3-a70d-1d409148ea41" />

**⏱ Tiempo total: 1.633 s**  
**Problema:** Seq Scan completo + Sort costoso. Sin índice en `customer_id`.

---

### Optimizado
**Optimización aplicada:** Índice covering compuesto

```sql
CREATE INDEX idx_orders_covering_q3 
ON orders (customer_id, order_date DESC, status, total_amount);
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| **Index Scan** | 1 | 0.019 ms | 90.48% |
| Limit | 1 | 0.003 ms | 14.29% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| **orders** | **Index Scan** | 0.019 ms |


<img width="1206" height="541" alt="image" src="https://github.com/user-attachments/assets/9a187994-f987-42b0-9b91-14b7aa34601f" />

**⏱ Tiempo total: 0.285 ms → Mejora del 99.98%**  
**Clave:** El índice covering elimina el Seq Scan y el Sort de golpe. PostgreSQL va directo a las filas del cliente ya ordenadas.

---

## Q4 - LIKE con comodín inicial

### Sin optimizar
```sql
SELECT *
FROM product
WHERE name ILIKE '%42%'
LIMIT 50;
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Limit | 1 | 0.007 ms | 0.57% |
| Seq Scan | 1 | 1.239 ms | 99.52% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| product | Seq Scan | 1.239 ms |


<img width="1206" height="384" alt="image" src="https://github.com/user-attachments/assets/527b9c28-5eb7-447a-b7a7-b89676904a67" />

**⏱ Tiempo total: 0.246 s**  
**Problema:** ILIKE '%texto%' no puede usar índice B-tree. Sin solución con índices tradicionales.

---

### Optimizado
**Optimización aplicada:** Extensión pg_trgm + índice GIN

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_product_name_trgm ON product USING gin (name gin_trgm_ops);
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Limit | 1 | 0.007 ms | 0.58% |
| Seq Scan | 1 | 1.22 ms | 99.52% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| product | Seq Scan | 1.22 ms |


<img width="1206" height="619" alt="image" src="https://github.com/user-attachments/assets/58e3e8a3-5527-4355-b4d8-d0ca4c833ef8" />

**⏱ Tiempo total: 0.208 s → Mejora del ~15%**  
**Nota:** El optimizador sigue eligiendo Seq Scan porque la tabla product tiene 100K filas y es más económico leerla completa. El índice GIN está listo para cuando la tabla crezca a millones de registros y el optimizador lo adoptará automáticamente.

---

## Q5 - Función sobre columna en WHERE

### Sin optimizar
```sql
SELECT count(*)
FROM orders
WHERE date_trunc('day', order_date) = TIMESTAMPTZ '2023-11-15';
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 899.91 ms | 61.72% |
| Gather | 1 | 108.808 ms | 7.47% |
| Seq Scan | 1 | 449.351 ms | 30.82% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| orders | Seq Scan | 449.351 ms |


<img width="1206" height="442" alt="image" src="https://github.com/user-attachments/assets/ab544fd7-6f0c-485e-bb25-206d201f3b61" />

**⏱ Tiempo total: 1.844 s**  
**Problema:** `date_trunc()` sobre la columna rompe el uso de índices B-tree. Anti-pattern clásico.

---

### Optimizado
**Optimización aplicada:** Reescritura del WHERE en forma de rango (sargable) + índice en order_date

```sql
CREATE INDEX idx_orders_orderdate ON orders (order_date);

-- Query reescrito (sargable)
SELECT count(*)
FROM orders
WHERE order_date >= TIMESTAMPTZ '2023-11-15 00:00:00'
  AND order_date <  TIMESTAMPTZ '2023-11-16 00:00:00';
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 1 | 0.17 ms | 1.07% |
| **Index Only Scan** | 1 | 15.73 ms | 98.94% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| **orders** | **Index Only Scan** | 15.73 ms |
<img width="1206" height="584" alt="image" src="https://github.com/user-attachments/assets/3f7447ad-d9d4-4f22-9576-4e8acb17c9e7" />

**⏱ Tiempo total: 0.310 s → Mejora del 83%**  
**Clave:** Hacer el predicado sargable permite usar el índice. Heap Fetches = 0 (Index Only Scan).

**Bonus — con tabla particionada:**
```sql
SELECT count(*)
FROM orders_partitioned
WHERE order_date >= TIMESTAMPTZ '2023-11-15 00:00:00'
  AND order_date <  TIMESTAMPTZ '2023-11-16 00:00:00';
```

<img width="1206" height="259" alt="image" src="https://github.com/user-attachments/assets/e4cca63c-83ba-4899-9396-d4e9e0ee99e0" />

Partition pruning → solo accede a `orders_2023` → 0.572 s

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

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 90.537 ms | 1.45% |
| Gather Merge | 1 | 237.083 ms | 3.79% |
| Hash | 1 | 1385.116 ms | 22.11% |
| Hash Inner Join | 1 | 3290.123 ms | 52.51% |
| Seq Scan | 2 | 1257.988 ms | 20.08% |
| Sort | 2 | 5.593 ms | 0.09% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| orders | Seq Scan | 647.725 ms |
| payment | Seq Scan | 610.263 ms |


<img width="1206" height="425" alt="image" src="https://github.com/user-attachments/assets/4cc73fdb-7379-4f1d-a581-759efcf3b359" />

**⏱ Tiempo total: 6.867 s**  
**Problema:** Seq Scan en ambas tablas. Sin índice en `payment_status` ni en `order_id`.

---

### Optimizado
**Optimización aplicada:** Índice compuesto en payment + índice en orders.status

```sql
CREATE INDEX idx_payment_status_order ON payment (payment_status, order_id);
CREATE INDEX idx_orders_status ON orders (status);
CREATE INDEX idx_payment_order_id ON payment (order_id);
```

| Nodo | Count | Tiempo | % Query |
|------|-------|--------|---------|
| Aggregate | 2 | 70.652 ms | 1.05% |
| Gather Merge | 1 | 91.619 ms | 1.37% |
| Hash | 1 | 1464.458 ms | 21.74% |
| Hash Inner Join | 1 | 3574.199 ms | 53.06% |
| **Index Only Scan** | 1 | 690.24 ms | 10.25% |
| Seq Scan | 1 | 843.035 ms | 12.52% |

| Tabla | Tipo Scan | Tiempo |
|-------|-----------|--------|
| **payment** | **Index Only Scan** | 690.24 ms |
| orders | Seq Scan | 843.035 ms |

<img width="1206" height="288" alt="image" src="https://github.com/user-attachments/assets/1895f922-2646-4373-90bc-4b5507d2cf66" />

**⏱ Tiempo total: 7.151 s → Sin mejora significativa**  
**Análisis:** El índice en payment sí fue adoptado (Index Only Scan), pero el filtro `payment_status = 'APPROVED'` no es selectivo (~33% de registros). El cuello de botella se desplazó a orders que sigue con Seq Scan porque recibe demasiadas filas del join.

---

## Conclusiones Generales

### Lo que funcionó muy bien
- **Q3** fue la mejora más espectacular (99.98%) con un índice covering. Demuestra que el índice correcto puede eliminar completamente el problema.
- **Q5** con reescritura sargable eliminó el anti-pattern de función sobre columna logrando 83% de mejora.
- **Q1** con particionamiento logró partition pruning, accediendo solo a `orders_2023`.

### Lo que funcionó parcialmente
- **Q2** mejoró 43% con reescritura pero sigue siendo lento porque hay que leer los 20M registros de order_item para la agregación completa.
- **Q6** el índice en payment fue adoptado pero el problema real es el volumen de datos que llega al join.

### Lo que no mejoró visiblemente
- **Q4** el índice GIN está listo pero la tabla es aún pequeña para que el optimizador lo prefiera. Escalará automáticamente cuando la tabla crezca.

### Diferencias clave vs EC2 con Docker
- RDS no permite editar `postgresql.conf` directamente — se configura via **Parameter Groups**
- El particionamiento funciona igual en ambos ambientes
- RDS tiene latencia de red adicional por ser un servicio administrado
- RDS facilita backups, escalado y mantenimiento sin intervención manual
