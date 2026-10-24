-- Warehouse Returns and Refurbishment Tracking System
-- 00_create_database.sql: Initializes the database schema.
-- Target DBMS: MySQL 8.0.16+ / MySQL 8.4+ with InnoDB.

CREATE DATABASE IF NOT EXISTS warehouse_returns_demo
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE warehouse_returns_demo;
