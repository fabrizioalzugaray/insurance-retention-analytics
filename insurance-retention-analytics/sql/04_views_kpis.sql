/*
=============================================================================
  Script:      04_views_kpis.sql
  Proyecto:    Insurance Retention Analytics
  Descripción: Crea las vistas analíticas que servirán como CAPA SEMÁNTICA
               entre las tablas crudas y Power BI.

               Por qué vistas y no tablas:
                 - Reflejan SIEMPRE los datos más actuales (sin ETL adicional)
                 - Centralizan la lógica de negocio (definición de KPIs)
                 - Power BI las consume como si fueran tablas, pero con la
                   inteligencia ya aplicada (joins, filtros, cálculos)
  Autor:       [Tu Nombre]
  Fecha:       2026
=============================================================================
*/

USE InsuranceRetention;
GO

-- =============================================================
-- 1. vw_executive_kpis
--    Los KPIs principales del Executive Overview del dashboard.
--    Una sola fila con todos los números clave.
-- =============================================================
IF OBJECT_ID('dbo.vw_executive_kpis', 'V') IS NOT NULL DROP VIEW dbo.vw_executive_kpis;
GO

CREATE VIEW dbo.vw_executive_kpis AS
SELECT
    COUNT(*)                                                        AS total_customers,
    SUM(CAST(churn_flag AS INT))                                    AS total_churners,
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))      AS churn_rate_pct,
    CAST((1 - AVG(CAST(churn_flag AS FLOAT))) * 100 AS DECIMAL(5,2)) AS retention_rate_pct,
    CAST(AVG(current_premium) AS DECIMAL(10,2))                     AS avg_premium,
    CAST(SUM(current_premium) AS DECIMAL(15,2))                     AS total_revenue,
    CAST(AVG(CAST(complaint_flag AS FLOAT)) * 100 AS DECIMAL(5,2))  AS complaint_rate_pct,
    CAST(AVG(CAST(multi_policy_flag AS FLOAT)) * 100 AS DECIMAL(5,2)) AS multi_policy_pct,
    CAST(AVG(CAST(customer_tenure_months AS FLOAT)) AS DECIMAL(6,1)) AS avg_tenure_months
FROM dbo.customer;
GO


-- =============================================================
-- 2. vw_customer_360
--    Vista enriquecida: combina customer + predictions en una sola tabla.
--    Es la vista MAESTRA que Power BI conectará para casi todo.
-- =============================================================
IF OBJECT_ID('dbo.vw_customer_360', 'V') IS NOT NULL DROP VIEW dbo.vw_customer_360;
GO

CREATE VIEW dbo.vw_customer_360 AS
SELECT
    c.customer_id,
    c.as_of_date,
    -- Demografía
    c.region_name,
    c.age,
    c.age_band,
    c.marital_status,
    -- Pólizas
    c.customer_tenure_months,
    CASE
        WHEN c.customer_tenure_months < 12  THEN '< 1 año'
        WHEN c.customer_tenure_months < 36  THEN '1-3 años'
        WHEN c.customer_tenure_months < 60  THEN '3-5 años'
        WHEN c.customer_tenure_months < 120 THEN '5-10 años'
        ELSE                                     '10+ años'
    END                                                           AS tenure_band,
    c.multi_policy_flag,
    c.num_policies,
    c.policy_type,
    c.renewal_month,
    -- Económicas
    c.current_premium,
    c.premium_change_pct,
    CASE WHEN c.premium_change_pct > 0.10 THEN 1 ELSE 0 END        AS premium_shock_flag,
    c.coverage_amount,
    c.payment_frequency,
    c.autopay_enabled,
    -- Comportamiento
    c.late_payment_count_12m,
    c.missed_payment_flag,
    c.num_claims_12m,
    c.num_rejected_claims_12m,
    c.complaint_flag,
    c.complaint_resolution_days,
    c.coverage_downgrade_flag,
    c.quote_requested_flag,
    -- Predicciones del modelo
    p.predicted_churn_probability,
    p.risk_bucket,
    p.risk_bucket_label,
    p.risk_score,
    -- Target real (para validación)
    c.churn_flag,
    c.churn_type
FROM dbo.customer c
LEFT JOIN dbo.customer_predictions p
    ON c.customer_id = p.customer_id;
GO


-- =============================================================
-- 3. vw_churn_by_segment
--    Tasas de churn por las 5 dimensiones más importantes.
--    Optimizada para gráficos comparativos en Power BI.
-- =============================================================
IF OBJECT_ID('dbo.vw_churn_by_segment', 'V') IS NOT NULL DROP VIEW dbo.vw_churn_by_segment;
GO

CREATE VIEW dbo.vw_churn_by_segment AS
SELECT
    'age_band'                                                                          AS dimension,
    age_band                                                                            AS segment,
    COUNT(*)                                                                            AS n_customers,
    SUM(CAST(churn_flag AS INT))                                                        AS n_churners,
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))                          AS churn_rate_pct
FROM dbo.customer
GROUP BY age_band

UNION ALL
SELECT 'region_name', region_name, COUNT(*), SUM(CAST(churn_flag AS INT)),
       CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))
FROM dbo.customer GROUP BY region_name

