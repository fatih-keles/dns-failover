#!/bin/bash

# Load environment variables for PRIMARY and SECONDARY IPs
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found."
    exit 1
fi

DOMAIN="failover.acedemos.net"
INTERVAL=2 # Frequency of DNS lookups in seconds

echo "Starting OCI DNS Failover Demo..."
echo "Target Domain: $DOMAIN"
echo "Primary IP:    $PRIMARY"
echo "Secondary IP:  $SECONDARY"
echo "----------------------------------------------------------------------"

# 1. Check current status
CURRENT_RESOLVE=$(dig +short "$DOMAIN" | tail -n1)

if [ "$CURRENT_RESOLVE" != "$PRIMARY" ]; then
    echo "Warning: Domain is not currently pointing to Primary ($PRIMARY)."
    echo "It is pointing to: $CURRENT_RESOLVE"
    echo "Ensure your Primary server is healthy and the Health Check is green."
fi

echo "Step 1: Monitoring $DOMAIN. Currently resolving to $CURRENT_RESOLVE."
echo "ACTION REQUIRED: Stop the HTTP service on your PRIMARY server ($PRIMARY) NOW."
echo "Waiting for failover to Secondary ($SECONDARY)..."
echo "----------------------------------------------------------------------"

START_TIME=$(date +%s)

# 2. Loop until the IP changes to the Secondary
while true; do
    CHECK_IP=$(dig +short "$DOMAIN" | tail -n1)
    ELAPSED=$(( $(date +%s) - START_TIME ))
    
    if [ "$CHECK_IP" == "$SECONDARY" ]; then
        echo -e "\n[SUCCESS] Failover Detected!"
        echo "New IP: $CHECK_IP"
        echo "Total Failover Time: $ELAPSED seconds"
        break
    elif [ "$CHECK_IP" == "$PRIMARY" ]; then
        echo -ne "Time Elapsed: ${ELAPSED}s | Still resolving to Primary... \r"
    else
        echo -ne "Time Elapsed: ${ELAPSED}s | Waiting for resolution... ($CHECK_IP) \r"
    fi
    
    sleep $INTERVAL
done

echo -e "\n----------------------------------------------------------------------"
echo "Step 2: Monitoring for Recovery."
echo "ACTION REQUIRED: Start the HTTP service back up on your PRIMARY server ($PRIMARY)."
echo "Waiting for failback to Primary..."

RECOVERY_START=$(date +%s)

while true; do
    CHECK_IP=$(dig +short "$DOMAIN" | tail -n1)
    ELAPSED=$(( $(date +%s) - RECOVERY_START ))
    
    if [ "$CHECK_IP" == "$PRIMARY" ]; then
        echo -e "\n[SUCCESS] Recovery Detected!"
        echo "Domain restored to: $CHECK_IP"
        echo "Total Recovery Time: $ELAPSED seconds"
        break
    else
        echo -ne "Time Elapsed: ${ELAPSED}s | Still resolving to Secondary... \r"
    fi
    
    sleep $INTERVAL
done

echo -e "\nDemo Complete."