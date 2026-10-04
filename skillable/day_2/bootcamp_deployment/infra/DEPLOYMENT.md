# Deploy Lab 04 Bicep directly

The recommended deployment path is `azd up`, but the subscription-scoped
[`main.bicep`](./main.bicep) entry point can also be executed directly with
Azure CLI. Direct deployment bypasses AZD hooks and does not save Bicep outputs
in an AZD environment.

Run every command from the repository root.

## Prerequisites

- Azure CLI installed and authenticated with `az login`.
- .NET SDK 8 or later and first-run outbound HTTPS access to
  `https://api.nuget.org` for `-Action Deploy`. They are not required for
  `Validate` or `WhatIf`.
- Permission to create subscription deployments and resource groups.
- Contributor and role-assignment permissions in the four generated resource
  groups.
- Regional availability and quota for the selected resources.

## Use the deployment script

The script prompts securely for the VM administrator password, resolves the
selected Microsoft Entra user for SQL administration, validates the object ID,
and never writes the password to a parameter file. Supply only the user's
principal name; the object ID remains an internal Bicep parameter.

The password must be 12-72 characters, must not contain the VM administrator
username, and must contain lowercase, uppercase, numeric, and at least one of
`! @ $ % * _ - + =`. Restricting input to these characters avoids the
differences between Windows and Linux password rules and native CLI quoting.

The deployment derives a deterministic eight-character resource suffix from
the subscription resource ID, `EnvironmentName`, and `Prefix`. Deploying the
same environment name and prefix to another subscription produces a different
suffix for globally unique resources. Rerunning in the same subscription with
the same inputs reuses the original names.

`Prefix` must be 3-18 lowercase alphanumeric characters with optional single
internal hyphens, and it must begin and end with an alphanumeric character.

Set your subscription:

```powershell
$subscriptionId = '<subscription-id>'
az login
```

If Microsoft Graph reports `InteractionRequired` or
`TokenCreatedWithOutdatedPolicies`, the ARM token is still cached but the Graph
token no longer satisfies current Conditional Access policy. Reauthenticate
interactively for the subscription tenant:

```powershell
$tenantId = az account show --query tenantId --output tsv
az login --tenant $tenantId
az account set --subscription $subscriptionId
az ad signed-in-user show --output table
```

If browser authentication is unavailable, use
`az login --tenant $tenantId --use-device-code`. Do not use a service principal
for the default signed-in-user lookup. To select a different administrator,
set the optional `LAB04_SQL_ADMIN_LOGIN_OVERRIDE` AZD value, or pass
`-SqlEntraAdminLogin` to the direct deployment script, with that user's
principal name. Both paths query Microsoft Graph to obtain the object ID
required by Azure SQL.

When invoking `main.bicep` without the deployment script, the
`sqlEntraAdminLogin` and `sqlEntraAdminObjectId` parameters are optional. They
default to the user principal name and object ID returned by Bicep's
`deployer()` function:

```powershell
az deployment sub what-if `
  --name 'lab04-direct-preview' `
  --location 'centralus' `
  --template-file .\infra\main.bicep `
  --parameters `
    environmentName='lab04-direct' `
    primaryLocation='centralus' `
    secondaryLocation='eastus2' `
    applicationLocation='centralus' `
    vmAdminUsername='labadmin' `
    vmAdminPassword='<strong-password>'
```

Service principals and managed identities do not normally have a user
principal name. A workload identity invoking the template must therefore pass
both `sqlEntraAdminLogin` and `sqlEntraAdminObjectId` explicitly. When
overriding the default for any deployment identity, always provide the
matching pair; Bicep cannot resolve an arbitrary login to its Microsoft Entra
object ID.

Validate the template and parameters:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName 'lab04-direct' `
  -Action Validate
```

Preview the changes without deploying:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName 'lab04-direct' `
  -Action WhatIf
```

Deploy after reviewing the interactive what-if result:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName 'lab04-direct' `
  -Action Deploy
```

`Deploy` runs `az deployment sub create --confirm-with-what-if`, so Azure CLI
asks for confirmation before changing resources. After a successful deployment,
the script automatically:

1. reads the managed environment, Front Door origin, request message, and
   endpoint from the ARM deployment outputs
2. waits for exactly one Private Link request with the expected Front Door
   request message
3. refuses to approve anything if an unknown pending or duplicate matching
   request exists
4. approves only the exact expected request, or accepts it if already approved
5. verifies the connection state and waits for a successful HTTPS response from
   Front Door

The operator therefore needs permission to approve private endpoint connections
on the Container Apps managed environment. Validation and what-if actions never
approve a connection.

This automatic approval is a lab convenience because the same reviewed
deployment creates both ends and the request is bound to deterministic output.
Production landing zones should normally keep Private Link approval as a
separate protected action unless an equivalently constrained deployment
identity and policy-approved automation path are in place.