UNION ALL
SELECT 'policy_type', policy_type, COUNT(*), SUM(CAST(churn_flag AS INT)),
       CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))
FROM dbo.customer GROUP BY policy_type

UNION ALL
SELECT 'marital_status', marital_status, COUNT(*), SUM(CAST(churn_flag AS INT)),
       CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))
FROM dbo.customer GROUP BY marital_status

UNION ALL
SELECT 'payment_frequency', payment_frequency, COUNT(*), SUM(CAST(churn_flag AS INT)),
       CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))
FROM dbo.customer GROUP BY payment_frequency;
GO


-- =============================================================
-- 4. vw_risk_distribution
--    Distribución del portafolio por bucket de riesgo + métricas económicas.
--    Alimenta la página "Risk Factors" del dashboard.
-- =============================================================
IF OBJECT_ID('dbo.vw_risk_distribution', 'V') IS NOT NULL DROP VIEW dbo.vw_risk_distribution;
GO

CREATE VIEW dbo.vw_risk_distribution AS
SELECT
    p.risk_bucket,
    p.risk_bucket_label,
    COUNT(*)                                                       AS n_customers,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_portfolio,
    SUM(CAST(c.churn_flag AS INT))                                 AS actual_churners,
    CAST(AVG(CAST(c.churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))   AS actual_churn_rate_pct,
    CAST(AVG(p.predicted_churn_probability) * 100 AS DECIMAL(5,2)) AS avg_predicted_pct,
    CAST(SUM(c.current_premium) AS DECIMAL(15,2))                  AS revenue_in_bucket,
    CAST(AVG(c.current_premium) AS DECIMAL(10,2))                  AS avg_premium
FROM dbo.customer_predictions p
JOIN dbo.customer c ON c.customer_id = p.customer_id
GROUP BY p.risk_bucket, p.risk_bucket_label;
GO


-- =============================================================
-- 5. vw_risk_factors_impact
--    Impacto de los 6 drivers de riesgo principales sobre la tasa de churn.
--    Una fila por driver, con churn rate con y sin el driver.
-- =============================================================
IF OBJECT_ID('dbo.vw_risk_factors_impact', 'V') IS NOT NULL DROP VIEW dbo.vw_risk_factors_impact;
GO

CREATE VIEW dbo.vw_risk_factors_impact AS
SELECT 'Morosidad severa'            AS driver,
       SUM(CASE WHEN missed_payment_flag = 1 THEN 1 ELSE 0 END)                              AS n_with_flag,
       CAST(AVG(CASE WHEN missed_payment_flag = 1 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)) AS churn_rate_with_flag,
       CAST(AVG(CASE WHEN missed_payment_flag = 0 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)) AS churn_rate_without_flag
FROM dbo.customer
UNION ALL
SELECT 'Queja registrada',
       SUM(CASE WHEN complaint_flag = 1 THEN 1 ELSE 0 END),
       CAST(AVG(CASE WHEN complaint_flag = 1 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)),
       CAST(AVG(CASE WHEN complaint_flag = 0 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2))
FROM dbo.customer
UNION ALL
SELECT 'Coverage downgrade',
       SUM(CASE WHEN coverage_downgrade_flag = 1 THEN 1 ELSE 0 END),
       CAST(AVG(CASE WHEN coverage_downgrade_flag = 1 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)),
       CAST(AVG(CASE WHEN coverage_downgrade_flag = 0 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2))
FROM dbo.customer
UNION ALL
SELECT 'Cotización externa solicitada',
       SUM(CASE WHEN quote_requested_flag = 1 THEN 1 ELSE 0 END),
       CAST(AVG(CASE WHEN quote_requested_flag = 1 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)),
       CAST(AVG(CASE WHEN quote_requested_flag = 0 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2))
FROM dbo.customer
UNION ALL
SELECT 'Premium shock (> +10%)',
       SUM(CASE WHEN premium_change_pct > 0.10 THEN 1 ELSE 0 END),
       CAST(AVG(CASE WHEN premium_change_pct > 0.10 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)),
       CAST(AVG(CASE WHEN premium_change_pct <= 0.10 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2))
FROM dbo.customer
UNION ALL
SELECT 'Mono-póliza',
       SUM(CASE WHEN multi_policy_flag = 0 THEN 1 ELSE 0 END),
       CAST(AVG(CASE WHEN multi_policy_flag = 0 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2)),
       CAST(AVG(CASE WHEN multi_policy_flag = 1 THEN CAST(churn_flag AS FLOAT) END) * 100 AS DECIMAL(5,2))
FROM dbo.customer;
GO


-- =============================================================
-- 6. Verificación: SELECT de prueba sobre cada vista
-- =============================================================
PRINT '>> Vistas creadas. Verificando con SELECT TOP 5 de cada una...';
PRINT '';

PRINT '--- vw_executive_kpis ---';
SELECT * FROM dbo.vw_executive_kpis;

PRINT '--- vw_risk_distribution ---';
SELECT * FROM dbo.vw_risk_distribution ORDER BY risk_bucket;

PRINT '--- vw_risk_factors_impact ---';
SELECT * FROM dbo.vw_risk_factors_impact;

PRINT '';
PRINT '>> Listo. Próximo paso: ejecutar 05_analytical_queries.sql';
GO
