# Azure RG + UAMI Bootstrap 🚀

Bash script using Azure CLI to bootstrap a resource group and user-assigned managed identity, then grant Owner at the resource group scope. Supports flags/env vars for project, stage, suffix, location, subscription, and tenant. Targets Azure public cloud.

## Features ✨
- ✅ Idempotent: safe to re-run
- 🧩 Naming: `rg-{project}-{stage}[-{suffix}]` and `id-{project}-{stage}[-{suffix}]`
- 🌍 Defaults: `location` defaults to `northeurope`
- 🔁 Context-aware: uses current `az` login; can override subscription and tenant
- ✅ Validates inputs and prints a summary

## Prerequisites 🔧
- 🪟 Azure CLI (az)
- 🔐 Logged in: `az login`
- 🎯 Optional: set default subscription: `az account set --subscription <id-or-name>`

## Usage ▶️
Make executable:

```bash
chmod +x create_rg_uami.sh
```

Run with flags:

```bash
./create_rg_uami.sh \
  --project myapp \
  --stage dev \
  --suffix eu \
  --location westeurope \
  --subscription <sub-id-or-name> \
  --tenant <tenant-id-or-domain>
```

Or with environment variables:

```bash
PROJECT=myapp \
STAGE=dev \
SUFFIX=eu \
LOCATION=westeurope \
SUBSCRIPTION=<sub-id-or-name> \
TENANT=<tenant-id-or-domain> \
./create_rg_uami.sh
```

## What it does 🧭
1. ☁️ Ensures Azure public cloud context (AzureCloud)
2. 🔑 Ensures you are logged in (`az account show`)
3. 🔀 Optionally sets subscription if provided
4. 📦 Creates/ensures resource group: `rg-{project}-{stage}[-{suffix}]`
5. 🆔 Creates/ensures user-assigned managed identity: `id-{project}-{stage}[-{suffix}]`
6. 🛡️ Grants Owner role to the identity at the RG scope (skips if already assigned)
7. 📣 Prints `principalId`, `clientId`, and identity resource ID

## Parameters ⚙️
- project (required): name part used in resource names
- stage (required): environment/stage (e.g., dev, prod)
- suffix (optional): extra discriminator
- location (optional, default `northeurope`)
- subscription (optional): subscription ID or name to use
- tenant (optional): tenant ID or domain. If different from current, re-login with `az login --tenant <id>`

## Example output 📄
```
Using Azure context:
  Tenant:       <tenant-id>
  Subscription: <name> (<id>)
  Location:     northeurope
Creating/ensuring resource group: rg-myapp-dev
Creating/ensuring user-assigned managed identity: id-myapp-dev
Ensuring 'Owner' role assignment for the identity at scope: /subscriptions/<id>/resourceGroups/rg-myapp-dev
Role assignment created.

Success!
Resource Group: rg-myapp-dev
Managed Identity: id-myapp-dev
  principalId: <guid>
  clientId:    <guid>
  resourceId:  /subscriptions/<id>/resourceGroups/rg-myapp-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-myapp-dev
Scope: /subscriptions/<id>/resourceGroups/rg-myapp-dev
Role: Owner (ensured)
```

## Notes 📝
- ✔️ Script validates inputs: lowercase letters, digits, hyphens
- 🧪 Uses non-interactive `az` calls; if login is required, it exits with guidance
- 🔐 Role assignment uses `--assignee-principal-type ServicePrincipal` for UAMI

## License 🪪
MIT License — see LICENSE.
