#!/usr/bin/env bash
set -euo pipefail

# create_rg_uami.sh
# Creates an Azure Resource Group and a User Assigned Managed Identity within it,
# then assigns Owner role to the identity at the RG scope.
#
# Naming:
# - Resource Group: rg-{project}-{stage}[-{suffix}]
# - Managed Identity: id-{project}-{stage}[-{suffix}]
#
# Inputs via flags or environment variables (flags take precedence):
# - --project | PROJECT (required)
# - --stage   | STAGE   (required)
# - --suffix  | SUFFIX  (optional)
# - --location| LOCATION (optional, default: northeurope)
# - --subscription | SUBSCRIPTION or AZURE_SUBSCRIPTION_ID (optional)
# - --tenant | TENANT or AZURE_TENANT_ID (optional)
#
# Context: Uses the currently set Azure tenant and subscription (or overrides if provided), in Azure public cloud.

usage() {
  cat <<'EOF'
Usage: create_rg_uami.sh [--project <name>] [--stage <name>] [--suffix <optional>] [--location <azure-region>] [--subscription <id-or-name>] [--tenant <tenant-id-or-name>] [--help]

Flags (override environment variables if both provided):
  --project, -p        Project name (required) or set PROJECT
  --stage, -s          Stage/environment (required) or set STAGE
  --suffix, -x         Optional suffix (or set SUFFIX)
  --location, -l       Azure region (default: northeurope) or set LOCATION
  --subscription, -S   Subscription id or name to use (or set SUBSCRIPTION / AZURE_SUBSCRIPTION_ID)
  --tenant, -T         Tenant id or domain to use (or set TENANT / AZURE_TENANT_ID). If different from current, you'll need to az login --tenant <id> first.
  --help, -h           Show this help

Environment variables:
  PROJECT, STAGE, SUFFIX (optional), LOCATION (default northeurope)
  SUBSCRIPTION or AZURE_SUBSCRIPTION_ID (optional), TENANT or AZURE_TENANT_ID (optional)

Examples:
  PROJECT=myapp STAGE=dev ./create_rg_uami.sh
  ./create_rg_uami.sh -p myapp -s prod -x eu -l westeurope
  ./create_rg_uami.sh -p myapp -s dev -S f0877200-2189-4721-99cb-5ae66a5023cb -T f1847c27-90be-4b38-a1b7-bd3a2029122f
EOF
}

# Defaults
PROJECT=${PROJECT:-}
STAGE=${STAGE:-}
SUFFIX=${SUFFIX:-}
LOCATION=${LOCATION:-northeurope}
SUBSCRIPTION=${SUBSCRIPTION:-${AZURE_SUBSCRIPTION_ID:-}}
TENANT=${TENANT:-${AZURE_TENANT_ID:-}}

# Parse flags (simple long/short parsing)
while [[ ${1:-} ]]; do
  case "$1" in
    --project|-p)
      PROJECT="$2"; shift 2;;
    --stage|-s)
      STAGE="$2"; shift 2;;
    --suffix|-x)
      SUFFIX="${2:-}"; shift 2;;
    --location|-l)
      LOCATION="$2"; shift 2;;
    --help|-h)
      usage; exit 0;;
    --subscription|-S)
      SUBSCRIPTION="$2"; shift 2;;
    --tenant|-T)
      TENANT="$2"; shift 2;;
    *)
      echo "Unknown argument: $1" 2>&1
      usage; exit 2;;
  esac
done

# Normalize to lowercase and strip leading/trailing hyphens/spaces
lower() { tr '[:upper:]' '[:lower:]'; }
trim_hyphens() { sed -E 's/^-+//; s/-+$//'; }

PROJECT=$(printf '%s' "${PROJECT}" | lower | trim_hyphens || true)
STAGE=$(printf '%s' "${STAGE}" | lower | trim_hyphens || true)
SUFFIX=$(printf '%s' "${SUFFIX}" | lower | trim_hyphens || true)
LOCATION=$(printf '%s' "${LOCATION}" | lower | trim_hyphens || true)

# Validate required
if [[ -z "${PROJECT}" ]]; then
  echo "Error: --project or PROJECT is required" >&2
  exit 1
fi
if [[ -z "${STAGE}" ]]; then
  echo "Error: --stage or STAGE is required" >&2
  exit 1
fi

# Basic name validation: letters, numbers, hyphens
re='^[a-z0-9-]+$'
for val_name in PROJECT STAGE LOCATION; do
  val=${!val_name}
  if [[ -z "$val" || ! "$val" =~ $re ]]; then
    echo "Error: $val_name must contain only lowercase letters, numbers, and hyphens (got: '$val')" >&2
    exit 1
  fi
