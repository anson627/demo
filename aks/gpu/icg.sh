#!/usr/bin/env bash
#
# Usage:
#   az login                       # ensure you have an active az session
#   ./aks_canary_validation.sh     # runs all 4 phases sequentially
#
# Override any variable via env, e.g.:
#   INITIAL_CAPACITY=18 TARGET_CAPACITY=36 ./aks_canary_validation.sh
# =============================================================================

set -euo pipefail

# ---------- Configuration (override via env) ---------------------------------
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-e941f974-6d4e-442b-a866-e8bdcdf428b4}"
MY_RESOURCE_GROUP_NAME="${MY_RESOURCE_GROUP_NAME:-myAKSResourceGroup}"
REGION="${REGION:-eastus2euap}"
ZONE="${ZONE:-3}"
VM_SIZE="${VM_SIZE:-Standard_ND128isr_GB300_v6}"

VMSS_NAME="${VMSS_NAME:-myVmss}"
ICG_NAME="${ICG_NAME:-myInterconnectGroup}"
ICB_NAME="${ICB_NAME:-myInterconnectBlock}"
VNET_NAME="${VNET_NAME:-myVNet}"
SUBNET_NAME="${SUBNET_NAME:-mySubnet}"

INITIAL_CAPACITY="${INITIAL_CAPACITY:-18}"
TARGET_CAPACITY="${TARGET_CAPACITY:-18}"

ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/id_rsa.pub}"

COMPUTE_API_VERSION="${COMPUTE_API_VERSION:-2025-11-01}"
NETWORK_API_VERSION="${NETWORK_API_VERSION:-2025-09-01}"

POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-30}"
POLL_TIMEOUT_SECONDS="${POLL_TIMEOUT_SECONDS:-3600}"

# ---------- Derived URLs -----------------------------------------------------
BASE_MGMT="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${MY_RESOURCE_GROUP_NAME}"

VMSS_URL="${BASE_MGMT}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}?api-version=${COMPUTE_API_VERSION}"
VMSS_INSTANCES_URL="${BASE_MGMT}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}/virtualMachines?api-version=${COMPUTE_API_VERSION}"
ICG_URL="${BASE_MGMT}/providers/Microsoft.Network/interconnectGroups/${ICG_NAME}?api-version=${NETWORK_API_VERSION}"

