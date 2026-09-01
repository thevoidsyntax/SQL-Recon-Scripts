/* ============================================================
   Orphan Record Detection
   Finds child rows whose foreign key has no matching parent.

   Common after migration, or where the FK constraint was
   never enforced in the first place.

   Read-only.
   ============================================================ */

SET NOCOUNT ON;

-- ============================================================
-- CONFIGURATION
-- ============================================================
DECLARE @ChildTable   SYSNAME       = 'demo.dbo.LeaveRequest';
DECLARE @ChildKey     SYSNAME       = 'EmployeeID';
DECLARE @ChildPK      SYSNAME       = 'RequestID';
DECLARE @ParentTable  SYSNAME       = 'demo.dbo.Employee';
DECLARE @ParentKey    SYSNAME       = 'EmployeeID';
DECLARE @ChildFilter  NVARCHAR(500) = 'IsDeleted = 0';
DECLARE @MaxSamples   INT           = 100;
DECLARE @FailIfAny    BIT           = 1;
-- ============================================================

DECLARE @Sql        NVARCHAR(MAX);
DECLARE @Orphans    BIGINT;
DECLARE @Total      BIGINT;
DECLARE @NullKeys   BIGINT;

DECLARE @Counts TABLE (Total BIGINT, Orphans BIGINT, NullKeys BIGINT);

SET @Sql = N'
    SELECT
        COUNT_BIG(*) AS Total,
        SUM(CASE WHEN c.' + QUOTENAME(@ChildKey) + N' IS NOT NULL
                  AND p.' + QUOTENAME(@ParentKey) + N' IS NULL
                 THEN 1 ELSE 0 END) AS Orphans,
        SUM(CASE WHEN c.' + QUOTENAME(@ChildKey) + N' IS NULL
                 THEN 1 ELSE 0 END) AS NullKeys
    FROM ' + @ChildTable + N' AS c
    LEFT JOIN ' + @ParentTable + N' AS p
        ON c.' + QUOTENAME(@ChildKey) + N' = p.' + QUOTENAME(@ParentKey) + N'
    WHERE ' + @ChildFilter + N';';

BEGIN TRY
    INSERT INTO @Counts EXEC sp_executesql @Sql;
END TRY
BEGIN CATCH
    SELECT 'ERROR' AS Status, ERROR_MESSAGE() AS ErrorMessage;
    RETURN;
END CATCH

SELECT @Total = Total, @Orphans = Orphans, @NullKeys = NullKeys FROM @Counts;

-- Summary
SELECT
    @ChildTable                AS ChildTable,
    @ParentTable               AS ParentTable,
    @Total                     AS RowsChecked,
    @Orphans                   AS OrphanRows,
    @NullKeys                  AS NullForeignKeys,
    CASE WHEN @Total = 0 THEN NULL
         ELSE CAST(@Orphans * 100.0 / @Total AS DECIMAL(6,3))
    END                        AS OrphanPercent,
    CASE
        WHEN @Orphans > 0 AND @FailIfAny = 1 THEN 'FAIL'
        WHEN @Orphans > 0 THEN 'WARN'
        ELSE 'PASS'
    END                        AS Status;

-- Samples
IF @Orphans > 0
BEGIN
    SET @Sql = N'
        SELECT TOP (' + CAST(@MaxSamples AS NVARCHAR(10)) + N')
            c.' + QUOTENAME(@ChildPK)  + N' AS ChildPrimaryKey,
            c.' + QUOTENAME(@ChildKey) + N' AS MissingParentKey
        FROM ' + @ChildTable + N' AS c
        LEFT JOIN ' + @ParentTable + N' AS p
            ON c.' + QUOTENAME(@ChildKey) + N' = p.' + QUOTENAME(@ParentKey) + N'
        WHERE ' + @ChildFilter + N'
          AND c.' + QUOTENAME(@ChildKey)  + N' IS NOT NULL
          AND p.' + QUOTENAME(@ParentKey) + N' IS NULL
        ORDER BY c.' + QUOTENAME(@ChildPK) + N';';

    EXEC sp_executesql @Sql;
END
ELSE
BEGIN
    SELECT 'No orphan records found.' AS Message;
END
