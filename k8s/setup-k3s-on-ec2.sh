#!/bin/bash
# One-time setup on Jenkins EC2 (run as root / with sudo)
# Creates a single-node Kubernetes cluster (k3s) suitable for this Jenkins job.

set -euo pipefail

echo "Installing k3s (single-node cluster)..."
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

echo "Waiting for node Ready..."
sleep 10
kubectl get nodes

echo "Installing nginx ingress controller (optional; k3s already has Traefik)..."
# Uncomment if you prefer nginx ingress instead of Traefik:
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml

echo "Allow jenkins user to use kubectl..."
mkdir -p /var/lib/jenkins/.kube
cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
chown -R jenkins:jenkins /var/lib/jenkins/.kube
# Replace server address if needed for local access
sed -i 's#https://127.0.0.1:6443#https://127.0.0.1:6443#g' /var/lib/jenkins/.kube/config

echo "Done. Open AWS security group ports: 80, 443, 30080"
kubectl get svc -A