done
if [[ -n "$SUFFIX" && ! "$SUFFIX" =~ $re ]]; then
  echo "Error: SUFFIX must contain only lowercase letters, numbers, and hyphens (got: '$SUFFIX')" >&2
  exit 1
fi

# Build names
suffix_part=""
if [[ -n "$SUFFIX" ]]; then
  suffix_part="-$SUFFIX"
fi
RG_NAME="rg-${PROJECT}-${STAGE}${suffix_part}"
ID_NAME="id-${PROJECT}-${STAGE}${suffix_part}"

# Ensure Azure CLI is installed
if ! command -v az >/dev/null 2>&1; then
  echo "Error: Azure CLI 'az' is not installed or not on PATH" >&2
  exit 1
fi

# Ensure Azure public cloud
az cloud set -n AzureCloud >/dev/null

# Ensure we have an active account context (non-interactive check)
if ! az account show >/dev/null 2>&1; then
  echo "You are not logged in to Azure CLI. Please run 'az login' (and 'az account set --subscription <id>' if needed) and re-run this script." 1>&2
  exit 1
fi

# If a subscription override was provided, set it now (supports id or name)
if [[ -n "${SUBSCRIPTION}" ]]; then
  echo "Setting subscription: ${SUBSCRIPTION}"
  az account set --subscription "${SUBSCRIPTION}"
fi

# Capture current subscription and tenant
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

# If a tenant override was provided, verify current tenant matches
if [[ -n "${TENANT}" ]]; then
  # Compare case-insensitively (IDs or domain names)
  shopt -s nocasematch || true
  if [[ "${TENANT_ID}" != "${TENANT}" && "${SUBSCRIPTION_NAME}" != "${TENANT}" ]]; then
    echo "Warning: Current tenant (${TENANT_ID}) does not match requested tenant (${TENANT})." 1>&2
    echo "If you need to switch tenants, run: az login --tenant ${TENANT} (and optionally --use-device-code), then re-run this script." 1>&2
  fi
  shopt -u nocasematch || true
fi

echo "Using Azure context:"
printf '  Tenant:       %s\n' "$TENANT_ID"
printf '  Subscription: %s (%s)\n' "$SUBSCRIPTION_NAME" "$SUBSCRIPTION_ID"
printf '  Location:     %s\n' "$LOCATION"

# Create or update Resource Group
echo "Creating/ensuring resource group: $RG_NAME"
az group create --name "$RG_NAME" --location "$LOCATION" --tags project="$PROJECT" stage="$STAGE" >/dev/null

# Create or ensure User Assigned Managed Identity
echo "Creating/ensuring user-assigned managed identity: $ID_NAME"
# Check existence
if az identity show -g "$RG_NAME" -n "$ID_NAME" >/dev/null 2>&1; then
  echo "Managed identity already exists."
else
  az identity create -g "$RG_NAME" -n "$ID_NAME" -l "$LOCATION" >/dev/null
  echo "Managed identity created."
fi

# Retrieve identity details (robustly via JMESPath queries)
PRINCIPAL_ID=$(az identity show -g "$RG_NAME" -n "$ID_NAME" --query principalId -o tsv)
CLIENT_ID=$(az identity show -g "$RG_NAME" -n "$ID_NAME" --query clientId -o tsv)
ID_RESOURCE_ID=$(az identity show -g "$RG_NAME" -n "$ID_NAME" --query id -o tsv)

if [[ -z "$PRINCIPAL_ID" ]]; then
  echo "Error: Failed to determine principalId of the managed identity" >&2
  exit 1
fi

# Assign Owner role at RG scope if not already present
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"

echo "Ensuring 'Owner' role assignment for the identity at scope: $SCOPE"
ASSIGNMENT_COUNT=$(az role assignment list \
  --assignee-object-id "$PRINCIPAL_ID" \
  --scope "$SCOPE" \
  --role "Owner" \
  --query 'length(@)' -o tsv)

if [[ "$ASSIGNMENT_COUNT" == "0" ]]; then
  az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Owner" \
    --scope "$SCOPE" >/dev/null
  echo "Role assignment created."
else
  echo "Role assignment already exists."
fi

# Output summary
cat <<EOF

Success!
Resource Group: ${RG_NAME}
Managed Identity: ${ID_NAME}
  principalId: ${PRINCIPAL_ID}
  clientId:    ${CLIENT_ID}
  resourceId:  ${ID_RESOURCE_ID}
Scope: ${SCOPE}
Role: Owner (ensured)
EOF

