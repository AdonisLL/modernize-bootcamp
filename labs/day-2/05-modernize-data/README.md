# Lab 05: Database Modernization Bootcamp

## SQL Server to Azure SQL Database — Student Migration Challenges

**Scenario:** Migrate the eShop database from SQL Server on VM to Azure SQL Database by using Azure Database Migration Service (DMS).

Lab 04 now provisions exactly one target. The standard path selects
`LAB04_DATABASE_MODE=azureSql`; complete the Azure SQL Database challenges
below. If an instructor selected `sqlMi`, use the SQL Managed Instance challenge
as the target-specific path and do not expect an Azure SQL logical server or
private endpoint to exist.

Now that the application is upgraded and moved to Azure PaaS services, it is time to modernize and migrate the database. 

***Security rule:*** *Never expose passwords, storage keys, SAS tokens, or connection strings in screenshots or submissions. Do not enable public RDP or public Azure SQL access unless the instructor explicitly requires it.*

Learning objectives

Students will learn to:

* Gather information about a SQL server database
* Prepare and assess a SQL Server database for migration to Azure.
* Learn about diffenent authentication mechanisms in SQL server
* Learn about different types of backups and migration techniques
* Run an assessment of the source SQL Server database, analyze the report
* Use the managed database target selected during Lab 04.
* Configure private connectivity to the Azure SQL Database from both the Azure VM and also target PaaS services
* Create Azure Data Migration Service (DMS) and configure to run the "Self hosted Integration Runtime" on the Azure VM.
* Run DMS offline migration to Azure SQLDB
* Run and monitor an offline migration. Verify migrated data by query only.
* When `sqlMi` was selected in Lab 04, run DMS online migration to SQL MI and verify migration.
* Configure the application with the database FQDN exported by Lab 04.
* Document differences between Azre SQLDB and Azire SQL MI and lessons learned. 

## Challenge 1 — Validate the source database

### Student tasks

1. Connect to the provided VM using the instructor-approved method.
2. Confirm that SQL Server services are running - service named "SQL Server (MSSQLSERVER)"
3. Determine the database credential the retail app is using. You can use Github coplilot chat to find out from the application source codebase.
4. Connect to the local SQL Server with SQL Server Management Studio (SSMS) using "sa" SQL login given to you
5. Record the SQL Server version,edition - right click on the server and type "new query". Execute the following SQL

```sql
Use master;
select @@version ;
```
7. Right click on database eshop and click on peroperties to determine database size, collation, disk file name and size of database files and "recovery mode", like [![this](./images/Challenge_1_db_properties.png)](./images/Challenge_1_db_properties.png)
8. While there, also note down all the "page" names displayed when checking on database "properties" section.
9. <u>Note do this only if this database VM is on Azure or some other cloud -->  </u>Map the VM data drives to azure disks. You can do find the SQL data and log file information from the "Files" page. Besides size what else is different between the two disks and why so ?
10. Verify that the VM has no unintended public exposure.
11. What are the different ways tuauthenticate to this eshop SQL database ?
12. (Research on this) What is a logical and physical backup of SQL server ? How is recovery mode and logical backup related ?
13. Put the database into full recovery mode in SSMS running this query

```sql
alter database eshop set recovery full ;
```

11. Run this query using SSMS. Investigate the results.

```text
DBCC CHECKDB (N'eShop') ;
```

## Success criteria

* SSMS connects to the source instance.
* The student records the source version, edition etc.
* You can explain at least 4 different authentication mechanisms and show at least 2 ways to connnect
* You can explain recovery model and different backups.



## Challenge 2 — Pre-migration assessment of the source database 

SSMS 22 is the latest version of Microsoft’s SQL Server Management Studio, a 64-bit graphical tool for managing, developing, and administering SQL Server and Azure databases. We will use it in the lab to perform the database assessment, querying and performing the necessary backups to upload to Azure storage for the migration. To launch the tool, locate on the labs desktop the shortcut:

 ![SSMS](./images/ssms_22.png)
