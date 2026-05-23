/*
=============================================================================
  Script:      02_create_tables.sql
  Proyecto:    Insurance Retention Analytics
  Descripción: Crea las 4 tablas del modelo de datos:
                 - customer                     (50,000 filas — CSV crudo)
                 - customer_predictions         (50,000 filas — output del modelo)
                 - high_risk_customers          (~13K — lista accionable)
                 - cross_sell_opportunities     (~12.5K — campaña cross-sell)
               Incluye PKs, CHECK constraints e índices no clustered para
               optimizar las consultas analíticas más comunes.
  Autor:       [Tu Nombre]
  Fecha:       2026
=============================================================================
*/

USE InsuranceRetention;
GO

-- =============================================================
-- 1. Borrar tablas si existen (script idempotente)
--    Orden: primero las dependientes, luego la maestra
-- =============================================================
IF OBJECT_ID('dbo.cross_sell_opportunities', 'U') IS NOT NULL
    DROP TABLE dbo.cross_sell_opportunities;

IF OBJECT_ID('dbo.high_risk_customers', 'U') IS NOT NULL
    DROP TABLE dbo.high_risk_customers;

IF OBJECT_ID('dbo.customer_predictions', 'U') IS NOT NULL
    DROP TABLE dbo.customer_predictions;

IF OBJECT_ID('dbo.customer', 'U') IS NOT NULL
    DROP TABLE dbo.customer;
GO

-- =============================================================
-- 2. TABLA: customer
--    Refleja directamente el CSV crudo (50,000 filas × 40 col)
--    Tipos elegidos para minimizar tamaño y maximizar performance.
-- =============================================================
PRINT '>> Creando tabla [customer]...';

CREATE TABLE dbo.customer (
    -- Identificador y tiempo
    customer_id                      INT             NOT NULL,
    as_of_date                       DATE            NOT NULL,

    -- Demográficos
    region_name                      VARCHAR(50)     NOT NULL,
    age                              TINYINT         NOT NULL,         -- 0-255, suficiente
    age_band                         VARCHAR(10)     NOT NULL,
    marital_status                   VARCHAR(20)     NOT NULL,

    -- Pólizas
    customer_tenure_months           SMALLINT        NOT NULL,         -- max 32K, ok para tenure
    multi_policy_flag                BIT             NOT NULL,
    num_policies                     TINYINT         NOT NULL,
    policy_type                      VARCHAR(20)     NOT NULL,
    renewal_month                    TINYINT         NOT NULL,         -- 1-12

    -- Económicas
    current_premium                  DECIMAL(10,2)   NOT NULL,
    premium_last_year                DECIMAL(10,2)   NOT NULL,
    premium_change_pct               DECIMAL(10,6)   NOT NULL,
    num_price_increases_last_3y      TINYINT         NOT NULL,
    coverage_amount                  DECIMAL(12,2)   NOT NULL,
    premium_to_coverage_ratio        DECIMAL(10,6)   NOT NULL,

    -- Comportamiento de pago
    payment_frequency                VARCHAR(10)     NOT NULL,
    autopay_enabled                  BIT             NOT NULL,
    late_payment_count_12m           TINYINT         NOT NULL,
    missed_payment_flag              BIT             NOT NULL,
    payment_method_change_flag       BIT             NOT NULL,

    -- Siniestros (claims)
    num_claims_12m                   TINYINT         NOT NULL,
    num_approved_claims_12m          TINYINT         NOT NULL,
    num_rejected_claims_12m          TINYINT         NOT NULL,
    num_pending_claims_12m           TINYINT         NOT NULL,
    avg_claim_amount                 DECIMAL(12,2)   NOT NULL,
    total_claim_amount_12m           DECIMAL(12,2)   NOT NULL,
    total_payout_amount_12m          DECIMAL(12,2)   NOT NULL,
    payout_ratio_12m                 DECIMAL(10,4)   NOT NULL,
    avg_settlement_time_days         SMALLINT        NOT NULL,
    days_since_last_claim            SMALLINT        NOT NULL,

    -- Servicio al cliente
    num_contacts_12m                 TINYINT         NOT NULL,
    complaint_flag                   BIT             NOT NULL,
    complaint_resolution_days        SMALLINT        NOT NULL,

    -- Señales de fuga
    quote_requested_flag             BIT             NOT NULL,
    coverage_downgrade_flag          BIT             NOT NULL,

    -- Target
    churn_flag                       BIT             NOT NULL,
    churn_type                       VARCHAR(30)     NOT NULL,
    churn_probability_true           DECIMAL(10,6)   NOT NULL,

    -- Primary Key
    CONSTRAINT pk_customer PRIMARY KEY CLUSTERED (customer_id),

    -- Validaciones de negocio (CHECK constraints)
    CONSTRAINT chk_customer_age          CHECK (age BETWEEN 18 AND 120),
    CONSTRAINT chk_customer_renewal      CHECK (renewal_month BETWEEN 1 AND 12),
    CONSTRAINT chk_customer_num_policies CHECK (num_policies BETWEEN 1 AND 10)
);
GO

PRINT '>> Creando índices analíticos en [customer]...';

