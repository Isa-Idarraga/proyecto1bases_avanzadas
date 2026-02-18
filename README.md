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
├── docs/                  # Informe técnico y documentación
├── sql/
│   ├── schema.sql         # Esquema de la base de datos
│   ├── data_gen.sql       # Scripts de generación de datos
│   ├── queries_base.sql   # Queries línea base
│   ├── optimizaciones.sql # Índices, particiones, rewrites
│   └── mediciones.sql     # Scripts de medición
├── infra/
│   ├── docker-compose.yml # Configuración Docker + PostgreSQL
│   └── rds_setup.md       # Instrucciones AWS RDS
├── resultados/            # Capturas, métricas, planes EXPLAIN
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

### 1. Clonar el repositorio
git clone https://github.com/Isa-Idarraga/proyecto1bases_avanzadas

### 2. Levantar la base de datos con Docker
cd infra
docker-compose up -d

### 3. Crear el esquema y cargar datos
psql -h localhost -U postgres -f sql/schema.sql
psql -h localhost -U postgres -f sql/data_gen.sql

### 4. Ejecutar mediciones
psql -h localhost -U postgres -f sql/mediciones.sql

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