ICG_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${MY_RESOURCE_GROUP_NAME}/providers/Microsoft.Network/interconnectGroups/${ICG_NAME}"
SUBNET_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${MY_RESOURCE_GROUP_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${SUBNET_NAME}"

ICB_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${MY_RESOURCE_GROUP_NAME}/providers/Microsoft.Compute/interconnectBlocks/${ICB_NAME}"
ICB_URL="${BASE_MGMT}/providers/Microsoft.Compute/interconnectBlocks/${ICB_NAME}?api-version=${COMPUTE_API_VERSION}"

# ---------- Helpers ----------------------------------------------------------
log()  { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }

require_az() {
  command -v az >/dev/null  || die "azure-cli (az) not found in PATH"
  command -v jq >/dev/null  || die "jq not found in PATH"
  az account show -o none 2>/dev/null || die "Not logged in. Run: az login"
  az account set --subscription "${SUBSCRIPTION_ID}"
  ok "Subscription set to ${SUBSCRIPTION_ID}"
}

ensure_resource_group() {
  log "Ensuring resource group '${MY_RESOURCE_GROUP_NAME}' exists in '${REGION}'"
  if az group show --name "${MY_RESOURCE_GROUP_NAME}" -o none 2>/dev/null; then
    ok "Resource group '${MY_RESOURCE_GROUP_NAME}' already exists"
  else
    warn "Resource group '${MY_RESOURCE_GROUP_NAME}' not found — creating it"
    az group create \
      --name "${MY_RESOURCE_GROUP_NAME}" \
      --location "${REGION}" \
      -o none
    ok "Resource group '${MY_RESOURCE_GROUP_NAME}' created in '${REGION}'"
  fi
}

ensure_vnet() {
  log "Ensuring VNet '${VNET_NAME}' and Subnet '${SUBNET_NAME}' exist"

  if az network vnet show \
       --resource-group "${MY_RESOURCE_GROUP_NAME}" \
       --name "${VNET_NAME}" \
       -o none 2>/dev/null; then
    ok "VNet '${VNET_NAME}' already exists"
  else
    warn "VNet '${VNET_NAME}' not found — creating it"
    az network vnet create \
      --resource-group "${MY_RESOURCE_GROUP_NAME}" \
      --name "${VNET_NAME}" \
      --location "${REGION}" \
      --address-prefix "10.0.0.0/16" \
      --subnet-name "${SUBNET_NAME}" \
      --subnet-prefix "10.0.0.0/24" \
      -o none
    ok "VNet '${VNET_NAME}' with Subnet '${SUBNET_NAME}' created"
    return 0
  fi

  if az network vnet subnet show \
       --resource-group "${MY_RESOURCE_GROUP_NAME}" \
       --vnet-name "${VNET_NAME}" \
       --name "${SUBNET_NAME}" \
       -o none 2>/dev/null; then
    ok "Subnet '${SUBNET_NAME}' already exists"
  else
    warn "Subnet '${SUBNET_NAME}' not found — creating it"
    az network vnet subnet create \
      --resource-group "${MY_RESOURCE_GROUP_NAME}" \
      --vnet-name "${VNET_NAME}" \
      --name "${SUBNET_NAME}" \
      --address-prefix "10.0.0.0/24" \
      -o none
    ok "Subnet '${SUBNET_NAME}' created"
  fi
}

# -----------------------------------------------------------------------------
# Ensure the Interconnect Group exists (required before creating an ICB)
# -----------------------------------------------------------------------------
ensure_icg() {
  log "Ensuring Interconnect Group '${ICG_NAME}' exists"

  local current
  if current=$(az rest --method GET --url "${ICG_URL}" 2>&1); then
    local state
    state=$(jq -r '.properties.provisioningState // empty' <<<"${current}")
    ok "Interconnect Group '${ICG_NAME}' already exists (provisioningState=${state})"
    if [[ "${state}" == "Succeeded" ]]; then
      return 0
    fi
    wait_for_icg
    return 0
  fi

  if ! grep -qiE "ResourceNotFound|NotFound" <<<"${current}"; then
    die "Failed to GET ICG: ${current}"
  fi

  warn "Interconnect Group '${ICG_NAME}' not found — creating it"

  local body
  body=$(cat <<EOF
{
  "location": "${REGION}",
  "properties": {
    "subgroupProfile": {
      "vmSize": "${VM_SIZE}",
      "scope": "VerticalConnect",
      "size": ${INITIAL_CAPACITY}
    }
  }
}
EOF
)

  az rest \
    --method PUT \
    --url "${ICG_URL}" \
    --headers "Content-Type=application/json" \
    --body "${body}"

  ok "ICG PUT submitted"
  wait_for_icg
}

wait_for_icg() {
  log "Waiting for ICG to reach provisioningState=Succeeded..."

  local start
  start=$(date +%s)
  while true; do
    local elapsed
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed > POLL_TIMEOUT_SECONDS )); then
      die "Timed out after ${elapsed}s waiting for ICG provisioningState=Succeeded"
    fi

    local icg_json icg_state
    icg_json=$(az rest --method GET --url "${ICG_URL}")
    icg_state=$(jq -r '.properties.provisioningState // empty' <<<"${icg_json}")

    printf '   [%3ds] icg.provisioningState=%s\n' "${elapsed}" "${icg_state}"

    if [[ "${icg_state}" == "Failed" ]]; then
      die "ICG operation failed; provisioningState=Failed"
    fi

    if [[ "${icg_state}" == "Succeeded" ]]; then
      ok "ICG provisioningState=Succeeded"
      return 0
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

