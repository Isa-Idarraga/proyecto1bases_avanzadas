-- =============================================
-- EAFITSHOP - Schema Base de Datos
-- =============================================

-- Clientes
CREATE TABLE customer (
    customer_id SERIAL PRIMARY KEY,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(150) UNIQUE NOT NULL,
    phone       VARCHAR(20),
    city        VARCHAR(100),
    created_at  TIMESTAMP DEFAULT NOW()
);

-- Productos
CREATE TABLE product (
    product_id   SERIAL PRIMARY KEY,
    name         VARCHAR(200) NOT NULL,
    category     VARCHAR(100),
    price        NUMERIC(10,2) NOT NULL,
    stock        INTEGER DEFAULT 0,
    created_at   TIMESTAMP DEFAULT NOW()
);

-- Órdenes
CREATE TABLE orders (
    order_id    SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customer(customer_id),
    status      VARCHAR(50) DEFAULT 'pending',
    total       NUMERIC(10,2),
    created_at  TIMESTAMP DEFAULT NOW()
);

-- Detalle de órdenes
CREATE TABLE order_item (
    item_id    SERIAL PRIMARY KEY,
    order_id   INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES product(product_id),
    quantity   INTEGER NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL
);

-- Pagos
CREATE TABLE payment (
    payment_id     SERIAL PRIMARY KEY,
    order_id       INTEGER REFERENCES orders(order_id),
    method         VARCHAR(50),
    status         VARCHAR(50) DEFAULT 'pending',
    amount         NUMERIC(10,2),
    payment_date   TIMESTAMP DEFAULT NOW()
);