-- Índices para acelerar agregaciones por dimensión (Power BI los aprovecha)
CREATE NONCLUSTERED INDEX ix_customer_churn        ON dbo.customer (churn_flag);
CREATE NONCLUSTERED INDEX ix_customer_age_band     ON dbo.customer (age_band);
CREATE NONCLUSTERED INDEX ix_customer_region       ON dbo.customer (region_name);
CREATE NONCLUSTERED INDEX ix_customer_policy_type  ON dbo.customer (policy_type);
CREATE NONCLUSTERED INDEX ix_customer_multi_policy ON dbo.customer (multi_policy_flag);
GO


-- =============================================================
-- 3. TABLA: customer_predictions
--    Output del notebook 07 (scoring del portafolio completo)
-- =============================================================
PRINT '>> Creando tabla [customer_predictions]...';

CREATE TABLE dbo.customer_predictions (
    customer_id                      INT             NOT NULL,
    as_of_date                       DATE            NOT NULL,
    predicted_churn_probability      DECIMAL(6,4)    NOT NULL,
    risk_bucket                      VARCHAR(20)     NOT NULL,   -- 1_Critico, 2_Alto, 3_Medio, 4_Bajo
    risk_bucket_label                VARCHAR(20)     NOT NULL,   -- 🟥 Crítico, etc.
    risk_score                       TINYINT         NOT NULL,
    policy_type                      VARCHAR(20)     NOT NULL,
    num_policies                     TINYINT         NOT NULL,
    age_band                         VARCHAR(10)     NOT NULL,
    current_premium                  DECIMAL(10,2)   NOT NULL,
    customer_tenure_months           SMALLINT        NOT NULL,
    churn_flag                       BIT             NOT NULL,

    CONSTRAINT pk_customer_predictions PRIMARY KEY CLUSTERED (customer_id),
    CONSTRAINT fk_predictions_customer FOREIGN KEY (customer_id)
        REFERENCES dbo.customer (customer_id),

    CONSTRAINT chk_proba CHECK (predicted_churn_probability BETWEEN 0 AND 1)
);
GO

-- Índices analíticos
CREATE NONCLUSTERED INDEX ix_predictions_bucket      ON dbo.customer_predictions (risk_bucket);
CREATE NONCLUSTERED INDEX ix_predictions_proba_desc  ON dbo.customer_predictions (predicted_churn_probability DESC);
GO


-- =============================================================
-- 4. TABLA: high_risk_customers
--    Lista accionable para el equipo de retención
-- =============================================================
PRINT '>> Creando tabla [high_risk_customers]...';

CREATE TABLE dbo.high_risk_customers (
    customer_id                      INT             NOT NULL,
    predicted_churn_probability      DECIMAL(6,4)    NOT NULL,
    risk_bucket                      VARCHAR(20)     NOT NULL,
    risk_score                       TINYINT         NOT NULL,
    age                              TINYINT         NOT NULL,
    customer_tenure_months           SMALLINT        NOT NULL,
    current_premium                  DECIMAL(10,2)   NOT NULL,
    num_policies                     TINYINT         NOT NULL,
    missed_payment_flag              BIT             NOT NULL,
    complaint_flag                   BIT             NOT NULL,
    coverage_downgrade_flag          BIT             NOT NULL,
    quote_requested_flag             BIT             NOT NULL,
    premium_change_pct               DECIMAL(10,6)   NOT NULL,
    recommended_action               VARCHAR(100)    NOT NULL,

    CONSTRAINT pk_high_risk_customers PRIMARY KEY CLUSTERED (customer_id),
    CONSTRAINT fk_high_risk_customer FOREIGN KEY (customer_id)
        REFERENCES dbo.customer (customer_id)
);
GO

CREATE NONCLUSTERED INDEX ix_highrisk_proba_desc ON dbo.high_risk_customers (predicted_churn_probability DESC);
GO


-- =============================================================
-- 5. TABLA: cross_sell_opportunities
--    Mono-póliza estables → target de cross-sell
-- =============================================================
PRINT '>> Creando tabla [cross_sell_opportunities]...';

CREATE TABLE dbo.cross_sell_opportunities (
    customer_id                      INT             NOT NULL,
    predicted_churn_probability      DECIMAL(6,4)    NOT NULL,
    risk_bucket                      VARCHAR(20)     NOT NULL,
    age                              TINYINT         NOT NULL,
    customer_tenure_months           SMALLINT        NOT NULL,
    current_premium                  DECIMAL(10,2)   NOT NULL,
    num_policies                     TINYINT         NOT NULL,
    recommended_action               VARCHAR(100)    NOT NULL,

    CONSTRAINT pk_cross_sell_opportunities PRIMARY KEY CLUSTERED (customer_id),
    CONSTRAINT fk_cross_sell_customer FOREIGN KEY (customer_id)
        REFERENCES dbo.customer (customer_id)
);
GO


-- =============================================================
-- 6. Verificación final
-- =============================================================
PRINT '';
PRINT '>> TABLAS CREADAS:';
SELECT
    t.name                                          AS tabla,
    p.rows                                          AS filas,
    SUM(a.total_pages) * 8 / 1024.0                 AS espacio_reservado_mb
FROM sys.tables t
JOIN sys.indexes i      ON t.object_id = i.object_id
JOIN sys.partitions p   ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.is_ms_shipped = 0
GROUP BY t.name, p.rows
ORDER BY t.name;

PRINT '';
PRINT '>> Listo. Próximo paso: ejecutar 03_load_data.sql';
GO