## Student tasks

1. Using SSMS, right click on the server and choose "Migrate SQL Server"
 ![SSMS](./images/Challenge_2_assessment_launch_1.png)
2. <u>Do not Migrate or Upgrade the database</u>. Run a "Migration rediness assessment". An html file will open in your browser once the assessment completes. This is the report.
 ![SSMS](./images/Challenge_2_assessment_launch_2.png)
3. Investigate the report. Find out compatibility issues with different SQL targets ![Assessment](./images/Challenge_2_assessment_full_report.png)


## Success criteria

* You learn different options of running SQL on Azure
* Understand the assessment report and the comptatibility issues.

## Challenge 3 — Create the required azure resources

Azure SQL Managed Instance, the target database service, is already provisionned on your lab subscription to save time. You will need to validate that *System Assigned Managed Identity* is enabled for the server.  

In this part of the lab you will create the necesary Azure resources to perform the migration. Deploy the resources in the same region that Azure SQL MI is deployed.  You will:

- Create a resource provider (if it does not exist) in the subscription for DMS.
- Deploy an Azure storage account and a blob container to store database and transaction log file backups.
- Deploy an Azure Database Migration Service (DMS) to migrate the database.


## Student tasks

### 1. Resource provider

From the Azure portal, go to *Subscriptions*.  Clicck on *Ressource Providers* and confirm that *Microsoft.DataMigration* is registered.  If it is not, then register it.

![ResourceProvider](./images/dms_resource_provider.png)

### 2. Azure SQL MI System Assigned Managed Identity

Locate the pre-deployed Azure SQL Managed instance in your lab subscription. Go to the *Identity* blade and confirm that *System Assigned Managed Identity* is enabled.  If it is not then enable it.

![SQLMI_SAMI](./images/SQLMI_SAMI.png)

### 3. Storage Account

Provision an Azure Storage Account and create a Blob container. 

![Storage1](./images/Storage_1.png)
![Storage2](./images/Storage_2.png)
![Storage3](./images/Storage_3.png)
![Storage4](./images/Storage_4.png)

Once the storage account is created you need to grant to your current Azure user the permission to view and list Blob containers.  Do this via IAM.  Assign the *Storage Blob Data Owner* role.

![Storage5](./images/Storage_5.png)
![Storage6](./images/Storage_6.png)
![Storage7](./images/Storage_7.png)
![Storage8](./images/Storage_8.png)

You will also need to grant the Azure SQL MI, System Managed Identity the blob reader permission. The identity has the same name as the SQL MI instance your lab subscription.

![Storage9](./images/Storage_9.png)
![Storage10](./images/Storage_10.png)

Create a Blob container in the storage account and a folder within the container.

![Storage11](./images/Storage_11.png)
![Storage12](./images/Storage_12.png)

### 4. Database Migration Service (DMS)

In the same region where Azure SQL MI is deployed in the lab subscription, deploy Azure Data Migration Services (DMS).

![DMS1](./images/DMS_1.png)
![DMS2](./images/DMS_2.png)
![DMS3](./images/DMS_3.png)
![DMS4](./images/DMS_4.png)



## Success criteria

- Resource provider is registered for data migrations
- SQL MI configured for System Assigned Managed Identity
- Storage account is created with a Blob container
- DMS is deployed 


## Challenge 4 — Online Migraton to SQL Managed Instance

In this challenge you will perform database backups to the Azure Storage account provisioned earlier.  You will then use DMS to perform an *Online* migration. To perform and online migration, DMS restores backups then takes advantage of the *Log Replay Service* (LRS) to replay transaction logs and complete the migration. 

## Student tasks

### 1. Backup the database to Azure Storage using SSMS 22

Launch SSMS from the desktop:

 ![SSMS22](./images/ssms_22.png)

