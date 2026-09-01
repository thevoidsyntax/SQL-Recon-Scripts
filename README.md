# SQL Reconciliation Scripts

T-SQL scripts for data validation. Written for SQL Server.

These answer the question that comes up in every UAT: *is this number actually right?*

## Scripts

| File | Checks |
|---|---|
| `01-row-count-reconciliation.sql` | Row counts between source and target after migration |
| `02-duplicate-detection.sql` | Duplicates on a business key, with severity ranking |
| `03-orphan-records.sql` | Child rows whose parent no longer exists |
| `04-null-and-format-audit.sql` | Nulls in required columns, format violations |
| `05-amount-reconciliation.sql` | Sum-level and row-level financial reconciliation |

## Usage

Each script has a configuration block at the top. Set the parameters, run, read the output.

All scripts are read-only. None of them modify data. Run them on a restored copy if the environment is sensitive.

Table and column names in the examples are placeholders. Replace them.

## Reading the output

Every script returns a `Status` column:

| Status | Meaning |
|---|---|
| `PASS` | No issue found |
| `WARN` | Below threshold, review recommended |
| `FAIL` | Above threshold, needs resolution before sign-off |

Thresholds are set in the configuration block.

## Limitations

These are checks, not fixes. They tell you what is wrong, not what to do about it. Deciding whether a mismatch is a defect or an accepted difference is a business conversation, not a query.
