/* ============================================================
   Amount Reconciliation
   Compares financial totals between two tables at sum level,
   then lists row-level mismatches.

   Tolerance exists because rounding differences between systems
   are normal. Set it to the smallest currency unit, not zero.

   Read-only.
   ============================================================ */

SET NOCOUNT ON;

-- ============================================================
-- CONFIGURATION
-- ============================================================
DECLARE @SourceTable   SYSNAME       = 'demo.dbo.Invoice_Src';
DECLARE @TargetTable   SYSNAME       = 'demo.dbo.Invoice';
DECLARE @JoinKey       SYSNAME       = 'InvoiceNo';
DECLARE @SourceAmount  SYSNAME       = 'TotalAmount';
DECLARE @TargetAmount  SYSNAME       = 'TotalAmount';
DECLARE @SourceFilter  NVARCHAR(500) = '1 = 1';
DECLARE @TargetFilter  NVARCHAR(500) = 'IsVoid = 0';
DECLARE @Tolerance     DECIMAL(18,4) = 0.01;
DECLARE @MaxSamples    INT           = 100;
-- ============================================================

DECLARE @Sql NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#Recon') IS NOT NULL DROP TABLE #Recon;

CREATE TABLE #Recon (
    JoinKey      NVARCHAR(200) NULL,
    SourceAmount DECIMAL(18,4) NULL,
    TargetAmount DECIMAL(18,4) NULL
);

SET @Sql = N'
    INSERT INTO #Recon (JoinKey, SourceAmount, TargetAmount)
    SELECT
        CAST(COALESCE(s.' + QUOTENAME(@JoinKey) + N', t.' + QUOTENAME(@JoinKey) + N') AS NVARCHAR(200)),
        s.' + QUOTENAME(@SourceAmount) + N',
        t.' + QUOTENAME(@TargetAmount) + N'
    FROM (SELECT * FROM ' + @SourceTable + N' WHERE ' + @SourceFilter + N') AS s
    FULL OUTER JOIN (SELECT * FROM ' + @TargetTable + N' WHERE ' + @TargetFilter + N') AS t
        ON s.' + QUOTENAME(@JoinKey) + N' = t.' + QUOTENAME(@JoinKey) + N';';

BEGIN TRY
    EXEC sp_executesql @Sql;
END TRY
BEGIN CATCH
    SELECT 'ERROR' AS Status, ERROR_MESSAGE() AS ErrorMessage;
    RETURN;
END CATCH

-- Sum level
SELECT
    'SUM LEVEL'                                              AS CheckLevel,
    SUM(ISNULL(SourceAmount, 0))                             AS SourceTotal,
    SUM(ISNULL(TargetAmount, 0))                             AS TargetTotal,
    SUM(ISNULL(TargetAmount, 0)) - SUM(ISNULL(SourceAmount, 0)) AS Difference,
    CASE
        WHEN ABS(SUM(ISNULL(TargetAmount, 0)) - SUM(ISNULL(SourceAmount, 0))) <= @Tolerance
            THEN 'PASS' ELSE 'FAIL'
    END                                                      AS Status
FROM #Recon;

-- Row level summary
SELECT
    'ROW LEVEL'                                                          AS CheckLevel,
    COUNT(*)                                                             AS RowsCompared,
    SUM(CASE WHEN SourceAmount IS NULL THEN 1 ELSE 0 END)                AS MissingInSource,
    SUM(CASE WHEN TargetAmount IS NULL THEN 1 ELSE 0 END)                AS MissingInTarget,
    SUM(CASE WHEN SourceAmount IS NOT NULL AND TargetAmount IS NOT NULL
              AND ABS(TargetAmount - SourceAmount) > @Tolerance
             THEN 1 ELSE 0 END)                                          AS AmountMismatches,
    CASE
        WHEN SUM(CASE WHEN SourceAmount IS NULL OR TargetAmount IS NULL
                       OR ABS(TargetAmount - SourceAmount) > @Tolerance
                      THEN 1 ELSE 0 END) > 0
            THEN 'FAIL' ELSE 'PASS'
    END                                                                  AS Status
FROM #Recon;

-- Mismatch samples
SELECT TOP (@MaxSamples)
    JoinKey,
    SourceAmount,
    TargetAmount,
    ISNULL(TargetAmount, 0) - ISNULL(SourceAmount, 0) AS Difference,
    CASE
        WHEN SourceAmount IS NULL THEN 'MISSING IN SOURCE'
        WHEN TargetAmount IS NULL THEN 'MISSING IN TARGET'
        ELSE 'AMOUNT MISMATCH'
    END AS Issue
FROM #Recon
WHERE SourceAmount IS NULL
   OR TargetAmount IS NULL
   OR ABS(TargetAmount - SourceAmount) > @Tolerance
ORDER BY ABS(ISNULL(TargetAmount, 0) - ISNULL(SourceAmount, 0)) DESC;

DROP TABLE #Recon;
