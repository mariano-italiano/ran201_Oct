## Deploy RKE2 High Available Cluster

### Install HA Proxy as Load Balancer for cluster

```sh
#!/bin/bash

# HAProxy Load Balancer Installation Script for RKE2 HA Cluster

set -e

# Configuration - EDIT THESE VALUES
SERVER1_IP="192.168.1.151"
SERVER2_IP="192.168.1.152"
SERVER3_IP="192.168.1.153"
STATS_PASSWORD="changeme123"

echo "=========================================="
echo "Installing HAProxy Load Balancer for RKE2"
echo "=========================================="

# Detect OS and install HAProxy
if [ -f /etc/debian_version ]; then
    echo "Detected Debian/Ubuntu system"
    apt-get update
    apt-get install -y haproxy
elif [ -f /etc/redhat-release ]; then
    echo "Detected RHEL/CentOS system"
    dnf install -y haproxy
else
    echo "Unsupported OS"
    exit 1
fi

# Backup original config
if [ -f /etc/haproxy/haproxy.cfg ]; then
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.$(date +%Y%m%d_%H%M%S)
fi

# Create HAProxy configuration
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# Kubernetes API Server
frontend rke2_api_frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend rke2_api_backend

backend rke2_api_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server server1 ${SERVER1_IP}:6443 check fall 3 rise 2
    server server2 ${SERVER2_IP}:6443 check fall 3 rise 2
    server server3 ${SERVER3_IP}:6443 check fall 3 rise 2

# RKE2 Supervisor/Registration
frontend rke2_supervisor_frontend
    bind *:9345
    mode tcp
    option tcplog
    default_backend rke2_supervisor_backend

backend rke2_supervisor_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server server1 ${SERVER1_IP}:9345 check fall 3 rise 2
    server server2 ${SERVER2_IP}:9345 check fall 3 rise 2
    server server3 ${SERVER3_IP}:9345 check fall 3 rise 2

# HTTPS Traffic (for Rancher and applications)
frontend https_frontend
    bind *:443
    mode tcp
    option tcplog
    default_backend https_backend

backend https_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server server1 ${SERVER1_IP}:443 check fall 3 rise 2
    server server2 ${SERVER2_IP}:443 check fall 3 rise 2
    server server3 ${SERVER3_IP}:443 check fall 3 rise 2

# HTTP Traffic
frontend http_frontend
    bind *:80
    mode tcp
    option tcplog
    default_backend http_backend

backend http_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server server1 ${SERVER1_IP}:80 check fall 3 rise 2
    server server2 ${SERVER2_IP}:80 check fall 3 rise 2
    server server3 ${SERVER3_IP}:80 check fall 3 rise 2

# Stats page
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats auth admin:${STATS_PASSWORD}
EOF

echo "HAProxy configuration created"

# Enable and start HAProxy
systemctl enable --now haproxy

# Check status
systemctl status haproxy --no-pager

echo ""
echo "=========================================="
echo "HAProxy installation complete!"
echo "=========================================="
echo "Stats page: http://$(hostname -I | awk '{print $1}'):8404/stats"
echo "Username: admin"
echo "Password: ${STATS_PASSWORD}"
echo ""
echo "Load balancer is ready on:"
echo "  - Kubernetes API: 6443"
echo "  - RKE2 Registration: 9345"
echo "  - HTTPS: 443"
echo "  - HTTP: 80"
echo "=========================================="
```


### Install First Control Plane

