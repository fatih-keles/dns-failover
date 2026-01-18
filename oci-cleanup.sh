#!/bin/bash

# 0. Load Environment Variables
if [ -f .env ]; then
    source .env
    echo "Environment variables loaded from .env"
else
    echo "Error: .env file not found."
    exit 1
fi

# Check if COMPARTMENT_ID is set
if [ -z "$COMPARTMENT_ID" ]; then
    echo "Error: COMPARTMENT_ID environment variable is not set."
    exit 1
fi

echo "Starting OCI DNS Infrastructure Cleanup for compartment: $COMPARTMENT_ID"
echo "----------------------------------------------------------------------"

# 1. DELETE STEERING POLICY ATTACHMENTS
# Note: These must be deleted before the policies themselves.
echo "Checking for Steering Policy Attachments..."
oci dns steering-policy-attachment list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,domain:"domain-name"}' \
  --output table

ATTACHMENT_IDs=$(oci dns steering-policy-attachment list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[*].id | join(`\n`, @)' \
  --raw-output)

if [ -n "$ATTACHMENT_IDs" ]; then
    for ATTACHMENT_ID in $ATTACHMENT_IDs; do
        echo "Deleting attachment: $ATTACHMENT_ID"
        oci dns steering-policy-attachment delete \
          --steering-policy-attachment-id "$ATTACHMENT_ID" \
          --force
    done
else
    echo "No attachments found."
fi

# 2. DELETE STEERING POLICIES
echo -e "\nChecking for Steering Policies..."
oci dns steering-policy list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,displayName:"display-name",template:"template"}' \
  --output table

POLICY_IDs=$(oci dns steering-policy list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[*].id | join(`\n`, @)' \
  --raw-output)

if [ -n "$POLICY_IDs" ]; then
    for POLICY_ID in $POLICY_IDs; do
        echo "Deleting policy: $POLICY_ID"
        oci dns steering-policy delete \
          --steering-policy-id "$POLICY_ID" \
          --force
    done
else
    echo "No policies found."
fi

# 3. DELETE HEALTH CHECK HTTP MONITORS
echo -e "\nChecking for Health Check HTTP Monitors..."
oci health-checks http-monitor list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,displayName:"display-name",protocol:"protocol"}' \
  --output table

MONITOR_IDs=$(oci health-checks http-monitor list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[*].id | join(`\n`, @)' \
  --raw-output)

if [ -n "$MONITOR_IDs" ]; then
    for MONITOR_ID in $MONITOR_IDs; do
        echo "Deleting monitor: $MONITOR_ID"
        oci health-checks http-monitor delete \
          --monitor-id "$MONITOR_ID" \
          --force
    done
else
    echo "No health check monitors found."
fi

echo -e "\n----------------------------------------------------------------------"
echo "Cleanup process complete."