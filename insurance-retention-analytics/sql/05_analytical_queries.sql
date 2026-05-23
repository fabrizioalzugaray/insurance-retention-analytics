/*
=============================================================================
  Script:      05_analytical_queries.sql
  Proyecto:    Insurance Retention Analytics
  Descripción: 10 queries analíticas orientadas a negocio.
               Cada query responde una pregunta concreta del comité directivo.
               Útiles para:
                 - Defender el proyecto en entrevistas técnicas
                 - Generar insights para el README/LinkedIn
                 - Alimentar visuales puntuales del dashboard
  Autor:       [Tu Nombre]
  Fecha:       2026
=============================================================================
*/

USE InsuranceRetention;
GO

/* ============================================================
   QUERY 1 — KPIs ejecutivos en una sola consulta
   Pregunta de negocio: "¿Cuál es la foto general del portafolio?"
   ============================================================ */
SELECT * FROM dbo.vw_executive_kpis;


/* ============================================================
   QUERY 2 — Top 5 regiones con mayor tasa de churn
   Pregunta de negocio: "¿En qué regiones debemos enfocar campañas?"
   ============================================================ */
SELECT TOP 5
    region_name,
    COUNT(*)                                                    AS n_customers,
    SUM(CAST(churn_flag AS INT))                                AS n_churners,
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))  AS churn_rate_pct,
    CAST(SUM(current_premium) AS DECIMAL(15,2))                 AS revenue_total,
    CAST(SUM(CASE WHEN churn_flag = 1 THEN current_premium ELSE 0 END) AS DECIMAL(15,2)) AS revenue_lost
FROM dbo.customer
GROUP BY region_name
ORDER BY churn_rate_pct DESC;


/* ============================================================
   QUERY 3 — Cohort analysis por antigüedad del cliente
   Pregunta de negocio: "¿En qué momento del lifecycle el cliente se vuelve frágil?"
   Output: churn rate por banda de tenure, validando que < 1 año es la zona crítica
   ============================================================ */
SELECT
    CASE
        WHEN customer_tenure_months < 12  THEN '1. < 1 año'
        WHEN customer_tenure_months < 36  THEN '2. 1-3 años'
        WHEN customer_tenure_months < 60  THEN '3. 3-5 años'
        WHEN customer_tenure_months < 120 THEN '4. 5-10 años'
        ELSE                                   '5. 10+ años'
    END                                                         AS tenure_band,
    COUNT(*)                                                    AS n_customers,
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))  AS churn_rate_pct,
    CAST(AVG(current_premium) AS DECIMAL(10,2))                 AS avg_premium,
    CAST(AVG(CAST(multi_policy_flag AS FLOAT)) * 100 AS DECIMAL(5,2)) AS multi_policy_pct
FROM dbo.customer
GROUP BY
    CASE
        WHEN customer_tenure_months < 12  THEN '1. < 1 año'
        WHEN customer_tenure_months < 36  THEN '2. 1-3 años'
        WHEN customer_tenure_months < 60  THEN '3. 3-5 años'
        WHEN customer_tenure_months < 120 THEN '4. 5-10 años'
        ELSE                                   '5. 10+ años'
    END
ORDER BY tenure_band;


/* ============================================================
   QUERY 4 — Payment behavior analysis
   Pregunta de negocio: "¿Cuánto eleva el churn cada nivel de morosidad?"
   ============================================================ */
SELECT
    late_payment_count_12m,
    COUNT(*)                                                    AS n_customers,
    SUM(CAST(churn_flag AS INT))                                AS n_churners,
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))  AS churn_rate_pct,
    -- Diferencia vs el grupo de 0 atrasos
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100
         - (SELECT AVG(CAST(churn_flag AS FLOAT)) * 100
            FROM dbo.customer WHERE late_payment_count_12m = 0)
         AS DECIMAL(5,2))                                       AS lift_pp_vs_zero_late
FROM dbo.customer
GROUP BY late_payment_count_12m
ORDER BY late_payment_count_12m;


/* ============================================================
   QUERY 5 — Análisis de quejas: efecto del SLA de resolución
   Pregunta de negocio: "¿Cuánto importa resolver una queja rápido?"
   Solo entre quienes presentaron queja
   ============================================================ */
