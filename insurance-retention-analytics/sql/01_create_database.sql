/*
=============================================================================
  Script:      01_create_database.sql
  Proyecto:    Insurance Retention Analytics
  Descripción: Crea la base de datos InsuranceRetention si no existe.
               Diseñado para SQL Server 2019 (Developer / Express).
  Autor:       [Tu Nombre]
  Fecha:       2026
=============================================================================
*/

-- =============================================================
-- 1. Cambiar al contexto master para crear la BD
-- =============================================================
USE master;
GO

-- =============================================================
-- 2. Crear la base de datos solo si NO existe
--    (script idempotente — se puede ejecutar varias veces)
-- =============================================================
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'InsuranceRetention')
BEGIN
    PRINT '>> Creando base de datos InsuranceRetention...';

    CREATE DATABASE InsuranceRetention
    COLLATE Latin1_General_CI_AS;   -- Case-insensitive, acentos sensibles (estándar LATAM/Europa)

    PRINT '>> Base de datos creada exitosamente.';
END
ELSE
BEGIN
    PRINT '>> La base de datos InsuranceRetention ya existe. No se creó nada.';
END
GO

-- =============================================================
-- 3. Configuración recomendada para proyecto local/portfolio
--    - Recovery SIMPLE: log de transacciones pequeño (suficiente para análisis)
--    - Auto-shrink OFF: buena práctica (shrink causa fragmentación)
-- =============================================================
ALTER DATABASE InsuranceRetention SET RECOVERY SIMPLE;
ALTER DATABASE InsuranceRetention SET AUTO_SHRINK OFF;
GO

-- =============================================================
-- 4. Cambiar al contexto de la BD recién creada
-- =============================================================
USE InsuranceRetention;
GO

PRINT '>> Listo. Conectado a InsuranceRetention.';
PRINT '>> Próximo paso: ejecutar 02_create_tables.sql';
GO