Connect to the source database that resides in the VM. Expand the tree and Database folder and locate the *eShop* database. Right click and select Tasks->Backup.

![SSMS22_1](./images/SSMS22_1.png)

Select *Full* for backup type and *URL* for *Back up to*. Click on *Add* to select the Azure Storage account and Blob container.

![SSMS22_2](./images/SSMS22_2.png)

Click on *New Container*

![SSMS22_3](./images/SSMS22_3.png)

Login to the lab's subscription and select the storage account and container created earlier. Generate SAS credentials and save them in notepad. Click OK.

![SSMS22_4](./images/SSMS22_4.png)

Make sure to prefix the *Backup File* with the directory name *backups/* of the Blob container that was created earlier. Otherwise the backup file will be created in the root of the container. Click OK.

![SSMS22_5](./images/SSMS22_5.png)

Repeat the task this time taking a differential backup.

![SSMS22_6](./images/SSMS22_6.png)

The backups should be listed in the Blob container in the storage account.

![SSMS22_7](./images/SSMS22_7.png)

### 2. Migrate the database online using DMS

Navigate to the Azure portal to the DMS service created earlier.  Select Migrate database.

![DMS_5](./images/DMS_5.png)

Select *New Migration*

![DMS_6](./images/DMS_6.png)

Select *Blob Storage* as the location of the backup files and *Online* as the migration mode.

![DMS_7](./images/DMS_7.png)

Configure details as shown. For the Instance details, the details referenced are not those of the source server, rather the *Migration Project* we are configuring. 

![DMS_8](./images/DMS_8.png)

Select the Azure SQL managed Instance that already exists as a target.

![DMS_9](./images/DMS_9.png)

Specify the location of the backup files in the Azure storage account as well as the target database name you eShop.

![DMS_10](./images/DMS_10.png)

Start the migration.

![DMS_11](./images/DMS_11.png)

Follow the migration progress.

![DMS_12](./images/DMS_12.png)

If all is well, both the full and differential backups have been restored.

![DMS_13](./images/DMS_13.png)

The work is not done yet.  Since this is an online migration, transaction logs need to be replayed.  The LRS can only be triggered via Azure CLI or PowerShell. The *datamigration* extension needs to be installed on the VM.

*az extension add --name datamigration --upgrade*

Once that is done, as a test to prove that transactions logs completed successfully and no data loss occured, go to the source database and add a new row to a table. Use SSMS 22 to launch a query window and run the command.

![DMS_14](./images/DMS_14.png)

Next we need to backup the transaction logs to the storage account, in the same folder/location as the database backups.  Use SSMS to do this as well. Opt for *Transactions Logs* as the back up type.

![DMS_15](./images/DMS_15.png)

From command line login to azure:

*az login*

Start the log replay service in continuous mode  by issuing the following command making sure to replace the place holders with your lab's Azure environment information.  If you don't have the SAS for the Storage account from the earlier steps, generate a new one.

az sql midb log-replay start -g mygroup --mi myinstance -n mymanageddb --storage-uri "https://*my storage accountname*.blob.core.windows.net/*container name*/*database backup folder*" --storage-sas "*SAS token for the container*"

Command should look like this:

![DMS_16](./images/DMS_16.png)

You can follow the progress of the log replay from the portal, same place as where the progress of the migration was being followed.

![DMS_122](./images/DMS_12.png)

The transaction logs have all been played when there are no files leeft to restore.

![DMS_17](./images/DMS_17.png)

Perform the cutover. Wait for it to complete.

![DMS_18](./images/DMS_18.png)

Navigate to the Azure SQL Managed instance and confirm the database is there and in good state. Click on *DAtabases* in the left to list all databases on this managed instance.

![DMS_19](./images/DMS_19.png)

Go back to SSMS 22.  Connect to the Azure SQL Managed Instance and eShop database using Entra. Explore the tables and make sure they are all there.  Confirm the row you added above is also present. 

