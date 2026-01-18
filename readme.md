# Git Related Setup
## create a new repository on the command line
```bash
echo "# dns-failover" >> readme.md
git init
git add readme.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/fatih-keles/dns-failover.git
git push -u origin main
```

## push an existing repository from the command line
```bash
git remote add origin https://github.com/fatih-keles/dns-failover.git
git branch -M main
git push -u origin main
```

## push changes 
```bash
git add readme.md
git commit -m "first commit"
git push -u origin main
```

# Configure Demo Instances
## SSH into the instance
```bash
source .env
ssh -i ~/.ssh/jump-server.key ubuntu@$PRIMARY
ssh -i ~/.ssh/jump-server.key ubuntu@$SECONDARY
```

## update
```bash
sudo apt-get update
```

## open port 80
```bash
sudo iptables -I INPUT 5 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -L INPUT --line-numbers -n
sudo netfilter-persistent save
```

## run-demo.sh
```bash
# Use instance metadata services
# get region name 
REGION=$(curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/region)

# get display name
DISPLAY_NAME=$(curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/displayName)

# Get Public IP
PUBLIC_IP=$(curl -s https://ifconfig.me)

# prepare www folders
mkdir -p ~/www/demo
cd ~/www/demo

# prepare index.html
cat > index.html <<EOF
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>DNS Failover Demo</title>
  </head>
  <body>
    <h1>DNS Failover Demo</h1>
    <pre>
Region:     $REGION
Instance:   $DISPLAY_NAME
Public IP:  $PUBLIC_IP
    </pre>
  </body>
</html>
EOF

# start serving http:80 
sudo python3 -m http.server 80
```

# OCI Setup 
## Assuming you have a Public DNS Zone `acedemos.net` already defined 

## create health check 
```bash 
source .env
MONITOR_ID=$(oci health-checks http-monitor create \
  --compartment-id $COMPARTMENT_ID \
  --display-name "DNS-Failover-Http-Health-Check" \
  --interval-in-seconds 30 \
  --protocol HTTP \
  --port 80 \
  --targets "[\"$PRIMARY\",\"$SECONDARY\"]" \
  --query 'data.id' \
  --raw-output
  )

echo "Health Check OCID: $MONITOR_ID"
```

## create failover steering policy
```bash
# create answers.json
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

# create rules.json
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

# create failover steering policy 
STEERING_POLICY_ID=$(
  oci dns steering-policy create \
    --compartment-id "$COMPARTMENT_ID" \
    --display-name "DNS-Failover-Policy" \
    --template FAILOVER \
    --ttl 30 \
    --health-check-monitor-id "$MONITOR_ID" \
    --answers file://answers.json \
    --rules file://rules.json \
    --query 'data.id' \
    --raw-output
)
echo "Steering Policy OCID: $STEERING_POLICY_ID"

# find public zone for acedemos.net
ZONE_ID=$(
  oci dns zone list --compartment-id "$COMPARTMENT_ID" \
    --query "data[?name=='acedemos.net'].id | [0]" \
    --raw-output
)
# ZONE_ID=$(
#   oci dns zone list --compartment-id "$COMPARTMENT_ID" \
#     --query "data[0].id" --raw-output
# )
echo "Zone OCID: $ZONE_ID"

# attach steering policy to the zone 
ATTACHMENT_ID=$( 
  oci dns steering-policy-attachment create \
    --zone-id "$ZONE_ID" \
    --domain-name "failover.acedemos.net" \
    --steering-policy-id "$STEERING_POLICY_ID" \
    --display-name "failover.acedemos.net attachment" \
    --query 'data.id' \
    --raw-output
)
echo "Steering Policy Attachment OCID: $ATTACHMENT_ID"

# verify 
oci dns steering-policy get --steering-policy-id "$STEERING_POLICY_ID" --query 'data.{name:"display-name",template:template,ttl:ttl}' --output table
oci dns steering-policy-attachment get --steering-policy-attachment-id "$ATTACHMENT_ID" --query 'data.{domain:"domain-name",displayName:"display-name"}' --output table

``` 

# Test from a third host   
```bash
nslookup failover.acedemos.net
dig failover.acedemos.net +short
curl -ikv http://failover.acedemos.net
```

# OCI Cleanup 
## List all domain attachments 
```bash 
oci dns steering-policy-attachment list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,domain:"domain-name"}' \
  --output table
```

## Delete all domain attachments 
Unfortunately I couldn't find any screens to delete domain attachments. So here is the script.
```bash
IDs=$(oci dns steering-policy-attachment list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[*].id | join(`\n`, @)' \
  --raw-output)

for ATTACHMENT_ID in $IDs; do

  echo "Deleting attachment: $ATTACHMENT_ID"
  oci dns steering-policy-attachment delete \
    --steering-policy-attachment-id "$ATTACHMENT_ID" \
    --force
done
```

## List all dns steering policies
```bash 
oci dns steering-policy list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,displayName:"display-name",template:"template"}' \
  --output table
```

## Delete all dns steering policies
```bash
IDs=$(oci dns steering-policy list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[*].id | join(`\n`, @)' \
  --raw-output)

for POLICY_ID in $IDs; do

  echo "Deleting policy: $POLICY_ID"
  oci dns steering-policy delete \
    --steering-policy-id "$POLICY_ID" \
    --force
done
```

## List all dns health check
```bash 
oci health-checks http-monitor list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[].{id:id,displayName:"display-name",protocol:"protocol"}' \
  --output table
```

## Delete all dns health check
```bash
IDs=$(oci health-checks http-monitor list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --query 'data[*].id | join(`\n`, @)' \
  --raw-output)

for MONITOR_ID in $IDs; do

  echo "Deleting policy: $MONITOR_ID"
  oci health-checks http-monitor delete \
    --monitor-id "$MONITOR_ID" \
    --force
done
```