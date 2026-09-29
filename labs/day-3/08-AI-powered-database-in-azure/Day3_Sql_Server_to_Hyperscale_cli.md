# Challenge 2 Onward: SQL Server to Azure SQL Database Hyperscale with Azure CLI

Run the commands in **PowerShell as Administrator** on the source SQL Server VM. Replace every value marked with angle brackets before continuing.

This procedure uses:

- core `az sql` commands to create the Azure SQL logical server and Hyperscale database;
- core `az network` commands to create private connectivity;
- the `datamigration` Azure CLI extension for assessment, schema migration, DMS, SHIR registration, migration, and monitoring.

> Azure SQL Database supports **offline** DMS migration. It does not use the SQL Managed Instance online backup/restore and cutover workflow. Stop application writes before starting the data migration. There is no separate cutover command for this target.

## 1. Set the lab values

```powershell
$subscriptionId = "<subscription-id>"
$location = "<azure-region>"

$resourceGroup = "<target-resource-group>"
$networkResourceGroup = "<vnet-resource-group>"

$vnetName = "<vnet-name>"
$privateEndpointSubnetName = "<private-endpoint-subnet-name>"

$sourceSqlServer = "<source-vm-private-name-or-ip>,1433"
$sourceDatabase = "eShop"
$sourceSqlUser = "<source-sql-migration-user>"

# Must be globally unique, lowercase, and contain only letters, numbers, and hyphens.
$targetSqlServerName = "<globally-unique-sql-server-name>"
$targetDatabase = "eShop"
$targetSqlAdmin = "<target-sql-admin-name>"

$dmsName = "<sql-migration-service-name>"
$privateEndpointName = "$targetSqlServerName-pe"
$privateDnsZoneName = "privatelink.database.windows.net"
$privateDnsLinkName = "$vnetName-sql-link"
$dnsZoneGroupName = "sql-dns-zone-group"

$assessmentOutput = "C:\Migration\Assessment"
$schemaOutput = "C:\Migration\Schema"
$shirMsi = "C:\Migration\IntegrationRuntime.msi"
```

Enter the source and target SQL passwords without placing them in this file:

```powershell
$sourceSecurePassword = Read-Host "Source SQL password" -AsSecureString
$sourceSqlPassword = [System.Net.NetworkCredential]::new("", $sourceSecurePassword).Password

$targetSecurePassword = Read-Host "New Azure SQL administrator password" -AsSecureString
$targetSqlPassword = [System.Net.NetworkCredential]::new("", $targetSecurePassword).Password
```

Create the local working folders:

```powershell
New-Item -ItemType Directory -Path $assessmentOutput -Force | Out-Null
New-Item -ItemType Directory -Path $schemaOutput -Force | Out-Null
```

## 2. Install and verify the Azure CLI components

```powershell
az version
az login
az account set --subscription $subscriptionId
az account show --query "{subscription:name, subscriptionId:id, tenantId:tenantId}" --output table
```

Install or update the `datamigration` extension:

```powershell
az extension add --name datamigration --upgrade --yes
az extension show --name datamigration --query "{name:name, version:version}" --output table
```

Confirm that Azure CLI is version 2.75.0 or later and that the required command groups are available:

```powershell
az datamigration get-assessment --help
az datamigration sql-server-schema --help
az datamigration sql-service --help
az datamigration sql-db --help
az sql db create --help
```

Register the required Azure resource providers:

```powershell
az provider register --namespace Microsoft.DataMigration
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.Network
```

Wait until all three providers report `Registered`:

```powershell
az provider show --namespace Microsoft.DataMigration --query registrationState --output tsv
az provider show --namespace Microsoft.Sql --query registrationState --output tsv
az provider show --namespace Microsoft.Network --query registrationState --output tsv
```

## 3. Challenge 2: Run the migration-readiness assessment

```powershell
$sourceMasterConnection = "Server=$sourceSqlServer;Initial Catalog=master;User ID=$sourceSqlUser;Password=$sourceSqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"

az datamigration get-assessment `
    --connection-string "$sourceMasterConnection" `
    --output-folder "$assessmentOutput" `
    --overwrite
```

List the generated assessment files:

```powershell
Get-ChildItem -Path $assessmentOutput -Recurse
```

Open the generated JSON report and check the following sections before continuing:

- `TargetReadinesses.AzureSqlDatabase`
- `DatabaseAssessments`
- `IssueCategory`
- `ImpactedObjects`
- `MoreInformation`
- `Errors`

Do not continue until blocking Azure SQL Database compatibility errors for `eShop` are resolved.

## 4. Challenge 3: Create Database Migration Service

Create or update the target resource group:

```powershell
az group create `
    --name $resourceGroup `
    --location $location `
    --output table
```

Create the SQL Migration Service in the same Azure region as the target database:

```powershell
az datamigration sql-service create `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --location $location `
    --output table
```

Verify the service:

