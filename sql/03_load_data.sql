/*
=============================================================================
  Script:      03_load_data.sql
  Proyecto:    Insurance Retention Analytics
  Descripción: Carga los CSVs en las tablas mediante BULK INSERT.
               BULK INSERT es el método más rápido en SQL Server para
               cargar archivos planos (mucho más rápido que INSERT fila por fila).
  Autor:       [Tu Nombre]
  Fecha:       2026

  IMPORTANTE — Antes de ejecutar:
    1. Modificar la variable @DATA_PATH abajo con la ruta REAL donde están los CSVs.
       Debe ser la ruta absoluta. SQL Server necesita permisos de lectura sobre ella.
       Ejemplo Windows: 'C:\Users\fabri\OneDrive\Escritorio\insurance-retention-analytics\data\'
    2. Asegurarse de haber ejecutado primero 01_create_database.sql y 02_create_tables.sql.
    3. Los CSVs requeridos:
       - data\raw\insurance_policyholder_churn_synthetic.csv
       - data\processed\customer_predictions.csv
       - data\processed\high_risk_customers.csv
       - data\processed\cross_sell_opportunities.csv

  Tips:
    - Si BULK INSERT da error de permisos, ejecutar SQL Server con cuenta con acceso
      a la carpeta, o copiar los CSVs a C:\Temp\ y ajustar la ruta.
    - FIRSTROW=2 omite la cabecera del CSV.
    - FIELDTERMINATOR es la coma; ROWTERMINATOR es salto de línea Windows.
=============================================================================
*/

USE InsuranceRetention;
GO

-- =============================================================
-- 0. Limpiar tablas antes de cargar (script idempotente)
--    Orden inverso a las foreign keys
-- =============================================================
DELETE FROM dbo.cross_sell_opportunities;
DELETE FROM dbo.high_risk_customers;
DELETE FROM dbo.customer_predictions;
DELETE FROM dbo.customer;
GO


-- =============================================================
-- 1. Cargar la tabla principal: customer (50,000 filas)
-- =============================================================
PRINT '>> Cargando dbo.customer desde insurance_policyholder_churn_synthetic.csv...';

BULK INSERT dbo.customer
FROM 'C:\Users\fabri\OneDrive\Escritorio\insurance-retention-analytics\data\raw\insurance_policyholder_churn_synthetic.csv'
WITH (
    FIRSTROW            = 2,            -- Omitir cabecera
    FIELDTERMINATOR     = ',',
    ROWTERMINATOR       = '0x0a',       -- LF (línea Unix). Usar '\r\n' o '0x0d0a' si fue exportado en Windows.
    CODEPAGE            = '65001',      -- UTF-8
    TABLOCK,                            -- Mejor performance: bloquea la tabla durante el load
    MAXERRORS           = 10
);

-- Validación rápida
DECLARE @rows_customer INT = (SELECT COUNT(*) FROM dbo.customer);
PRINT CONCAT('   Filas cargadas en customer: ', @rows_customer);

IF @rows_customer <> 50000
    PRINT '   ⚠️  ADVERTENCIA: se esperaban 50,000 filas. Revisa el archivo o el ROWTERMINATOR.';
ELSE
    PRINT '   ✅ OK';
GO


-- =============================================================
-- 2. Cargar customer_predictions (output del notebook 07)
-- =============================================================
PRINT '';
PRINT '>> Cargando dbo.customer_predictions desde customer_predictions.csv...';

BULK INSERT dbo.customer_predictions
FROM 'C:\Users\fabri\OneDrive\Escritorio\insurance-retention-analytics\data\processed\customer_predictions.csv'
WITH (
    FIRSTROW            = 2,
    FIELDTERMINATOR     = ',',
    ROWTERMINATOR       = '0x0a',
    CODEPAGE            = '65001',
    TABLOCK,
    MAXERRORS           = 10
);

DECLARE @rows_pred INT = (SELECT COUNT(*) FROM dbo.customer_predictions);
PRINT CONCAT('   Filas cargadas en customer_predictions: ', @rows_pred);
GO


-- =============================================================
-- 3. Cargar high_risk_customers
-- =============================================================
PRINT '';
PRINT '>> Cargando dbo.high_risk_customers desde high_risk_customers.csv...';

BULK INSERT dbo.high_risk_customers
FROM 'C:\Users\fabri\OneDrive\Escritorio\insurance-retention-analytics\data\processed\high_risk_customers.csv'
WITH (
    FIRSTROW            = 2,
    FIELDTERMINATOR     = ',',
    ROWTERMINATOR       = '0x0a',
    CODEPAGE            = '65001',
    TABLOCK,
    MAXERRORS           = 10
);

DECLARE @rows_hr INT = (SELECT COUNT(*) FROM dbo.high_risk_customers);
PRINT CONCAT('   Filas cargadas en high_risk_customers: ', @rows_hr);
GO


-- =============================================================
-- 4. Cargar cross_sell_opportunities
-- =============================================================
PRINT '';
PRINT '>> Cargando dbo.cross_sell_opportunities desde cross_sell_opportunities.csv...';

BULK INSERT dbo.cross_sell_opportunities
FROM 'C:\Users\fabri\OneDrive\Escritorio\insurance-retention-analytics\data\processed\cross_sell_opportunities.csv'
WITH (
    FIRSTROW            = 2,
    FIELDTERMINATOR     = ',',
    ROWTERMINATOR       = '0x0a',
    CODEPAGE            = '65001',
    TABLOCK,
    MAXERRORS           = 10
);

DECLARE @rows_cs INT = (SELECT COUNT(*) FROM dbo.cross_sell_opportunities);
PRINT CONCAT('   Filas cargadas en cross_sell_opportunities: ', @rows_cs);
GO


-- =============================================================
-- 5. Resumen final de la carga
-- =============================================================
PRINT '';
PRINT '>> RESUMEN DE CARGA:';
SELECT
    'customer'                   AS tabla, COUNT(*) AS filas FROM dbo.customer
UNION ALL
SELECT 'customer_predictions',        COUNT(*)    FROM dbo.customer_predictions
UNION ALL
SELECT 'high_risk_customers',         COUNT(*)    FROM dbo.high_risk_customers
UNION ALL
SELECT 'cross_sell_opportunities',    COUNT(*)    FROM dbo.cross_sell_opportunities;

PRINT '';
PRINT '>> Listo. Próximo paso: ejecutar 04_views_kpis.sql';
GO
