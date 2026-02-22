# Proyecto 1 - Bases de Datos Avanzadas
## EafitShop - PostgreSQL Performance Tuning

Universidad EAFIT  
Curso: Bases de Datos Avanzadas  
Entrega: Semana 5 | Sustentación: Semana 6

---

## Descripción

Caso de estudio sobre optimización de rendimiento en PostgreSQL 
usando el sistema EafitShop, un e-commerce OLTP con millones de 
registros. Se aplican técnicas de indexación, particionamiento, 
reescritura de queries y performance tuning del servidor.

---

## Objetivos

- Establecer una línea base de rendimiento con EXPLAIN / EXPLAIN ANALYZE
- Aplicar técnicas de optimización de forma incremental
- Comparar el rendimiento antes y después de cada optimización
- Desplegar en EC2 (Docker) y AWS RDS

---

## Estructura del repositorio

```
proyecto1bases_avanzadas/
│
├── sql/
│   ├── shema.sql           # Esquema de la base de datos
│   ├── data_gen_small.sql  # Generación de datos (conjunto pequeño)
│   ├── data_gen_big.sql    # Generación de datos (conjunto grande)
│   ├── queries_base.sql    # Queries línea base
│   ├── optimizaciones.sql  # Índices, particiones, rewrites
│   └── mediciones.sql      # Scripts de medición
├── infra/
│   ├── docker-compose.yml  # Configuración Docker + PostgreSQL 15
│   └── rds_setup.md        # Instrucciones AWS RDS
├── resultados/
│   ├── AWS_RDS.md          # Resultados y métricas en AWS RDS
│   └── DOCKER_EC2.MD       # Resultados y métricas en Docker/EC2
└── README.md
```

---

## Tecnologías

- PostgreSQL 15+
- Docker
- AWS EC2
- AWS RDS
- pgbench

---

## Cómo replicar el proyecto

> **Requisitos previos:** Docker Desktop instalado y en ejecución.

### 1. Clonar el repositorio

```bash
git clone https://github.com/Isa-Idarraga/proyecto1bases_avanzadas
cd proyecto1bases_avanzadas
```

### 2. Levantar la base de datos con Docker

```bash
cd infra
docker-compose up -d
```

Esto levanta un contenedor llamado `eafitshop_db` con PostgreSQL 15 expuesto en el puerto **5433**.  
Verifica que esté corriendo:

```bash
docker ps
```

### 3. Crear el esquema y cargar datos

```bash
psql -h localhost -p 5433 -U eafitshop -d eafitshop -f sql/shema.sql
```

Contraseña: `eafitshop123`

Carga el dataset (elige según el entorno):

```bash
# Dataset pequeño - para pruebas rápidas
psql -h localhost -p 5433 -U eafitshop -d eafitshop -f sql/data_gen_small.sql

# Dataset grande - para pruebas de rendimiento reales
psql -h localhost -p 5433 -U eafitshop -d eafitshop -f sql/data_gen_big.sql
```

---

### 4. Ejecutar las queries BASE una a una y registrar resultados

Conéctate a la base de datos:

```bash
psql -h localhost -p 5433 -U eafitshop -d eafitshop
```

Ejecuta cada query del archivo `sql/queries_base.sql` **una por una** y guarda el plan que devuelve el `EXPLAIN (ANALYZE, BUFFERS)`:

| Query | Descripción |
|-------|-------------|
| **Q1** | Ventas por ciudad en un año — join `customer` + `orders` sin índices |
| **Q2** | Top 10 productos más vendidos — agregación masiva sobre `order_item` |
| **Q3** | Últimas órdenes de un cliente — filtro + sort sin índice |
| **Q4** | Búsqueda `ILIKE '%texto%'` — patrón no sargable |
| **Q5** | Conteo por fecha con `date_trunc` — función sobre columna en `WHERE` |
| **Q6** | Join `orders` + `payment` filtrado por `payment_status` sin índices |

De cada query anota:
- **Plan de ejecución** (tipo de scan: Seq Scan, Index Scan, etc.)
- **Tiempo total** (`Execution Time`)
- **Filas estimadas vs reales** (`rows=` estimado vs `actual rows=`)
- **Buffers** (hits vs reads)

---

### 5. Aplicar las optimizaciones (índices)

Ejecuta los **PASO 1 y PASO 2** del archivo `sql/optimizaciones.sql`.  
Esto crea todos los índices básicos y adicionales sobre la tabla `orders`, `order_item`, `product` y `payment`:

```sql
-- Dentro de psql, ejecuta bloque por bloque o copia los CREATE INDEX
-- correspondientes al PASO 1 y PASO 2 de sql/optimizaciones.sql
```

### 6. Aplicar el particionamiento

Ejecuta el **PASO 3** del archivo `sql/optimizaciones.sql`.  
Esto crea la tabla `orders_partitioned` particionada por año (2021–2026) y migra los datos:

```sql
-- Ejecuta el bloque PASO 3 de sql/optimizaciones.sql
-- Al final verifica la distribución con la query SELECT tableoid::regclass...
```

---

### 7. Ejecutar las queries OPTIMIZADAS una a una y registrar resultados

Con los índices y particiones aplicados, ejecuta cada query optimizada del archivo `sql/optimizaciones.sql` **una por una**:

| Query | Optimización aplicada |
|-------|----------------------|
| **Q1 opt** | `idx_orders_covering_q1` — Index Only Scan + partition pruning en `orders_partitioned` |
| **Q2 opt** | Reescritura: subquery agrega primero, luego hace join — usa `idx_orderitem_product_qty` |
| **Q3 opt** | `idx_orders_covering_q3` — Index Only Scan sin Sort extra |
| **Q4 opt** | `idx_product_name_trgm` — índice GIN trigram para ILIKE |
| **Q5 opt** | Reescritura a rango sargable — usa `idx_orders_orderdate` y pruning en `orders_partitioned` |
| **Q6 opt** | `idx_payment_status_order` + `idx_orders_status` — Index Scan en ambas tablas |

Anota los mismos datos que en el paso 4 para poder comparar directamente.

---

### 8. Comparar resultados

Con los datos recolectados en los pasos 4 y 7, compara para cada query:

- Reducción en tiempo de ejecución
- Cambio de Seq Scan → Index Scan / Index Only Scan
- Diferencia en buffers leídos
- Precisión de la estimación de filas del planner

Los resultados documentados están en la carpeta `resultados/`.

---

### (Opcional) Detener el entorno

```bash
docker-compose down
```

---

## Integrantes

- Isabella Idárraga
- Juan José Rodríguez
- Nicolás Saldarriaga

---

## Uso de IA

Este proyecto utilizó herramientas de IA (Claude, ChatGPT) como 
apoyo en la investigación y documentación, 
fortaleciendo el aprendizaje del equipo.
