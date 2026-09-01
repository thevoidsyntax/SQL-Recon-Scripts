/* ============================================================
   Null and Format Audit
   Checks required columns for nulls, empty strings, and
   whitespace-only values. Optional pattern check.

   Empty strings are the ones that get missed. A NOT NULL
   constraint does not stop them.

   Read-only.
   ============================================================ */

SET NOCOUNT ON;

-- ============================================================
-- CONFIGURATION
-- ============================================================
DECLARE @Table       SYSNAME       = 'demo.dbo.Employee';
DECLARE @Filter      NVARCHAR(500) = 'IsActive = 1';
DECLARE @WarnPercent DECIMAL(5,2)  = 0.00;
DECLARE @FailPercent DECIMAL(5,2)  = 1.00;
-- ============================================================

-- Columns to check. Pattern NULL = presence check only.
DECLARE @Checks TABLE (
    ColumnName NVARCHAR(128),
    Pattern    NVARCHAR(200) NULL,
    Note       NVARCHAR(200) NULL
);

INSERT INTO @Checks (ColumnName, Pattern, Note) VALUES
    ('NationalID', '[0-9][0-9][0-9][0-9][0-9][0-9]%', 'Numeric, min 6 digits'),
    ('Email',      '%_@_%._%',                        'Basic email shape'),
    ('FullName',   NULL,                              'Required'),
    ('Department', NULL,                              'Required'),
    ('HireDate',   NULL,                              'Required');

IF OBJECT_ID('tempdb..#Audit') IS NOT NULL DROP TABLE #Audit;

CREATE TABLE #Audit (
    ColumnName   NVARCHAR(128),
    Note         NVARCHAR(200) NULL,
    TotalRows    BIGINT,
    NullCount    BIGINT,
    BlankCount   BIGINT,
    FormatFails  BIGINT
);

DECLARE @Col     NVARCHAR(128);
DECLARE @Pattern NVARCHAR(200);
DECLARE @Note    NVARCHAR(200);
DECLARE @Sql     NVARCHAR(MAX);

DECLARE col_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT ColumnName, Pattern, Note FROM @Checks;

OPEN col_cursor;
FETCH NEXT FROM col_cursor INTO @Col, @Pattern, @Note;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
        INSERT INTO #Audit (ColumnName, Note, TotalRows, NullCount, BlankCount, FormatFails)
        SELECT
            @pCol,
            @pNote,
            COUNT_BIG(*),
            SUM(CASE WHEN ' + QUOTENAME(@Col) + N' IS NULL THEN 1 ELSE 0 END),
            SUM(CASE WHEN ' + QUOTENAME(@Col) + N' IS NOT NULL
                      AND LTRIM(RTRIM(CAST(' + QUOTENAME(@Col) + N' AS NVARCHAR(MAX)))) = ''''
                     THEN 1 ELSE 0 END),
            ' + CASE
                    WHEN @Pattern IS NULL THEN N'0'
                    ELSE N'SUM(CASE WHEN ' + QUOTENAME(@Col) + N' IS NOT NULL
                                     AND CAST(' + QUOTENAME(@Col) + N' AS NVARCHAR(MAX)) NOT LIKE @pPattern
                                    THEN 1 ELSE 0 END)'
                END + N'
        FROM ' + @Table + N'
        WHERE ' + @Filter + N';';

    BEGIN TRY
        EXEC sp_executesql
            @Sql,
            N'@pCol NVARCHAR(128), @pNote NVARCHAR(200), @pPattern NVARCHAR(200)',
            @pCol = @Col, @pNote = @Note, @pPattern = @Pattern;
    END TRY
    BEGIN CATCH
        INSERT INTO #Audit (ColumnName, Note, TotalRows, NullCount, BlankCount, FormatFails)
        VALUES (@Col, 'ERROR: ' + ERROR_MESSAGE(), 0, 0, 0, 0);
    END CATCH

    FETCH NEXT FROM col_cursor INTO @Col, @Pattern, @Note;
END

CLOSE col_cursor;
DEALLOCATE col_cursor;

-- Detail
SELECT
    ColumnName,
    Note,
    TotalRows,
    NullCount,
    BlankCount,
    FormatFails,
    NullCount + BlankCount + FormatFails AS TotalIssues,
    CASE WHEN TotalRows = 0 THEN NULL
         ELSE CAST((NullCount + BlankCount + FormatFails) * 100.0 / TotalRows AS DECIMAL(6,2))
    END AS IssuePercent,
    CASE
        WHEN TotalRows = 0 THEN 'NO DATA'
        WHEN (NullCount + BlankCount + FormatFails) * 100.0 / TotalRows > @FailPercent THEN 'FAIL'
        WHEN (NullCount + BlankCount + FormatFails) * 100.0 / TotalRows > @WarnPercent THEN 'WARN'
        ELSE 'PASS'
    END AS Status
FROM #Audit
ORDER BY (NullCount + BlankCount + FormatFails) DESC;

DROP TABLE #Audit;
