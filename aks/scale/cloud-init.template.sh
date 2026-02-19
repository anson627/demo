#!/bin/bash
set -eo pipefail

curl -fsSL https://raw.githubusercontent.com/Azure/AKSFlexNode/main/scripts/install.sh | bash -s -- -y

cat > /etc/aks-flex-node/config.json <<'EOF'
{
  "azure": {
    "subscriptionId": "${SUBSCRIPTION}",
    "tenantId": "${TENANT_ID}",
    "cloud": "AzurePublicCloud",
    "bootstrapToken": {
      "token": "${BOOTSTRAP_TOKEN}"
    },
    "arc": {
      "enabled": false
    },
    "targetCluster": {
      "resourceId": "${AKS_RESOURCE_ID}",
      "location": "${LOCATION}"
    }
  },
  "kubernetes": {
    "version": "1.34.2"
  },
  "node": {
    "kubelet": {
      "serverURL": "${SERVER_URL}",
      "caCertData": "${CA_CERT_DATA}"
    }
  },
  "agent": {
    "logLevel": "info",
    "logDir": "/var/log/aks-flex-node"
  }
}
EOF

systemctl enable --now aks-flex-node-agent