```powershell
az datamigration sql-service show `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --output table
```

## 5. Install and register the self-hosted integration runtime

Download the current self-hosted integration runtime installer:

```powershell
Invoke-WebRequest `
    -Uri "https://aka.ms/sql-migration-shir-download" `
    -OutFile $shirMsi
```

Get a DMS authentication key:

```powershell
$shirAuthKey = az datamigration sql-service list-auth-key `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --query "authKey1" `
    --output tsv
```

Install SHIR and register this VM with DMS:

```powershell
az datamigration register-integration-runtime `
    --auth-key "$shirAuthKey" `
    --ir-path "$shirMsi"
```

Verify that the integration runtime node is online:

```powershell
az datamigration sql-service list-integration-runtime-metric `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --output table
```

Do not continue until the SHIR node reports online and healthy.

## 6. Challenge 4 replacement: Create an Azure SQL Database Hyperscale target

Create the Azure SQL logical server with SQL authentication:

```powershell
az sql server create `
    --resource-group $resourceGroup `
    --name $targetSqlServerName `
    --location $location `
    --admin-user $targetSqlAdmin `
    --admin-password "$targetSqlPassword" `
    --enable-public-network false `
    --output table
```

Create the empty `eShop` Hyperscale database:

```powershell
az sql db create `
    --resource-group $resourceGroup `
    --server $targetSqlServerName `
    --name $targetDatabase `
    --edition Hyperscale `
    --family Gen5 `
    --capacity 2 `
    --compute-model Provisioned `
    --backup-storage-redundancy Local `
    --zone-redundant false `
    --output table
```

Verify that the database is online and uses Hyperscale:

```powershell
az sql db show `
    --resource-group $resourceGroup `
    --server $targetSqlServerName `
    --name $targetDatabase `
    --query "{name:name, status:status, edition:edition, sku:sku.name, capacity:sku.capacity, location:location}" `
    --output table
```

## 7. Create the Azure SQL private endpoint and private DNS

Get the VNet, subnet, and SQL server resource IDs:

```powershell
$vnetId = az network vnet show `
    --resource-group $networkResourceGroup `
    --name $vnetName `
    --query id `
    --output tsv

$privateEndpointSubnetId = az network vnet subnet show `
    --resource-group $networkResourceGroup `
    --vnet-name $vnetName `
    --name $privateEndpointSubnetName `
    --query id `
    --output tsv

$targetSqlServerId = az sql server show `
    --resource-group $resourceGroup `
    --name $targetSqlServerName `
    --query id `
    --output tsv
```

Enable private endpoints on the selected subnet:

```powershell
az network vnet subnet update `
    --resource-group $networkResourceGroup `
    --vnet-name $vnetName `
    --name $privateEndpointSubnetName `
    --private-endpoint-network-policies Disabled `
    --output table
```

Create the private endpoint:

```powershell
az network private-endpoint create `
    --resource-group $resourceGroup `
    --name $privateEndpointName `
    --location $location `
    --subnet $privateEndpointSubnetId `
    --private-connection-resource-id $targetSqlServerId `
    --group-ids sqlServer `
    --connection-name "$targetSqlServerName-connection" `
    --output table
```

Create the Azure SQL private DNS zone:

```powershell
az network private-dns zone create `
    --resource-group $resourceGroup `
    --name $privateDnsZoneName `
    --output table
```

Link the private DNS zone to the source VM's VNet:

```powershell
az network private-dns link vnet create `
    --resource-group $resourceGroup `
    --zone-name $privateDnsZoneName `
    --name $privateDnsLinkName `
    --virtual-network $vnetId `
    --registration-enabled false `
    --output table
```

Get the private DNS zone ID and associate it with the private endpoint:

```powershell
$privateDnsZoneId = az network private-dns zone show `
    --resource-group $resourceGroup `
    --name $privateDnsZoneName `
    --query id `
    --output tsv

az network private-endpoint dns-zone-group create `
    --resource-group $resourceGroup `
    --endpoint-name $privateEndpointName `
    --name $dnsZoneGroupName `
    --private-dns-zone $privateDnsZoneId `
    --zone-name "sql" `
    --output table
```

Confirm that public network access remains disabled:

```powershell
az sql server show `
    --resource-group $resourceGroup `
    --name $targetSqlServerName `
    --query "{server:fullyQualifiedDomainName, publicNetworkAccess:publicNetworkAccess}" `
    --output table
```

Confirm that the private endpoint connection is approved:

```powershell
az network private-endpoint show `
    --resource-group $resourceGroup `
    --name $privateEndpointName `
    --query "privateLinkServiceConnections[].{name:name,status:privateLinkServiceConnectionState.status}" `
    --output table
```

## 8. Migrate the `eShop` schema with the `datamigration` extension

Build the source and target connection strings:

```powershell
$targetSqlFqdn = az sql server show `
    --resource-group $resourceGroup `
    --name $targetSqlServerName `
    --query fullyQualifiedDomainName `
    --output tsv