# -----------------------------------------------------------------------------
# Step 1: Create VMSS (capacity 18, ICG + ICB specified, NO subgroup id)
# -----------------------------------------------------------------------------
create_vmss() {
  log "Step 1/4 — Creating VMSS '${VMSS_NAME}' at capacity ${INITIAL_CAPACITY} (no subgroup id)"

  [[ -r "${SSH_PUBLIC_KEY_PATH}" ]] \
    || die "SSH public key not found at ${SSH_PUBLIC_KEY_PATH} (override via SSH_PUBLIC_KEY_PATH)"
  local ssh_public_key
  ssh_public_key=$(<"${SSH_PUBLIC_KEY_PATH}")

  local body
  body=$(cat <<EOF
{
  "location": "${REGION}",
  "zones": ["${ZONE}"],
  "sku": {
    "name": "${VM_SIZE}",
    "tier": "Standard",
    "capacity": ${INITIAL_CAPACITY}
  },
  "properties": {
    "orchestrationMode": "Uniform",
    "singlePlacementGroup": false,
    "platformFaultDomainCount": 1,
    "upgradePolicy": { "mode": "Manual" },
    "virtualMachineProfile": {
      "interconnectBlockProfile": {
        "interconnectBlock": { "id": "${ICB_ID}" }
      },
      "osProfile": {
        "computerNamePrefix": "icb-vmss",
        "adminUsername": "${ADMIN_USERNAME}",
        "linuxConfiguration": {
          "disablePasswordAuthentication": true,
          "ssh": {
            "publicKeys": [
              {
                "path": "/home/${ADMIN_USERNAME}/.ssh/authorized_keys",
                "keyData": "${ssh_public_key}"
              }
            ]
          }
        }
      },
      "storageProfile": {
        "imageReference": {
          "publisher": "microsoft-dsvm",
          "offer": "ubuntu-hpc",
          "sku": "2404-gb",
          "version": "24.04.2025110401"
        },
        "osDisk": {
          "createOption": "FromImage",
          "caching": "ReadWrite",
          "managedDisk": { "storageAccountType": "Premium_LRS" }
        },
        "dataDisks": [
          {
            "lun": 0,
            "createOption": "Empty",
            "diskSizeGB": 256,
            "managedDisk": { "storageAccountType": "Premium_LRS" }
          }
        ]
      },
      "networkProfile": {
        "interconnectGroupProfile": {
          "interconnectGroup": { "id": "${ICG_ID}" }
        },
        "networkInterfaceConfigurations": [
          {
            "name": "myNic",
            "properties": {
              "primary": true,
              "ipConfigurations": [
                {
                  "name": "ipconfig1",
                  "properties": {
                    "subnet": { "id": "${SUBNET_ID}" }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}
EOF
)

  az rest \
    --method PUT \
    --url "${VMSS_URL}" \
    --headers "Content-Type=application/json" \
    --body "${body}"

  ok "VMSS PUT submitted"
  wait_for_vmss_capacity "${INITIAL_CAPACITY}"
}

# -----------------------------------------------------------------------------
# Step 0: Create the ICB at INITIAL_CAPACITY so Step 1's VMSS has capacity.
# -----------------------------------------------------------------------------
create_icb() {
  ensure_icg

  log "Step 0/4 — Creating ICB '${ICB_NAME}' at capacity ${INITIAL_CAPACITY}"
  log "          ICB id: ${ICB_ID}"

  local body
  body=$(cat <<EOF
{
  "location": "${REGION}",
  "zones": ["${ZONE}"],
  "sku": {
    "name": "${VM_SIZE}",
    "capacity": ${INITIAL_CAPACITY}
  },
  "properties": {
    "interconnectGroup": {
      "id": "${ICG_ID}"
    }
  }
}
EOF
)

  az rest \
    --method PUT \
    --url "${ICB_URL}" \
    --headers "Content-Type=application/json" \
    --body "${body}"

  ok "ICB PUT submitted"
  wait_for_icb_capacity "${INITIAL_CAPACITY}"
}

# -----------------------------------------------------------------------------
# Step 2: Ensure the existing ICB has the desired capacity for the scale-out.
#         PATCHes the ICB sku.capacity to TARGET_CAPACITY if it does not match.
# -----------------------------------------------------------------------------
update_icb_capacity() {
  log "Step 2/4 — Ensuring ICB '${ICB_NAME}' has capacity == ${TARGET_CAPACITY}"
  log "          ICB id: ${ICB_ID}"

  local current cap state
  if ! current=$(az rest --method GET --url "${ICB_URL}" 2>&1); then
    if grep -qiE "ResourceNotFound|NotFound" <<<"${current}"; then
      warn "ICB '${ICB_NAME}' not found — re-creating at capacity ${TARGET_CAPACITY}"
      TARGET_CAP_BACKUP="${INITIAL_CAPACITY}"
      INITIAL_CAPACITY="${TARGET_CAPACITY}"
      create_icb
      INITIAL_CAPACITY="${TARGET_CAP_BACKUP}"
      return 0
    else
      die "Failed to GET ICB: ${current}"
    fi
  fi

  cap=$(jq   -r '.sku.capacity // empty'                 <<<"${current}")
  state=$(jq -r '.properties.provisioningState // empty' <<<"${current}")

  [[ -n "${cap}" ]] || die "Could not read sku.capacity from ICB ${ICB_ID}"
  ok "Existing ICB capacity=${cap}, provisioningState=${state}"

  if (( cap == TARGET_CAPACITY )); then
    ok "ICB already at desired capacity=${TARGET_CAPACITY}; no PATCH required"
    return 0
  fi

  log "ICB capacity (${cap}) != TARGET_CAPACITY (${TARGET_CAPACITY}); PATCHing ICB"

  local body
  body=$(cat <<EOF
{
  "sku": {
    "capacity": ${TARGET_CAPACITY}
  }
}
EOF
)

  az rest \
    --method PATCH \
    --url "${ICB_URL}" \
    --headers "Content-Type=application/json" \
    --body "${body}"

  ok "ICB PATCH submitted"
  wait_for_icb_capacity "${TARGET_CAPACITY}"
}

wait_for_icb_capacity() {
  local expected="$1"
  log "Waiting for ICB to reach capacity=${expected} and provisioningState=Succeeded..."

  local start
  start=$(date +%s)
  while true; do
    local elapsed
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed > POLL_TIMEOUT_SECONDS )); then
      die "Timed out after ${elapsed}s waiting for ICB capacity=${expected}"
    fi

    local icb_json icb_cap icb_state
    icb_json=$(az rest --method GET --url "${ICB_URL}")
    icb_cap=$(jq   -r '.sku.capacity // empty'                 <<<"${icb_json}")
    icb_state=$(jq -r '.properties.provisioningState // empty' <<<"${icb_json}")

    printf '   [%3ds] icb.provisioningState=%s sku.capacity=%s\n' \
      "${elapsed}" "${icb_state}" "${icb_cap}"

    if [[ "${icb_state}" == "Failed" ]]; then
      die "ICB operation failed; provisioningState=Failed"
    fi

    if [[ "${icb_state}" == "Succeeded" && "${icb_cap}" == "${expected}" ]]; then
      ok "ICB at capacity=${expected}, provisioningState=Succeeded"
      return 0
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

# -----------------------------------------------------------------------------
# Step 3: Scale-out VMSS via PATCH (capacity 36, NO subgroup id)
# -----------------------------------------------------------------------------
patch_vmss_capacity() {
  log "Step 3/4 — PATCHing VMSS '${VMSS_NAME}' to capacity ${TARGET_CAPACITY} (no subgroup id)"

  local current
  if ! current=$(az rest --method GET --url "${VMSS_URL}" 2>&1); then
    if grep -qi "NotFound" <<<"${current}"; then
      warn "VMSS '${VMSS_NAME}' not found — creating it first at capacity ${TARGET_CAPACITY}"
      local orig_cap="${INITIAL_CAPACITY}"
      INITIAL_CAPACITY="${TARGET_CAPACITY}"
      create_vmss
      INITIAL_CAPACITY="${orig_cap}"
      return 0
    else
      die "Failed to GET VMSS: ${current}"
    fi
  fi

  local body
  body=$(cat <<EOF
{
  "sku": {
    "capacity": ${TARGET_CAPACITY}
  }
}
EOF
)

  az rest \
    --method PATCH \
    --url "${VMSS_URL}" \
    --headers "Content-Type=application/json" \
    --body "${body}"

  ok "VMSS PATCH submitted"
}

# -----------------------------------------------------------------------------
# Step 4: Validate scale-out
# -----------------------------------------------------------------------------
wait_for_vmss_capacity() {
  local expected="$1"
  log "Waiting for VMSS to reach capacity=${expected} and all instances to provision..."

  local start
  start=$(date +%s)
  while true; do
    local elapsed
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed > POLL_TIMEOUT_SECONDS )); then
      die "Timed out after ${elapsed}s waiting for capacity=${expected}"
    fi

    local vmss_json sku_capacity prov_state
    vmss_json=$(az rest --method GET --url "${VMSS_URL}")
    sku_capacity=$(jq -r '.sku.capacity' <<<"${vmss_json}")
    prov_state=$(jq -r '.properties.provisioningState' <<<"${vmss_json}")

    local instances_json total succeeded failed
    instances_json=$(az rest --method GET --url "${VMSS_INSTANCES_URL}")
    total=$(jq    '[.value[]] | length' <<<"${instances_json}")
    succeeded=$(jq '[.value[] | select(.properties.provisioningState=="Succeeded")] | length' <<<"${instances_json}")
    failed=$(jq    '[.value[] | select(.properties.provisioningState=="Failed")]    | length' <<<"${instances_json}")

    printf '   [%3ds] vmss.provisioningState=%s sku.capacity=%s  instances: total=%s succeeded=%s failed=%s\n' \
      "${elapsed}" "${prov_state}" "${sku_capacity}" "${total}" "${succeeded}" "${failed}"

    if (( failed > 0 )); then
      warn "${failed} instance(s) reported Failed provisioningState"
    fi

    if [[ "${prov_state}" == "Succeeded" \
       && "${sku_capacity}" == "${expected}" \
       && "${total}" == "${expected}" \
       && "${succeeded}" == "${expected}" ]]; then
      ok "VMSS at capacity=${expected}, all ${expected} instances Succeeded"
      return 0
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

validate_scale_out() {
  log "Step 4/4 — Validating scale-out ${INITIAL_CAPACITY} -> ${TARGET_CAPACITY}"
  wait_for_vmss_capacity "${TARGET_CAPACITY}"

  # Final ICB sanity check
  local icb_cap
  icb_cap=$(az rest --method GET --url "${ICB_URL}" | jq -r '.sku.capacity')
  ok "Final ICB capacity: ${icb_cap}"

  log "✅ Canary validation completed successfully."
}

main() {
  require_az
  ensure_resource_group
  ensure_vnet
  local stages="${STAGES:-2 3 4}"
  for stage in ${stages}; do
    case "${stage}" in
      0) create_icb ;;
      1) create_vmss ;;
      2) update_icb_capacity ;;
      3) patch_vmss_capacity ;;
      4) validate_scale_out ;;
      *) die "Unknown stage: ${stage}" ;;
    esac
  done
}

main "$@"
