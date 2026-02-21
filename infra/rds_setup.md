# Levantar el contenedor
docker-compose up -d

# Ver logs
docker-compose logs -f

# Conectarse a la base de datos
docker exec -it eafitshop_db psql -U eafitshop -d eafitshop

# Cargar el schema
docker exec -it eafitshop_db psql -U eafitshop -d eafitshop -f /docker-entrypoint-initdb.d/schema.sql

# Cargar los datos masivos (puede tardar unos minutos)
docker exec -it eafitshop_db psql -U eafitshop -d eafitshop -f /docker-entrypoint-initdb.d/data_gen.sql

# Detener el contenedor
docker-compose down