## Configure optional GitHub OIDC

The deployment script names the subscription deployment
`<EnvironmentName>-deploy` and prints a copyable OIDC setup command after a
successful deployment. Direct deployment outputs are stored on that ARM
deployment; they are not copied into an AZD environment.

`Deploy-Lab04.ps1` also accepts an optional `-DeploymentName` override. This
controls the ARM subscription deployment record only; `-EnvironmentName`
continues to control resource naming and tags. If supplied, use that exact
deployment name when running `Configure-Lab04GitHub.ps1`.

For the default `lab04-direct` environment, run this from the bootcamp
deployment directory:

```powershell
Set-Location (Join-Path (git rev-parse --show-toplevel) 'skillable\day_2\bootcamp_deployment')

.\assets\scripts\Configure-Lab04GitHub.ps1 `
  -SubscriptionId $subscriptionId `
  -DeploymentName 'lab04-direct-deploy' `
  -RequiredReviewer '<github-user-login>' `
  -DeploymentBranch 'main'
```

The authenticated GitHub account needs `ADMIN` permission on the repository;
`WRITE` permission is not sufficient for the environments API. Confirm the
automatically selected target before running setup:

```powershell
gh repo view `
  --json nameWithOwner,viewerPermission `
  --jq '{repository: .nameWithOwner, permission: .viewerPermission}'
```

If needed, have a repository administrator run the setup or add
`-Repository 'owner/name'` for a repository you administer.

If PowerShell reports that `DeploymentName` is not a recognized parameter,
inspect the resolved script before retrying:

```powershell
$oidcScript = Get-Command .\assets\scripts\Configure-Lab04GitHub.ps1
$oidcScript.Source
$oidcScript.ParameterSets |
  Select-Object Name, @{ Name = 'Parameters'; Expression = { $_.Parameters.Name -join ', ' } }
```

The `Arm` row must include `DeploymentName`. If it does not, the command is
loading a stale script; update the checkout or remove the stale copy. This
binding error occurs before Azure validates the deployment name.

Do not use `-AzdEnvironment` for infrastructure created by
`Deploy-Lab04.ps1`. To locate the generated ARM deployment and verify its
outputs:

```powershell
az deployment sub list `
  --query "[?properties.provisioningState=='Succeeded'].name" `
  --output table

az deployment sub show `
  --name 'lab04-direct-deploy' `
  --query properties.outputs.LAB04_BOOTSTRAP_RESOURCE_GROUP.value `
  --output tsv
```

If an older checkout fails at `az role definition create` with
`Failed to parse string as JSON`, Windows PowerShell stripped quotes from the
inline JSON argument before Azure CLI parsed it. Update
`assets/scripts/Configure-Lab04GitHub.ps1` and rerun the same OIDC setup
command. The corrected script uses a temporary JSON file and cleans it up;
there is no need to redeploy Lab 04.

## Select deployment and resource locations

The Azure CLI `--location` value stores the subscription deployment record and
does not control resource locations. The direct deployment script exposes this
value as `DeploymentLocation`. By default, it uses the selected
`PrimaryLocation`, preserving the existing behavior.

The Bicep `primaryLocation`, `secondaryLocation`, and `applicationLocation`
parameters independently control resource locations and each defaults to
`centralus`. The deployment script mirrors those defaults, so no location
arguments are required for a default deployment.

Pass one or more location arguments to override the defaults. For example:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName 'lab04-direct' `
  -DeploymentLocation 'eastus2' `
  -PrimaryLocation 'centralus' `
  -SecondaryLocation 'eastus2' `
  -ApplicationLocation 'centralus' `
  -Action WhatIf
```

For a raw Azure CLI deployment, set the deployment record with `--location`
and pass the three resource locations through `--parameters`, as shown in the
earlier `az deployment sub what-if` example. A raw
`az deployment sub create` provisions only the infrastructure because ARM
cannot package the repository-local `data\eshop.bacpac`. Use
`Deploy-Lab04.ps1 -Action Deploy` when the `eshop_ai` database must be
initialized.

Confirm SQL, VM, DMS, SQL MI, and zone-redundant Container Apps availability
before deploying to different regions. Locations cannot be changed in place for
existing regional resources. Use a new environment name or remove the old
deployment first.

## Select the database target

SQL Managed Instance is the default and requests the Freemium offer:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -Action Deploy
```

If Freemium is unavailable, instructor automation can select the paid General
Purpose model without an additional prompt:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName 'lab04-direct-sqlmi' `
  -SqlMiPricingModel Regular `
  -Action Deploy
