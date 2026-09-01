/* ============================================================
   Row Count Reconciliation
   Compares row counts between source and target tables,
   optionally grouped by a partition column.

   Read-only. Modifies nothing.
   ============================================================ */

SET NOCOUNT ON;

-- ============================================================
-- CONFIGURATION
-- ============================================================
DECLARE @SourceTable      SYSNAME       = 'demo.dbo.LeaveRequest_Src';
DECLARE @TargetTable      SYSNAME       = 'demo.dbo.LeaveRequest';
DECLARE @PartitionColumn  SYSNAME       = 'StatusCode';   -- NULL for total only
DECLARE @SourceFilter     NVARCHAR(500) = '1 = 1';
DECLARE @TargetFilter     NVARCHAR(500) = 'IsDeleted = 0';
DECLARE @WarnThreshold    INT           = 0;   -- diff above this = WARN
DECLARE @FailThreshold    INT           = 10;  -- diff above this = FAIL
-- ============================================================

DECLARE @Sql NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;

CREATE TABLE #Result (
    PartitionValue NVARCHAR(200) NULL,
    SourceCount    BIGINT        NOT NULL DEFAULT 0,
    TargetCount    BIGINT        NOT NULL DEFAULT 0
);

IF @PartitionColumn IS NULL
BEGIN
    SET @Sql = N'
        INSERT INTO #Result (PartitionValue, SourceCount, TargetCount)
        SELECT
            ''(total)'',
            (SELECT COUNT_BIG(*) FROM ' + @SourceTable + N' WHERE ' + @SourceFilter + N'),
            (SELECT COUNT_BIG(*) FROM ' + @TargetTable + N' WHERE ' + @TargetFilter + N');';
END
ELSE
BEGIN
    SET @Sql = N'
        WITH src AS (
            SELECT CAST(' + QUOTENAME(@PartitionColumn) + N' AS NVARCHAR(200)) AS PartitionValue,
                   COUNT_BIG(*) AS Cnt
            FROM ' + @SourceTable + N'
            WHERE ' + @SourceFilter + N'
            GROUP BY CAST(' + QUOTENAME(@PartitionColumn) + N' AS NVARCHAR(200))
        ),
        tgt AS (
            SELECT CAST(' + QUOTENAME(@PartitionColumn) + N' AS NVARCHAR(200)) AS PartitionValue,
                   COUNT_BIG(*) AS Cnt
            FROM ' + @TargetTable + N'
            WHERE ' + @TargetFilter + N'
            GROUP BY CAST(' + QUOTENAME(@PartitionColumn) + N' AS NVARCHAR(200))
        )
        INSERT INTO #Result (PartitionValue, SourceCount, TargetCount)
        SELECT
            COALESCE(src.PartitionValue, tgt.PartitionValue),
            ISNULL(src.Cnt, 0),
            ISNULL(tgt.Cnt, 0)
        FROM src
        FULL OUTER JOIN tgt ON src.PartitionValue = tgt.PartitionValue;';
END

BEGIN TRY
    EXEC sp_executesql @Sql;
END TRY
BEGIN CATCH
    SELECT
        'ERROR'                AS Status,
        ERROR_NUMBER()         AS ErrorNumber,
        ERROR_MESSAGE()        AS ErrorMessage;
    RETURN;
END CATCH

-- Detail
SELECT
    PartitionValue,
    SourceCount,
    TargetCount,
    TargetCount - SourceCount AS Difference,
    CASE
        WHEN SourceCount = 0 THEN NULL
        ELSE CAST(ABS(TargetCount - SourceCount) * 100.0 / SourceCount AS DECIMAL(6,2))
    END AS DiffPercent,
    CASE
        WHEN ABS(TargetCount - SourceCount) > @FailThreshold THEN 'FAIL'
        WHEN ABS(TargetCount - SourceCount) > @WarnThreshold THEN 'WARN'
        ELSE 'PASS'
    END AS Status
FROM #Result
ORDER BY ABS(TargetCount - SourceCount) DESC, PartitionValue;

-- Summary
SELECT
    COUNT(*)                                                   AS PartitionsChecked,
    SUM(SourceCount)                                           AS TotalSource,
    SUM(TargetCount)                                           AS TotalTarget,
    SUM(TargetCount) - SUM(SourceCount)                        AS TotalDifference,
    SUM(CASE WHEN ABS(TargetCount - SourceCount) > @FailThreshold THEN 1 ELSE 0 END) AS FailCount,
    CASE
        WHEN SUM(CASE WHEN ABS(TargetCount - SourceCount) > @FailThreshold THEN 1 ELSE 0 END) > 0 THEN 'FAIL'
        WHEN SUM(CASE WHEN ABS(TargetCount - SourceCount) > @WarnThreshold THEN 1 ELSE 0 END) > 0 THEN 'WARN'
        ELSE 'PASS'
    END AS OverallStatus
FROM #Result;

DROP TABLE #Result;