SELECT
    CASE
        WHEN complaint_resolution_days <= 7  THEN '1. <= 7 días'
        WHEN complaint_resolution_days <= 14 THEN '2. 8-14 días'
        WHEN complaint_resolution_days <= 30 THEN '3. 15-30 días'
        ELSE                                      '4. 30+ días'
    END                                                         AS resolution_band,
    COUNT(*)                                                    AS n_complaints,
    CAST(AVG(CAST(churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))  AS churn_rate_pct,
    CAST(AVG(CAST(complaint_resolution_days AS FLOAT)) AS DECIMAL(6,1)) AS avg_days
FROM dbo.customer
WHERE complaint_flag = 1
GROUP BY
    CASE
        WHEN complaint_resolution_days <= 7  THEN '1. <= 7 días'
        WHEN complaint_resolution_days <= 14 THEN '2. 8-14 días'
        WHEN complaint_resolution_days <= 30 THEN '3. 15-30 días'
        ELSE                                      '4. 30+ días'
    END
ORDER BY resolution_band;


/* ============================================================
   QUERY 6 — Top 10 clientes en riesgo CRÍTICO para llamada inmediata
   Pregunta de negocio: "¿A qué 10 clientes hay que llamar mañana?"
   ============================================================ */
SELECT TOP 10
    h.customer_id,
    h.predicted_churn_probability,
    h.age,
    h.customer_tenure_months,
    h.current_premium,
    h.num_policies,
    h.missed_payment_flag,
    h.complaint_flag,
    h.coverage_downgrade_flag,
    h.quote_requested_flag,
    h.premium_change_pct,
    h.recommended_action
FROM dbo.high_risk_customers h
WHERE h.risk_bucket = '1_Critico'
ORDER BY h.predicted_churn_probability DESC;


/* ============================================================
   QUERY 7 — Oportunidades de retención por revenue at risk
   Pregunta de negocio: "¿Qué bucket de riesgo prioriza el CFO por $?"
   ============================================================ */
SELECT
    p.risk_bucket,
    p.risk_bucket_label,
    COUNT(*)                                                    AS n_customers,
    CAST(SUM(c.current_premium) AS DECIMAL(15,2))               AS revenue_at_risk,
    CAST(SUM(c.current_premium) * AVG(CAST(c.churn_flag AS FLOAT)) AS DECIMAL(15,2)) AS expected_revenue_loss,
    -- Asumiendo 30% de retención exitosa con la campaña
    CAST(SUM(c.current_premium) * AVG(CAST(c.churn_flag AS FLOAT)) * 0.30 AS DECIMAL(15,2)) AS revenue_recoverable_30pct
FROM dbo.customer_predictions p
JOIN dbo.customer c ON c.customer_id = p.customer_id
GROUP BY p.risk_bucket, p.risk_bucket_label
ORDER BY p.risk_bucket;


/* ============================================================
   QUERY 8 — Cross-sell potential por región
   Pregunta de negocio: "¿Dónde hay más mono-pólizas estables para cross-sell?"
   ============================================================ */
SELECT
    c.region_name,
    COUNT(*)                                                    AS n_targets,
    CAST(AVG(c.customer_tenure_months) AS INT)                  AS avg_tenure_months,
    CAST(AVG(c.current_premium) AS DECIMAL(10,2))               AS avg_premium,
    -- Upside estimado: 15% de conversión × 70% del ticket actual como segunda póliza
    CAST(COUNT(*) * 0.15 * AVG(c.current_premium) * 0.7 AS DECIMAL(15,2)) AS estimated_upside_15pct_conv
FROM dbo.cross_sell_opportunities cs
JOIN dbo.customer c ON c.customer_id = cs.customer_id
GROUP BY c.region_name
ORDER BY n_targets DESC;


/* ============================================================
   QUERY 9 — Premium shock: clientes con aumento > 10% no detectados aún
   Pregunta de negocio: "¿Quiénes recibirán un aumento grande y aún no están en alerta?"
   ============================================================ */
SELECT
    c.customer_id,
    c.region_name,
    c.age,
    c.policy_type,
    c.customer_tenure_months,
    c.premium_last_year,
    c.current_premium,
    c.premium_change_pct,
    p.predicted_churn_probability,
    p.risk_bucket
FROM dbo.customer c
JOIN dbo.customer_predictions p ON c.customer_id = p.customer_id
WHERE c.premium_change_pct > 0.10
  AND p.risk_bucket = '4_Bajo'           -- bajo riesgo pero con premium shock = puntos ciegos
ORDER BY c.premium_change_pct DESC;


/* ============================================================
   QUERY 10 — Validación del modelo: real vs predicho por bucket
   Pregunta de negocio: "¿Es confiable la segmentación de riesgo?"
   ============================================================ */
SELECT
    p.risk_bucket,
    COUNT(*)                                                    AS n_customers,
    CAST(AVG(p.predicted_churn_probability) * 100 AS DECIMAL(5,2)) AS predicted_avg_pct,
    CAST(AVG(CAST(c.churn_flag AS FLOAT)) * 100 AS DECIMAL(5,2))   AS actual_churn_pct,
    -- Diferencia absoluta (calibración del modelo)
    CAST(ABS(AVG(p.predicted_churn_probability) * 100
            - AVG(CAST(c.churn_flag AS FLOAT)) * 100) AS DECIMAL(5,2)) AS abs_calibration_gap
FROM dbo.customer_predictions p
JOIN dbo.customer c ON c.customer_id = p.customer_id
GROUP BY p.risk_bucket
ORDER BY p.risk_bucket;

PRINT '';
PRINT '>> Las 10 queries analíticas están disponibles.';
PRINT '>> Tip: ejecutar de a una para revisar resultados.';
PRINT '>> Próximo paso: conectar Power BI a estas vistas/queries.';
GO