```

To deploy Azure SQL Database instead, pass `-DatabaseMode azureSql`.

Both targets are provisioned without an empty child database. After a
successful deployment, the script imports `data\eshop.bacpac` as `eshop_ai`
with SqlPackage and the signed-in Entra administrator's Azure SQL token. The
script automatically discovers the caller's public IPv4 address through
`api.ipify.org`, temporarily permits only that `/32`, and removes the rule in
`finally`. Azure SQL public network access is restored to its original
disabled state.

The importer installs pinned Microsoft.SqlPackage `170.5.96` with
`dotnet tool` into the ignored project-local
`.azure\tools\sqlpackage\170.5.96` cache. It uses an explicit nuget.org source,
does not alter persistent NuGet configuration or global tools, verifies the
reported version, and reuses the cache on subsequent deployments. If
installation fails, verify `dotnet --list-sdks`, HTTPS access to
`api.nuget.org`, and proxy or certificate trust. An incomplete version cache
is rejected with its exact cleanup path rather than silently using it.

Do not switch database modes for an existing environment name. Conditional
Bicep resources omitted during an incremental deployment are not automatically
deleted.

## Use a different Entra administrator

By default, the script uses the signed-in Entra user. For a different Entra
user, pass only the user's principal name:

```powershell
.\infra\Deploy-Lab04.ps1 `
  -SubscriptionId $subscriptionId `
  -SqlEntraAdminLogin '<user-principal-name>' `
  -Action WhatIf
```

The script resolves the user principal name to the object ID required by Azure
SQL and passes both values to Bicep internally. If the user cannot be resolved,
the deployment stops rather than selecting a different administrator.

## Reruns and diagnostics

Deployments are deterministic for the subscription, environment name, and
prefix, so a failed deployment can normally be corrected and rerun with the
same values.

An existing `eshop_ai` database is always preserved. The deployment checks for
it before public-IP discovery or any SQL network change and skips the BACPAC
import when it exists. If import fails after creating the database, inspect
the database before rerunning because preserve-on-rerun behavior does not drop
or repair a partially imported database. Import failures report SqlPackage and
temporary-access cleanup errors explicitly.

After confirming that `eshop_ai` was created by a failed import and contains no
data that must be retained, retry only the import with the explicit recovery
switch. The switch deletes exactly that database, waits for deletion, and then
imports the BACPAC again:

```powershell
.\assets\scripts\Import-Lab04Database.ps1 `
  -DeploymentName 'lab04-direct-deploy' `
  -ReplaceExistingDatabase
```

A `ReferencedResourceNotProvisioned` error that reports an application VNet in
`Updating` state during `PutSubnetOperation` is a deployment-order race. The
network module sequences the reciprocal peerings after subnet completion; rerun
the same deployment after applying the current module.

A `ManagedEnvironmentInvalidSchema` error on API `2025-01-01` can result from
properties that are absent from that API's managed-environment schema. The
environment uses `vnetConfiguration.internal: true` for private ingress and
does not inject unsupported properties. The generated Container App name is
also bounded to the service's 32-character limit.

`ManagedEnvironmentCapacityHeavyUsageError` or `AKSCapacityHeavyUsage` means
the Container Apps control plane cannot currently allocate backing capacity in
the selected application region. It is not an ARM schema or quota error. Retry
later, or select another region that supports the Consumption workload profile.
Because the application VNet is regional, delete the failed managed environment
and application VNet before changing `ApplicationLocation` for the same
environment name. Confirm every resolved resource ID before deletion.

If Azure Database Migration Service fails while provisioning its managed
`IaaSAntimalware` VM extension, first rerun the same deployment. The backing VM
and extension are created by the DMS resource provider and are not controlled
by this Bicep template. If the same failure repeats, inspect the failed DMS
operation and inherited Azure Policy assignments, try another supported region,
or open an Azure support request.

The DMS resource explicitly declares the immutable classic-service kind as
`Cloud`. This is required for idempotent retries because Azure retains a failed
DMS resource and rejects later requests that omit or change its kind.

If the retained DMS resource remains in terminal `Failed` state and has no
`virtualNicId`, it cannot resume. Delete only that failed DMS resource, wait for
deletion to complete, and rerun the full deployment:

```powershell
$dmsId = az resource list `
  --resource-group 'rg-caldova-lab04-primary-<suffix>' `
  --resource-type 'Microsoft.DataMigration/services' `
  --query '[0].id' `
  --output tsv

az resource delete --ids $dmsId --api-version 2025-06-30
az resource wait --deleted --ids $dmsId --api-version 2025-06-30
```

Confirm the resolved resource ID before running the delete command. This
recreates only DMS; the successfully deployed Lab 04 resources remain intact.

Inspect failed subscription operations:

```powershell
az deployment operation sub list `
  --name 'lab04-direct-deploy' `
  --query "[?properties.provisioningState=='Failed']" `
  --output table
```

List resources created for the direct deployment:

```powershell
az resource list `
  --tag azd-env-name=lab04-direct `
  --output table
```

Direct deployment does not create AZD state. Cleanup must be performed by
reviewing and deleting the four generated Lab 04 resource groups. Do not delete
resource groups until dependent labs are complete.