$sourceDatabaseConnection = "Server=$sourceSqlServer;Initial Catalog=$sourceDatabase;User ID=$sourceSqlUser;Password=$sourceSqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"
$targetDatabaseConnection = "Server=tcp:$targetSqlFqdn,1433;Initial Catalog=$targetDatabase;User ID=$targetSqlAdmin;Password=$targetSqlPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
```

Migrate the schema:

```powershell
az datamigration sql-server-schema `
    --action MigrateSchema `
    --src-sql-connection-str "$sourceDatabaseConnection" `
    --tgt-sql-connection-str "$targetDatabaseConnection" `
    --output-folder "$schemaOutput"
```

Review the command output and the files in the schema output folder:

```powershell
Get-ChildItem -Path $schemaOutput -Recurse
```

Do not start the data migration if schema migration reports unresolved errors.

## 9. Start the offline data migration to Hyperscale

Stop all application writes to the source `eShop` database.

Get the resource IDs required by DMS:

```powershell
$migrationServiceId = az datamigration sql-service show `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --query id `
    --output tsv

$targetSqlServerId = az sql server show `
    --resource-group $resourceGroup `
    --name $targetSqlServerName `
    --query id `
    --output tsv
```

Create and start the offline migration:

```powershell
az datamigration sql-db create `
    --resource-group $resourceGroup `
    --sqldb-instance-name $targetSqlServerName `
    --target-db-name $targetDatabase `
    --scope $targetSqlServerId `
    --migration-service $migrationServiceId `
    --source-database-name $sourceDatabase `
    --source-sql-connection `
        authentication="SqlAuthentication" `
        data-source="$sourceSqlServer" `
        user-name="$sourceSqlUser" `
        password="$sourceSqlPassword" `
        encrypt-connection=true `
        trust-server-certificate=true `
    --target-sql-connection `
        authentication="SqlAuthentication" `
        data-source="$targetSqlFqdn" `
        user-name="$targetSqlAdmin" `
        password="$targetSqlPassword" `
        encrypt-connection=true `
        trust-server-certificate=false `
    --no-wait
```

## 10. Monitor the migration

Show the migration summary:

```powershell
az datamigration sql-db show `
    --resource-group $resourceGroup `
    --sqldb-instance-name $targetSqlServerName `
    --target-db-name $targetDatabase `
    --output table
```

Show detailed migration status:

```powershell
az datamigration sql-db show `
    --resource-group $resourceGroup `
    --sqldb-instance-name $targetSqlServerName `
    --target-db-name $targetDatabase `
    --expand MigrationStatusDetails `
    --output jsonc
```

Show only the provisioning and migration states:

```powershell
az datamigration sql-db show `
    --resource-group $resourceGroup `
    --sqldb-instance-name $targetSqlServerName `
    --target-db-name $targetDatabase `
    --expand MigrationStatusDetails `
    --query "{provisioningState:properties.provisioningState,migrationStatus:properties.migrationStatus}" `
    --output table
```

Rerun the preceding status command until:

```text
provisioningState: Succeeded
migrationStatus:   Succeeded
```

List migrations attached to the DMS instance:

```powershell
az datamigration sql-service list-migration `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --output table
```

## 11. Complete the exercise

Confirm that the target database remains online:

```powershell
az sql db show `
    --resource-group $resourceGroup `
    --server $targetSqlServerName `
    --name $targetDatabase `
    --query "{name:name,status:status,edition:edition,sku:sku.name,capacity:sku.capacity}" `
    --output table
```

Clear passwords and the SHIR registration key from the PowerShell session:

```powershell
$sourceSqlPassword = $null
$targetSqlPassword = $null
$sourceSecurePassword = $null
$targetSecurePassword = $null
$shirAuthKey = $null
$sourceMasterConnection = $null
$sourceDatabaseConnection = $null
$targetDatabaseConnection = $null
```

Do not delete DMS or the migration resource until migration status is `Succeeded` and target data validation has been completed.

## 12. Optional cleanup after validation

Delete the completed migration resource:

```powershell
az datamigration sql-db delete `
    --resource-group $resourceGroup `
    --sqldb-instance-name $targetSqlServerName `
    --target-db-name $targetDatabase `
    --force true `
    --yes
```

Delete the SQL Migration Service:

```powershell
az datamigration sql-service delete `
    --resource-group $resourceGroup `
    --sql-migration-service-name $dmsName `
    --yes
```

## Command references

- <https://learn.microsoft.com/cli/azure/datamigration>
- <https://learn.microsoft.com/cli/azure/datamigration/sql-db>
- <https://learn.microsoft.com/cli/azure/datamigration/sql-service>
- <https://learn.microsoft.com/cli/azure/sql/db>
- <https://learn.microsoft.com/azure/private-link/tutorial-private-endpoint-sql-cli>
- <https://learn.microsoft.com/azure/dms/migration-dms-powershell-cli>