#### Congratulations - you have migrated to Azure SQL

## Challenge 5  — Enable private endpoint for SQL Managed Instance

## Student tasks

1. Create a private endpoint for the Azure SQL logical server. Go to Azure portal - -> Security --> Networking --> Private Access
2. Configure the private endpoint in the same region where you want to connect from.
3. One the azure portal, search for your private DNS zone just created for SQL Database. Under DNS Management ---> Virtual Network Links, 
add links to the Vnet where you want to connect to this SQL database from azure. 
4. Ensure net connectibity using private endpoint from your source something like 
```text
test-NetConnection <your-logical-server>.database.windows.net -Port 1434
```

privatelink.database.windows.net <b>"privatelink.database.windows.net"</b> 

1. Link the private DNS zone to the VNet.
2. Associate the private endpoint with a DNS zone group.
3. Confirm that the private endpoint connection is approved.

## Success criteria

* The Azure SQL server name resolves to a private IP from the VM.
* TCP 1433 is reachable from the VM.
* Public network access remains disabled.

## Challenge 6  — Application readiness - Entra-id authentication for app

## Student tasks

1. Identify the Lab 04 retail Container App and its system-assigned managed identity:

   ```powershell
   $containerApp = az containerapp list `
     --resource-group '<application-resource-group>' `
     --query '[0].{name:name, principalId:identity.principalId}' `
     --output json | ConvertFrom-Json
   ```

2. Connect to the Azure SQL `eShop` database as the configured Microsoft Entra administrator.
3. Create a container user for the Container App identity. Use a unique alias and its object ID so the database principal does not depend on Entra display-name uniqueness:

   ```sql
   CREATE USER [caldova_retail_app] FROM EXTERNAL PROVIDER
     WITH OBJECT_ID = '<container-app-principal-id>';

   ALTER ROLE db_datareader ADD MEMBER [caldova_retail_app];
   ALTER ROLE db_datawriter ADD MEMBER [caldova_retail_app];
   ```

4. Do not grant `db_owner` or `db_ddladmin`; the runtime application reads and writes data but does not own schema deployment.
5. Prepare a passwordless application connection string using the Azure SQL FQDN:

   ```text
   Server=tcp:<server>.database.windows.net,1433;Initial Catalog=eShop;Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
   ```

6. Confirm TLS encryption and managed-identity authentication.
7. Test representative application operations.
8. Identify features that require redesign after migration.
9. Document rollback criteria and a cutover plan.

## Success criteria

The Container App identity has only the required database roles, the connection string contains no password, and the student demonstrates that application readiness requires more than successful data copy.


Suggested class schedule

|  |  |  |
| --- | --- | --- |
| **Phase** | **Challenges** | **Suggested time** |
| Source preparation | 1–3 | 45–60 minutes |
| Target preparation | 4–7 | 60 minutes |
| DMS configuration | 8–9 | 45 minutes |
| Troubleshooting | 10–11 | 60 minutes |
| Data migration | 12 | 30–60 minutes |
| Validation and closeout | 13–15 | 60 minutes |


### Instructor debrief questions

1. Why must compatibility assessment occur before migration?
2. What roles do Private Link and private DNS play?
3. Why should clients use the Azure SQL FQDN instead of its private IP?
4. What is the role of SHIR in an offline DMS migration?
5. How did you isolate error 2060 from network connectivity?
6. Why is independently deploying schema a valid migration strategy?
7. What evidence is required before declaring the migration successful?
8. What would change for a production migration with minimal downtime?
9. Which steps should be automated for repeatable delivery?

**Lab principle:** A migration is complete only after compatibility, connectivity, schema, data, application behavior, security, and operational readiness have all been validated with evidence.

---

[← Previous: Deploy the Azure Foundation](../04-deploy-to-azure/README.md) | [Next: Deploy Code with GitHub Actions →](../06-deploy-code-with-github-actions/README.md)