```sh
#!/bin/bash

# RKE2 First Server Node Installation Script

set -e

# Configuration - EDIT THESE VALUES
CLUSTER_TOKEN="my-super-secret-token-rke2"
LB_ADDRESS="192.168.1.150"    # Your HAProxy IP or DNS
LB_DNS="rancher.lab.local"    # Your HAProxy DNS name (optional)

echo "=========================================="
echo "Installing RKE2 First Server Node"
echo "=========================================="

# Disable firewall (optional, adjust based on your security requirements)
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# Install RKE2 server
echo "Downloading and installing RKE2..."
curl -sfL https://get.rke2.io | sh -

# Create config directory
mkdir -p /etc/rancher/rke2

# Create RKE2 config
cat > /etc/rancher/rke2/config.yaml << EOF
token: ${CLUSTER_TOKEN}
tls-san:
  - ${LB_ADDRESS}
  - ${LB_DNS}
  - $(hostname -I | awk '{print $1}')
cluster-cidr: 10.42.0.0/16
service-cidr: 10.43.0.0/16
write-kubeconfig-mode: "0644"
EOF

echo "RKE2 configuration created"

# Enable and start RKE2 server
systemctl enable -- now rke2-server.service

echo "Waiting for RKE2 to start (this may take a few minutes)..."
sleep 30

# Wait for the node to be ready
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if systemctl is-active --quiet rke2-server.service; then
        if [ -f /var/lib/rancher/rke2/server/node-token ]; then
            echo "RKE2 server is running!"
            break
        fi
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "Still waiting... ($elapsed seconds)"
done

# Add kubectl and other tools to PATH
cat >> ~/.bashrc << 'EOF'
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
alias k=kubectl
EOF

source ~/.bashrc

# Set kubeconfig
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=$PATH:/var/lib/rancher/rke2/bin

echo ""
echo "=========================================="
echo "First server node installation complete!"
echo "=========================================="
echo "Node token: $(cat /var/lib/rancher/rke2/server/node-token)"
echo ""
echo "Check node status with:"
echo "  kubectl get nodes"
echo ""
echo "View logs with:"
echo "  journalctl -u rke2-server -f"
echo ""
echo "Now install the other two server nodes"
echo "=========================================="

# Display nodes
sleep 10
/var/lib/rancher/rke2/bin/kubectl get nodes
```

### Install Additional Control Plane

```sh
#!/bin/bash

# RKE2 Additional Server Node Installation Script

set -e

# Configuration - EDIT THESE VALUES
FIRST_SERVER_IP="192.168.1.151"              # IP of your first server
CLUSTER_TOKEN="my-super-secret-token-rke2"   # Same token as first server
LB_ADDRESS="192.168.1.150"                   # Your HAProxy IP or DNS
LB_DNS="rancher.lab.local"                   # Your HAProxy DNS name (optional)

echo "=========================================="
echo "Installing RKE2 Additional Server Node"
echo "=========================================="

# Disable firewall (optional, adjust based on your security requirements)
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# Install RKE2 server
echo "Downloading and installing RKE2..."
curl -sfL https://get.rke2.io | sh -

# Create config directory
mkdir -p /etc/rancher/rke2

# Create RKE2 config
cat > /etc/rancher/rke2/config.yaml << EOF
server: https://${FIRST_SERVER_IP}:9345
token: ${CLUSTER_TOKEN}
tls-san:
  - ${LB_ADDRESS}
  - ${LB_DNS}
  - $(hostname -I | awk '{print $1}')
EOF

echo "RKE2 configuration created"

# Enable and start RKE2 server
systemctl enable --now rke2-server.service

echo "Waiting for RKE2 to start and join the cluster..."
sleep 30

# Wait for the node to be ready
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if systemctl is-active --quiet rke2-server.service; then
        echo "RKE2 server is running and joined the cluster!"
        break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "Still waiting... ($elapsed seconds)"
done

# Add kubectl and other tools to PATH
cat >> ~/.bashrc << 'EOF'
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
alias k=kubectl
EOF

source ~/.bashrc

# Set kubeconfig
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=$PATH:/var/lib/rancher/rke2/bin

echo ""
echo "=========================================="
echo "Server node joined the cluster!"
echo "=========================================="
echo "Check cluster status with:"
echo "  kubectl get nodes"
echo ""
echo "View logs with:"
echo "  journalctl -u rke2-server -f"
echo "=========================================="

# Display nodes
sleep 10
/var/lib/rancher/rke2/bin/kubectl get nodes
```
