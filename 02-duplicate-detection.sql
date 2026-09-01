/* ============================================================
   Duplicate Detection
   Finds duplicate rows on a business key and reports whether
   the duplicates are identical or conflicting.

   Conflicting duplicates matter more — identical rows can be
   deduplicated safely, conflicting ones need a business decision.

   Read-only.
   ============================================================ */

SET NOCOUNT ON;

-- ============================================================
-- CONFIGURATION
-- ============================================================
DECLARE @Table          SYSNAME       = 'demo.dbo.Employee';
DECLARE @KeyColumns     NVARCHAR(500) = 'NationalID';           -- comma separated
DECLARE @CompareColumns NVARCHAR(500) = 'FullName, Department, Email';
DECLARE @Filter         NVARCHAR(500) = 'IsActive = 1';
DECLARE @MaxSamples     INT           = 50;
-- ============================================================

DECLARE @Sql NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#Dup') IS NOT NULL DROP TABLE #Dup;

CREATE TABLE #Dup (
    KeyValue      NVARCHAR(500) NOT NULL,
    DupCount      INT           NOT NULL,
    DistinctCount INT           NOT NULL
);

SET @Sql = N'
    INSERT INTO #Dup (KeyValue, DupCount, DistinctCount)
    SELECT TOP (' + CAST(@MaxSamples AS NVARCHAR(10)) + N')
        CONCAT_WS('' | '', ' + @KeyColumns + N')          AS KeyValue,
        COUNT(*)                                          AS DupCount,
        COUNT(DISTINCT CONCAT_WS(''|'', ' + @CompareColumns + N')) AS DistinctCount
    FROM ' + @Table + N'
    WHERE ' + @Filter + N'
    GROUP BY ' + @KeyColumns + N'
    HAVING COUNT(*) > 1
    ORDER BY COUNT(*) DESC;';

BEGIN TRY
    EXEC sp_executesql @Sql;
END TRY
BEGIN CATCH
    SELECT 'ERROR' AS Status, ERROR_MESSAGE() AS ErrorMessage;
    RETURN;
END CATCH

-- Detail
SELECT
    KeyValue,
    DupCount,
    DistinctCount,
    DupCount - 1 AS ExcessRows,
    CASE
        WHEN DistinctCount = 1 THEN 'IDENTICAL'
        ELSE 'CONFLICTING'
    END AS DuplicateType,
    CASE
        WHEN DistinctCount > 1 THEN 'FAIL'
        ELSE 'WARN'
    END AS Status
FROM #Dup
ORDER BY DistinctCount DESC, DupCount DESC;

-- Summary
SELECT
    COUNT(*)                                                        AS DuplicateKeys,
    SUM(DupCount - 1)                                               AS ExcessRowsTotal,
    SUM(CASE WHEN DistinctCount > 1 THEN 1 ELSE 0 END)              AS ConflictingKeys,
    SUM(CASE WHEN DistinctCount = 1 THEN 1 ELSE 0 END)              AS IdenticalKeys,
    CASE
        WHEN SUM(CASE WHEN DistinctCount > 1 THEN 1 ELSE 0 END) > 0 THEN 'FAIL'
        WHEN COUNT(*) > 0 THEN 'WARN'
        ELSE 'PASS'
    END AS OverallStatus
FROM #Dup;

DROP TABLE #Dup;
