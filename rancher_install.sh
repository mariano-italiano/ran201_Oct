#!/bin/bash

# Support https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-8-3/
# /usr/local/bin/rke2-uninstall.sh

echo "[TASK 1] Update repositories and install curl"
apt-get update >/dev/null 2>&1
apt-get install vim git curl -y >/dev/null 2>&1

echo "[TASK 2] Install and run RKE2"
#curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="v1.29" sh -
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="stable" sh - >/dev/null 2>&1
mkdir -p /etc/rancher/rke2 >/dev/null 2>&1
echo "write-kubeconfig-mode: \"0644\"" > /etc/rancher/rke2/config.yaml 
systemctl enable --now rke2-server.service >/dev/null 2>&1

echo "[TASK 3] Install kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" >/dev/null 2>&1
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl >/dev/null 2>&1

echo "[TASK 4] Install Bash completion"
apt-get install bash-completion >/dev/null 2>&1
echo 'source <(kubectl completion bash)' >>~/.bashrc 
source ~/.bashrc 

echo "[TASK 5] Crate kubeconfig"
mkdir -p ~/.kube >/dev/null 2>&1
ln -s /etc/rancher/rke2/rke2.yaml ~/.kube/config >/dev/null 2>&1

echo "[TASK 6] Install Helm"
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3  | bash  >/dev/null 2>&1

echo "[TASK 7] Deploy Cert-manager"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1
helm install cert-manager jetstack/cert-manager --namespace cert-manager --set installCRDs=true --create-namespace >/dev/null 2>&1

echo "[TASK 8] Deploy Rancher"
helm repo add rancher-prime https://charts.rancher.com/server-charts/prime >/dev/null 2>&1
# helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
# helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm search repo rancher-stable/rancher --versions
helm install rancher rancher-prime/rancher --namespace cattle-system --set hostname=rancher.192.168.1.170.nip.io --set replicas=1 --version 2.8.11 --create-namespace --set bootstrapPassword=password --wait --timeout=10m >/dev/null 2>&1
# helm upgrade rancher rancher-prime/rancher --namespace cattle-system --set hostname=rancher.192.168.1.170.nip.io --set replicas=1 --version 2.12.1 --create-namespace --set bootstrapPassword=password

echo "[TASK 8] Waiting for Rancher to start"
while true; do curl -kv https://rancher.192.168.1.170.nip.io 2>&1 | grep -q "dynamiclistener-ca"; if [ $? != 0 ]; then echo "Rancher isn't ready yet"; sleep 5; continue; fi; break; done; echo "Rancher is Ready";
