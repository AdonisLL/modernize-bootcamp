# Building the Zava Lending Lab on Azure SQL Hyperscale

## Copy all the scripts from this [folder](https://github.com/microsoft/azuresqlfoundations/tree/main/cloudborn)

## Tool install (windows only): Install `sqlsim.exe`

Complete this section before running any of the lab scripts.

`sqlsim.exe` does not have an MSI or setup wizard. It is a standalone Microsoft command-line utility distributed in the public [`microsoft/bobsql`](https://github.com/microsoft/bobsql) GitHub repository. The only runtime dependency is **Microsoft ODBC Driver 18 for SQL Server**.

### 1. Install or verify Microsoft ODBC Driver 18

Download Microsoft ODBC Driver 18 for SQL Server from:

<https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server>

After installation, open a new PowerShell window and verify that Windows can find it:

```powershell
Get-OdbcDriver -Name "ODBC Driver 18 for SQL Server"
```

The command should return an installed driver. If it returns nothing, install the x64 ODBC Driver 18 package before continuing.

### 2. Download `sqlsim.exe`  

For this lab, store the executable at:

```text
C:\temp\sqlsim.exe
```

Open PowerShell and run:

```powershell
$sqlsimDirectory = "C:\temp"
$sqlsimPath = Join-Path $sqlsimDirectory "sqlsim.exe"

New-Item -ItemType Directory -Path $sqlsimDirectory -Force | Out-Null

Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/microsoft/bobsql/master/hyperscale-developer/utilities/sqlsim/sqlsim.exe" `
    -OutFile $sqlsimPath

Unblock-File -Path $sqlsimPath
```

This downloads the executable from the Microsoft-owned repository. The commands in this guide explicitly pass this location to each applicable script.

If your organization blocks direct executable downloads, download or clone the repository from <https://github.com/microsoft/bobsql>, locate:

```text
hyperscale-developer\utilities\sqlsim\sqlsim.exe
```

and copy that file to:

```text
C:\temp\sqlsim.exe
```

### 3. Verify the tool

Run:

```powershell
Test-Path "C:\temp\sqlsim.exe"

& "C:\temp\sqlsim.exe" --version

& "C:\temp\sqlsim.exe" --help
```

Expected results:

- `Test-Path` returns `True`;
- `--version` prints the SQL Workload Simulator version;
- `--help` prints connection, authentication, query, and workload options.

Do not continue if Windows reports that the executable is missing or if the ODBC driver cannot be loaded.

### Using `sqlsim.exe` from this location

The scripts have a different built-in default path, so every database-related command in this guide supplies `-SqlsimPath` explicitly:

```powershell
.\step1-setup-db.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<database-name>" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

Use this path for Steps 1, 2, 3, 4, and 6. Step 5 does not use `sqlsim.exe`. If you later move the executable, replace `C:\temp\sqlsim.exe` in every applicable command.

Official usage documentation is available at:

<https://github.com/microsoft/bobsql/blob/master/hyperscale-developer/utilities/sqlsim/sqlsim-usage.md>


This walkthrough is written for infrastructure architects who may not work with SQL every day. The objective is not to memorize T-SQL. Focus on authentication, connectivity, data placement, workload shape, scale, isolation, and what each operation changes.

> **Important:** These are the **cloud-born, build-from-scratch** scripts. They are not post-migration scripts. Step 1 drops and recreates core objects, Step 4 drops and recreates the scale-demo objects, and Step 6 clears the scale tables before loading them. Do not point these scripts at a database containing data that must be preserved.

## Architecture at a glance

The exercise has four main parts:

1. **PowerShell orchestration** runs on the administrator's workstation.
2. **Microsoft Entra authentication** supplies a short-lived access token for Azure SQL.
3. **`sqlsim.exe`** opens SQL connections and submits SQL scripts or individual SQL commands.
4. **Azure SQL Database Hyperscale** stores the schema and data and performs the database work.

Step 5 is different: it is a local data-generation operation and does not connect to Azure SQL. Step 6 transfers that locally generated data to Azure.

The resource group is the Azure management boundary that contains the lab resources. The PowerShell scripts do not take a resource-group parameter. They reach the database by using the Azure SQL logical server's fully qualified domain name and the database name.

## What is `sqlsim.exe`?

The executable used by these scripts is:

```text
C:\temp\sqlsim.exe
```

`sqlsim.exe` is a command-line SQL workload and query execution tool. It can:

- connect to SQL Server or Azure SQL through ODBC;
- authenticate with Windows credentials, SQL credentials, Microsoft Entra authentication, or an access token;
- execute a SQL file with `-i`;
- execute an inline query with `-Q`;
- run repeated or concurrent workloads;
- print verbose execution information and metrics.

It is **not** the Azure SQL server, the Hyperscale database, or an Azure resource. It is a client executable running on the local machine, similar in role to `sqlcmd`, but it also supports workload simulation and concurrency features used elsewhere in the lab.

The common options used in these scripts are:

| Option | Meaning |
|---|---|
| `-S` | Azure SQL logical server name, sometimes including `tcp:` and port `1433` |
| `-d` | Target database name |
| `-T` | Microsoft Entra access token |
| `-i` | SQL input file to execute |
| `-Q` | Inline SQL command to execute |
| `-v` | Verbose output |
| `-q` | Quiet output |

For example, Steps 1, 3, and 4 acquire an Azure SQL access token and then use `sqlsim.exe` to submit a complete `.sql` file:

```powershell
& $SqlsimPath -S $Server -d $Database -T $token -i $sqlFile -v
```

Step 6 uses two different data paths:

- `sqlsim.exe` runs control commands such as cleanup, index rebuilds, and row-count validation.
- .NET `SqlBulkCopy` streams the large CSV data into Azure SQL efficiently.

This distinction matters architecturally: control-plane-style database commands and high-volume data movement do not have to use the same client mechanism.

## Before students begin

Students need:

- access to the Azure subscription and the `bootcamp` resource group;
- the Azure SQL logical server name and database name;
- an Azure SQL Database configured with the Hyperscale service tier;
- network access to the Azure SQL endpoint on TCP port `1433`;
- an Azure firewall rule, private endpoint path, or other approved connectivity route;
- Microsoft Entra permission to connect to and modify the target database;
- the Az PowerShell module and an authenticated Azure session;
- `sqlsim.exe` at `C:\temp\sqlsim.exe`, supplied to each applicable script with `-SqlsimPath`;
- sufficient local disk space for the CSV files generated in Step 5;
- a SQL client library for Step 6, preferably `Microsoft.Data.SqlClient` supplied by the PowerShell `SqlServer` module.

Sign in before running the database steps:

```powershell
Connect-AzAccount
```

Change to this folder:

```powershell
Set-Location C:\Documents\Github\azuresqlfoundations\cloudborn
```

Use the actual logical server and database values in place of the examples below. The server normally resembles `server-name.database.windows.net`.

## Step 1: Create the base database objects and sample data

Run:

```powershell
.\step1-setup-db.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<database-name>" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

### What the script does

The PowerShell wrapper:

1. verifies that `sqlsim.exe` exists;
2. verifies that `01-setup-zava-lending-db.sql` exists;
3. requests a Microsoft Entra token for `https://database.windows.net/`;
4. passes the server, database, token, and SQL file to `sqlsim.exe`;
5. checks the process exit code and reports success or failure.

The SQL file drops and recreates the base Zava Lending schema. It creates objects including:

- `dbo.Applicants`;
- `dbo.LoanHistory`;
- `dbo.LoanApplications`;
- `dbo.LoanDecisions`;
- the append-only ledger table `dbo.LoanDecisionAudit`;
- supporting indexes.

It then seeds 1,000 applicants, 1,000 historical loans, and a pending loan application.

### What students should learn

- **Authentication is token based.** No SQL password is embedded in the script.
- **The client and database engine are separate.** PowerShell and `sqlsim.exe` submit work; Azure SQL executes it.
- **A successful connection is not enough.** The signed-in identity also needs database permissions to create, alter, and drop objects.
- **Idempotent does not mean non-destructive.** The script can be rerun because it drops and recreates objects, but existing data in those objects is lost.
- **Indexes are architecture choices.** They improve particular access patterns but consume storage and add work to data modifications.
- **Ledger is a data-integrity capability.** The audit table demonstrates a tamper-evident, append-only design for regulated decision records.

### What students should observe

- The script displays `Token acquired`.
- `sqlsim.exe` shows the SQL batches being executed in verbose mode.
- The final output reports successful database setup.
- In the database, the base tables and indexes now exist.
- `Applicants` and `LoanHistory` each contain 1,000 rows.

## Step 2: Named replica reporting queries — skipped

The optional command would be:

```powershell
.\step2-replica-queries.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<named-replica-database-name>" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

I did **not** run this step because the exercise did not use a configured named replica.

### What the script would do

It runs `02-named-replica-reporting.sql` against a named replica. The queries verify that the replica is read-only and run reporting examples such as an underwriter dashboard, credit-risk analysis, and portfolio analytics.

### What students should learn

- A named replica is an additional, read-only Hyperscale compute endpoint.
- Read-heavy reporting can be isolated from transactional activity.
- Workload isolation is an architectural decision: it can protect the primary workload, but it introduces another compute resource, cost, security surface, and operational dependency.
- Skipping this step does not prevent Steps 3–6 from running against the primary database.

### What students would observe

If a named replica were configured correctly, write operations would not be allowed there, while reporting queries would return data without running on the primary compute endpoint.

## Step 3: Add narrative text and full-text search

Run:

```powershell
.\step3-add-narratives.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<database-name>" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

### What the script does

The wrapper obtains a new Azure SQL token and uses `sqlsim.exe` to run `03-add-loan-narratives.sql`.

The SQL script:

- adds a nullable `LoanNarrative` column to `dbo.LoanHistory`;
- ensures the column is `NVARCHAR(4000)`;
- fills rich narrative text for the original 100 loan records;
- creates the `FT_ZavaLending` full-text catalog if needed;
- creates a full-text index on `LoanNarrative` with automatic change tracking.

### What students should learn

- Structured columns and narrative text serve different query needs.
- Full-text search requires database objects beyond an ordinary table column.
- Search features have schema, indexing, storage, and maintenance implications.
- The script is written to tolerate reruns by checking whether the column, catalog, and index already exist.
- This step prepares a later comparison between lexical full-text search and semantic/vector search.

### What students should observe

- The script reports that narratives were added.
- The full-text catalog and index are created.
- The first 100 historical loans have readable narrative descriptions.
- Full-text indexing is a database-engine feature; no separate search server is deployed for this exercise.

## Step 4: Create the scale-test schema

Run:

```powershell
.\step4-scale-schema.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<database-name>" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

### What the script does

The wrapper uses `sqlsim.exe` to execute `04-scale-schema.sql`.

The SQL script first checks that the base `LoanHistory` table exists. It then drops and recreates the scale-demo objects:

- `dbo.LoanHistoryExpanded`, a rowstore table for the larger loan population;
- `dbo.LoanTransactions`, a large fact table with a clustered columnstore index;
- `dbo.MonthlyPortfolioSnapshot`, a summarized table with a clustered columnstore index;
- `dbo.PaymentProcessingBatch`, an audit/workload sink;
- `dbo.vw_AllLoans`, which combines the original and expanded loan histories.

`LoanTransactions` also receives a rowstore nonclustered index for loan-level point lookups. Its clustered columnstore index is ordered by transaction date to support segment elimination for date-filtered analytical queries.

### What students should learn

- **Rowstore and columnstore address different workload shapes.** Rowstore is generally suitable for selective lookups; columnstore is designed for compression and analytical scans over many rows.
- **Mixed workloads may require both index types.** The transaction table has columnstore for analytics and a rowstore index for point access.
- **Denormalization can be intentional.** Attributes such as region and channel are stored in the transaction fact table to make analytical scans efficient.
- **Data organization affects pruning.** Ordering columnstore data by date helps the engine skip segments outside a requested date range.
- **Schema isolation protects the original demo data.** Expanded data is stored separately and exposed through a union view.
- **Rerunning this step deletes existing scale-demo data.**

### What students should observe

- The base tables remain present.
- The new scale tables are initially empty.
- Columnstore indexes exist on the two analytical tables.
- `vw_AllLoans` provides a single logical query surface over two physical tables.

## Step 5: Generate scale data locally

Run with the defaults:

```powershell
.\step5-generate-data.ps1
```

For a smaller classroom exercise, students can deliberately choose lower values:

```powershell
.\step5-generate-data.ps1 `
    -LoanCount 100000 `
    -TransactionsPerLoan 50
```

### What the script does

This step does **not** connect to Azure and does not use `sqlsim.exe`.

It generates three headerless CSV files in the local `data` folder:

- `loan-history-expanded.csv`;
- `loan-transactions.csv`;
- `monthly-snapshots.csv`.

With default parameters, it generates 500,000 expanded loans and then creates transaction events for eligible loans. Events include disbursements, interest accruals, payments, occasional late fees, and defaults. It also creates monthly portfolio summaries across loan type, region, channel, and credit-score band.

The generator uses:

- a fixed random seed so repeated runs are reproducible;
- .NET `StreamWriter` instead of the slower PowerShell object pipeline;
- buffered writes so millions of rows can be produced efficiently;
- overwrite behavior, so rerunning replaces the existing CSV files.

### What students should learn

- **Data generation consumes local resources.** CPU, memory, disk capacity, and disk throughput matter before Azure is involved.
- **Data volume is part of infrastructure design.** A test with 1,000 rows does not represent the storage, transfer, indexing, or query behavior of a multi-million-row workload.
- **Synthetic data should be reproducible.** A fixed random seed makes comparisons between runs more meaningful.
- **The number of transactions is data dependent.** It varies with loan outcome, age, term, and payoff/default behavior; use the script's final count rather than assuming an exact total.
- **Local staging creates a data-transfer boundary.** The generated files must later cross the network into Azure.

### What students should observe

- Progress is shown while loans and transactions are generated.
- The final output displays the actual row count for each file.
- The transaction CSV is much larger than the loan and snapshot files.
- No Azure token is requested and no Azure SQL activity should appear during this step.

## Step 6: Bulk-load data into Hyperscale

Run:

```powershell
.\step6-load-data.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<database-name>" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

If Step 5 used a custom output directory, pass the same directory:

```powershell
.\step6-load-data.ps1 `
    -Server "<server-name>.database.windows.net" `
    -Database "<database-name>" `
    -DataDir "C:\temp\scaledata" `
    -SqlsimPath "C:\temp\sqlsim.exe"
```

### What the script does

The script:

1. loads an available SQL client library;
2. confirms that all three CSV files exist;
3. obtains an Azure SQL access token;
4. confirms that `sqlsim.exe` exists;
5. uses `sqlsim.exe` to truncate `LoanTransactions` and `MonthlyPortfolioSnapshot` and delete rows from `LoanHistoryExpanded`;
6. opens encrypted Azure SQL connections with the access token;
7. reads the CSV files as streams;
8. sends rows in batches through .NET `SqlBulkCopy`;
9. rebuilds the transaction columnstore index;
10. uses `sqlsim.exe` to query and display final row counts;
11. attempts to create workload stored procedures if the expected SQL file is present.

The default bulk-copy batch size is 100,000 rows. Streaming and batching prevent the script from holding the entire data set in memory.

The access token is acquired again after a long load because the original token may expire while millions of rows are being transferred and indexed.

### What students should learn

- **Bulk ingestion is different from row-by-row insertion.** Batching greatly reduces client and network overhead.
- **The end-to-end path includes local disk, network, gateway, database compute, transaction logging, and storage.** Any of these can become the limiting component.
- **Hyperscale separates compute and storage architecture, but ingestion still consumes database resources.**
- **Index design affects load strategy.** The columnstore index is rebuilt after loading to improve data organization and segment elimination.
- **Long-running automation must account for token lifetime.**
- **Rerunning the step replaces the scale data.** It is repeatable, but destructive to the three scale tables.
- **Validation is part of automation.** A zero process exit code is useful, but students should also compare final row counts with Step 5's generated counts.

### What students should observe

- The selected SQL client library is printed first.
- Existing scale data is cleared before the load.
- Row-transfer progress appears at each batch boundary.
- The transaction load takes much longer than the other two loads.
- The columnstore index rebuild uses additional database compute and can be observed in Azure SQL monitoring.
- Final row counts should match the generated CSV counts.

### Important Step 6 warning

The script treats a missing workload-procedure file, or a failure while creating those procedures, as a warning rather than a fatal data-load error. Therefore, `Data Load Complete` proves that the scale data path finished, but it does not by itself prove that every later workload procedure exists.

Students should read the end of the console output and verify whether it says:

```text
Workload procs created successfully.
```

If it instead reports that the file was not found or that procedure setup returned a nonzero exit code, the data is still loaded, but the later workload exercise requires that issue to be corrected first.

## What the completed environment represents

After Steps 1 and 3–6, the database contains:

- a small operational lending model;
- sample applicants, historical loans, applications, decisions, and an append-only audit design;
- narrative text with full-text indexing;
- a much larger synthetic loan population;
- a high-volume transaction fact table using clustered columnstore;
- monthly analytical snapshots;
- a combined view over the original and expanded loans.

This gives architects a controlled environment in which to discuss:

- Microsoft Entra authentication and least privilege;
- public or private connectivity to Azure SQL;
- Hyperscale compute and storage behavior;
- operational versus analytical access patterns;
- rowstore versus columnstore;
- bulk ingestion and network throughput;
- indexing cost and data organization;
- read-scale isolation with an optional named replica;
- observability during long-running data and index operations;
- repeatability, destructive operations, and recovery planning.

## Recommended verification checklist

After each run, verify more than the green success message:

- [ ] The command targeted the intended server and database.
- [ ] The target database is in the expected `bootcamp` environment.
- [ ] Microsoft Entra token acquisition succeeded.
- [ ] The `sqlsim.exe` exit code was zero where the script requires it.
- [ ] No unexpected warnings appeared at the end of Step 6.
- [ ] Step 1 produced 1,000 applicants and 1,000 historical loans.
- [ ] Step 3 populated narrative text and created a full-text index.
- [ ] Step 4 created the rowstore, columnstore, view, and workload-sink objects.
- [ ] Step 5 generated all three local CSV files and reported their row counts.
- [ ] Step 6 loaded row counts matching the generated files.
- [ ] Workload stored procedures exist before attempting a later workload test.
- [ ] Azure monitoring shows the expected resource activity during loading and index rebuild.

## Cleanup and cost awareness

The local CSV files can consume substantial disk space. Delete them only after confirming they are no longer needed for a rerun.

Azure SQL Hyperscale compute and any named replica continue to incur cost while provisioned. At the end of the class, follow the lab owner's cleanup or scale-down instructions for the resources in the `bootcamp` resource group. Do not delete the resource group unless you have explicit permission, because it may contain shared resources.
