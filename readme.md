# create a new repository on the command line
```bash
echo "# dns-failover" >> readme.md
git init
git add readme.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/fatih-keles/dns-failover.git
git push -u origin main
```

# push an existing repository from the command line
```bash
git remote add origin https://github.com/fatih-keles/dns-failover.git
git branch -M main
git push -u origin main
```

# SSH into the instance
```bash
source .env
ssh -i ~/.ssh/jump-server.key ubuntu@$PRIMARY
ssh -i ~/.ssh/jump-server.key ubuntu@$SECONDARY
```

# update
```bash
sudo apt-get update
```

# open port 80
```bash
sudo iptables -I INPUT 5 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -L INPUT --line-numbers -n
sudo netfilter-persistent save
```

# run-demo.sh
```bash
# get region name
REGION=$(curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/region)

# get display name
DISPLAY_NAME=$(curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/displayName)

# Get Public IP
PUBLIC_IP=$(curl -s https://ifconfig.me)

# prepare demo folders
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

# serve
sudo python3 -m http.server 80
```

# test dns 
```bash
nslookup failover.acedemos.net
```