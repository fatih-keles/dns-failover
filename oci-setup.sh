#!/bin/bash

# 1. Load Environment Variables
if [ -f .env ]; then
    source .env
    echo "Environment variables loaded from .env"
else
    echo "Error: .env file not found."
    exit 1
fi

# 2. Validate Required Variables
REQS=(COMPARTMENT_ID PRIMARY SECONDARY)
for var in "${REQS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not defined in .env"
        exit 1
    fi
done

echo "Starting OCI DNS Setup..."
echo "----------------------------------------------------------------------"

# 3. Create Health Check HTTP Monitor
echo "Creating Health Check..."
MONITOR_ID=$(oci health-checks http-monitor create \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "DNS-Failover-Http-Health-Check" \
  --interval-in-seconds 30 \
  --protocol HTTP \
  --port 80 \
  --targets "[\"$PRIMARY\",\"$SECONDARY\"]" \
  --query 'data.id' \
  --raw-output)

echo "Health Check OCID: $MONITOR_ID"

# 4. Prepare JSON Config Files
echo "Generating policy configuration files..."

cat > answers.json <<EOF
[
  {
    "name": "server-primary",
    "rtype": "A",
    "rdata": "${PRIMARY}",
    "pool": "primary"
  },
  {
    "name": "server-secondary",
    "rtype": "A",
    "rdata": "${SECONDARY}",
    "pool": "secondary"
  }
]
EOF

cat > rules.json <<'EOF'
[
  {
    "ruleType": "FILTER",
    "defaultAnswerData": [
      {
        "answerCondition": "answer.isDisabled != true",
        "shouldKeep": true
      }
    ]
  },
  { "ruleType": "HEALTH" },
  {
    "ruleType": "PRIORITY",
    "defaultAnswerData": [
      { "answerCondition": "answer.pool == 'primary'",   "value": 1  },
      { "answerCondition": "answer.pool == 'secondary'", "value": 99 }
    ]
  },
  { "ruleType": "LIMIT", "defaultCount": 1 }
]
EOF

# 5. Create Steering Policy
echo "Creating Steering Policy (FAILOVER)..."
STEERING_POLICY_ID=$(oci dns steering-policy create \
    --compartment-id "$COMPARTMENT_ID" \
    --display-name "DNS-Failover-Policy" \
    --template FAILOVER \
    --ttl 30 \
    --health-check-monitor-id "$MONITOR_ID" \
    --answers file://answers.json \
    --rules file://rules.json \
    --query 'data.id' \
    --raw-output)

echo "Steering Policy OCID: $STEERING_POLICY_ID"

# 6. Locate DNS Zone
echo "Locating Zone ID for acedemos.net..."
ZONE_ID=$(oci dns zone list --compartment-id "$COMPARTMENT_ID" \
    --query "data[?name=='acedemos.net'].id | [0]" \
    --raw-output)

if [ "$ZONE_ID" == "null" ] || [ -z "$ZONE_ID" ]; then
    echo "Error: Could not find Zone ID for acedemos.net"
    exit 1
fi
echo "Zone OCID: $ZONE_ID"

# 7. Create Steering Policy Attachment
echo "Attaching Policy to domain: failover.acedemos.net..."
ATTACHMENT_ID=$(oci dns steering-policy-attachment create \
    --zone-id "$ZONE_ID" \
    --domain-name "failover.acedemos.net" \
    --steering-policy-id "$STEERING_POLICY_ID" \
    --display-name "failover.acedemos.net attachment" \
    --query 'data.id' \
    --raw-output)

echo "Attachment OCID: $ATTACHMENT_ID"

# 8. Cleanup Temp Files
rm answers.json rules.json

# 9. Final Verification
echo -e "\n--- VERIFICATION ---"

echo -e "\nSteering Policy:"
oci dns steering-policy get --steering-policy-id "$STEERING_POLICY_ID" \
    --query 'data.{name:"display-name",template:template,ttl:ttl}' --output table

echo -e "\nSteering Policy Attachment:"
oci dns steering-policy-attachment get --steering-policy-attachment-id "$ATTACHMENT_ID" \
    --query 'data.{domain:"domain-name",displayName:"display-name"}' --output table

echo -e "\nHealth Check:"
oci health-checks http-monitor list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,displayName:"display-name",protocol:"protocol"}' \
  --output table

echo -e "\nSetup Complete. Your failover is now active."