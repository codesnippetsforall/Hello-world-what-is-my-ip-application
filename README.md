# Hello World — What Is My Host / IP Application

A simple nginx-based web app that displays the **hostname of the machine serving the page** (from the browser URL via JavaScript). The project includes Docker packaging, Docker Hub publishing, Jenkins CI/CD on AWS EC2, GitHub webhook auto-triggers, and an optional Kubernetes (k3s) deployment with **2 replicas**, LoadBalancer/NodePort, and Ingress.

**GitHub repository:** [codesnippetsforall/Hello-world-what-is-my-ip-application](https://github.com/codesnippetsforall/Hello-world-what-is-my-ip-application)

---

## Table of contents

1. [Overview](#overview)
2. [Project structure](#project-structure)
3. [How the web app works](#how-the-web-app-works)
4. [Prerequisites](#prerequisites)
5. [Run locally with Docker](#run-locally-with-docker)
6. [Push image to Docker Hub](#push-image-to-docker-hub)
7. [Jenkins Docker pipeline](#jenkins-docker-pipeline)
8. [GitHub webhook auto-trigger](#github-webhook-auto-trigger)
9. [Kubernetes deployment (k3s on EC2)](#kubernetes-deployment-k3s-on-ec2)
10. [AWS security group ports](#aws-security-group-ports)
11. [Troubleshooting](#troubleshooting)
12. [Notes and limitations](#notes-and-limitations)

---

## Overview

| Layer | Purpose |
|--------|---------|
| `index.html` | UI that shows host hostname using `window.location` |
| `Dockerfile` | Serves the page with `nginx:alpine` |
| `JenkinsFile` | Checkout → build image → run container on EC2 |
| `JenkinsFile-k8s` | Pull Hub image → deploy to k3s (2 pods) + Service/Ingress |
| `k8s/` | Kubernetes manifests and one-time k3s setup script |

**Example environment used in this project**

| Item | Example value |
|------|----------------|
| Jenkins / app EC2 public IP | `15.207.223.192` |
| Jenkins URL | `http://15.207.223.192:8080/` |
| Docker Hub image (K8s flow) | `dockermano1984/myhostip:v1` |
| Local / Jenkins image name | `whatismyip:v1` |
| K8s NodePort | `30080` |

Update IPs, ports, and image names in the Jenkinsfiles and manifests to match your environment.

---

## Project structure

```text
.
├── index.html                 # Front-end UI (hostname display)
├── Dockerfile                 # nginx:alpine + copy index.html
├── JenkinsFile                # Docker build & run pipeline
├── JenkinsFile-k8s            # Kubernetes deploy pipeline
├── README.md                  # This file
└── k8s/
    ├── deployment.yaml        # Deployment, 2 replicas
    ├── service.yaml           # LoadBalancer (NodePort 30080) + ClusterIP
    ├── ingress.yaml           # Ingress (Traefik class for k3s)
    └── setup-k3s-on-ec2.sh    # One-time k3s install on Jenkins EC2
```

---

## How the web app works

The page is a static HTML/CSS/JS app served by nginx.

- **Primary value:** `window.location.hostname` (e.g. `15.207.223.192` when opened via that IP)
- **Full host:** `window.location.host` (includes port, e.g. `15.207.223.192:888`)
- **Protocol:** `window.location.protocol`

### Important behaviour

| What you might expect | What actually happens |
|------------------------|------------------------|
| Visitor’s public IP (home ISP) | **Not shown** — earlier demos used `ipapi.co` / `ipify`; current app does not |
| Linux hostname (`ip-172-31-...`) | **Not available** from browser JavaScript alone |
| Host from the URL you open | **Yes** — this is what the current app displays |

Browser JavaScript cannot read the EC2 OS hostname for security reasons. To show the true OS hostname you would need a server-side injection (entrypoint / API). This project intentionally uses **client-side JavaScript only**.

---

## Prerequisites

### Local machine

- Docker Desktop (or Docker Engine)
- Git

### Jenkins EC2

- Ubuntu/Debian (or similar)
- Docker installed and usable by the `jenkins` user
- Jenkins with Pipeline job support
- GitHub Plugin (for webhook trigger)
- Outbound access to GitHub and Docker Hub
- For K8s path: `k3s` + `kubectl` (see setup script)

### Docker Hub

- Account and public repository (example: `dockermano1984/myhostip`)
- Access token for `docker login` (recommended over account password)

---

## Run locally with Docker

```bash
# From the project root
docker build -t whatismyip:v1 .

docker run -d --name whatismyip-app -p 8080:80 whatismyip:v1
```

Open: [http://localhost:8080/](http://localhost:8080/)

You should see hostname `localhost` (or `127.0.0.1` depending on how you open the URL).

Stop and remove:

```bash
docker rm -f whatismyip-app
```

---

## Push image to Docker Hub

Tag the local image with your Docker Hub namespace, then push:

```bash
docker login
# Username: your Docker Hub user
# Password: Access Token

docker tag whatismyip:v1 dockermano1984/myhostip:v1
docker push dockermano1984/myhostip:v1
```

Optional `latest` tag:

```bash
docker tag whatismyip:v1 dockermano1984/myhostip:latest
docker push dockermano1984/myhostip:latest
```

**Note:** `docker tag` does not copy layers; it adds another name to the same image ID. Deleting by image ID may fail with *“image is referenced in multiple repositories”* until you remove or force-delete the extra tags.

Pull on any machine:

```bash
docker pull dockermano1984/myhostip:v1
```

---

## Jenkins Docker pipeline

File: [`JenkinsFile`](JenkinsFile)

### Stages

1. **Checkout** — clone GitHub `main`
2. **Build** — `docker build -t whatismyip:v1 .`
3. **Test** — list images matching `whatismyip`
4. **Code-Check** — assert `Dockerfile` and `index.html` exist
5. **Deploy** — remove old container, run new one with host port mapping

### Environment variables (edit as needed)

| Variable | Meaning | Example |
|----------|---------|---------|
| `IMAGE_NAME` | Local image tag | `whatismyip:v1` |
| `CONTAINER_NAME` | Container name | `whatismyip-app` |
| `HOST_PORT` | Host port mapped to container `80` | `888` |

### Create the Jenkins job

1. New Item → **Pipeline** (e.g. `docker-job-05-sept`)
2. Under **Pipeline**, paste contents of `JenkinsFile`, **or** use Pipeline from SCM pointing at this repo and set Script Path to `JenkinsFile`
3. Under **Triggers**, enable **GitHub hook trigger for GITScm polling**
4. Save → **Build Now**

### Jenkins + Docker permission

If the build fails with `docker: not found` or permission denied:

```bash
# On the EC2 Jenkins host
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Verify
sudo -u jenkins -H docker ps
```

---

## GitHub webhook auto-trigger

### Jenkins

- Job trigger: **GitHub hook trigger for GITScm polling** ✅

### GitHub repository webhook

| Setting | Required value |
|---------|----------------|
| Payload URL | `http://<JENKINS_PUBLIC_IP>:8080/github-webhook/` |
| Content type | `application/json` |
| Events | Just the **push** event |
| Active | Checked |

**Critical:** Payload URL must end with `/github-webhook/` — not only `/`.

Example:

```text
http://15.207.223.192:8080/github-webhook/
```

### Verify

1. Push a commit to `main`
2. GitHub → Webhooks → **Recent Deliveries** → expect **HTTP 200**
3. Jenkins job should start automatically

Ensure AWS security group allows inbound **TCP 8080** so GitHub can reach Jenkins.

---

## Kubernetes deployment (k3s on EC2)

Goal: **1 cluster (single EC2 node)**, **1 Deployment with 2 replicas (2 pods)**, same Docker Hub image, exposed via **LoadBalancer/NodePort** and **Ingress**.

### Why one Deployment with 2 replicas?

For the same image and one public endpoint, Kubernetes best practice is **one Deployment** with `replicas: 2`. That yields two pods behind one Service/Ingress. Two separate Deployments are only needed for different apps or versions (e.g. blue/green).

### One-time: install k3s on Jenkins EC2

```bash
# Copy setup script to the server, then:
sudo bash k8s/setup-k3s-on-ec2.sh
```

This script:

- Installs **k3s** (single-node Kubernetes)
- Copies kubeconfig for the **jenkins** user to `/var/lib/jenkins/.kube/config`
- Relies on k3s built-in **Traefik** Ingress controller

Confirm:

```bash
kubectl get nodes
sudo -u jenkins -H kubectl get nodes
```

### Manifests

| File | Resource |
|------|----------|
| `k8s/deployment.yaml` | Deployment `myhostip`, image `dockermano1984/myhostip:v1`, **2 replicas** |
| `k8s/service.yaml` | `LoadBalancer` (NodePort **30080**) + `ClusterIP` for Ingress |
| `k8s/ingress.yaml` | Ingress path `/` → ClusterIP service (`ingressClassName: traefik`) |

### Jenkins K8s pipeline

File: [`JenkinsFile-k8s`](JenkinsFile-k8s)

Stages:

1. **Checkout**
2. **Verify cluster** — `kubectl` must exist
3. **Pull image** — `docker pull dockermano1984/myhostip:v1`
4. **Deploy** — `kubectl apply` Deployment, Service, Ingress; wait for rollout
5. **Verify** — at least **2 Running** pods

Create a separate Pipeline job (e.g. `k8s-myhostip-deploy`) using `JenkinsFile-k8s`.

### Access URLs (after deploy)

| Path | URL example |
|------|-------------|
| NodePort / LoadBalancer | `http://15.207.223.192:30080/` |
| Ingress (Traefik on 80) | `http://15.207.223.192/` |

Useful commands:

```bash
kubectl get pods -l app=myhostip -o wide
kubectl get svc -l app=myhostip
kubectl get ingress myhostip-ingress
kubectl logs -l app=myhostip --tail=50
kubectl rollout restart deployment/myhostip
```

### Manual apply (without Jenkins)

```bash
docker pull dockermano1984/myhostip:v1
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl rollout status deployment/myhostip
```

---

## AWS security group ports

| Port | Use |
|------|-----|
| `22` | SSH |
| `8080` | Jenkins UI + GitHub webhook |
| Host app port (`888` / `666` / etc.) | Direct Docker `docker run -p` |
| `30080` | Kubernetes NodePort |
| `80` / `443` | Ingress / Traefik (optional) |

Open only what you need; restrict source CIDRs when possible.

---

## Troubleshooting

### `docker: not found` (exit 127) in Jenkins

Docker is missing from the Jenkins agent PATH, or not installed. Install Docker and add `jenkins` to the `docker` group, then restart Jenkins (see [Jenkins Docker pipeline](#jenkins-docker-pipeline)).

### Image delete: *referenced in multiple repositories*

Same image ID has multiple tags (e.g. `whatismyip:v1` and `dockermano1984/myhostip:v1`). Remove by tag:

```bash
docker rmi whatismyip:v1
# or
docker rmi -f <image-id>
```

### Webhook does not trigger Jenkins

1. Payload URL must be `.../github-webhook/`
2. Security group allows `8080` from internet
3. Job has **GitHub hook trigger** enabled
4. Check GitHub **Recent Deliveries** for status codes

### App shows home ISP IP instead of EC2

That happens only if the page still calls public IP lookup APIs (`ipapi.co`, `ipify`). Current `index.html` uses `window.location.hostname` and should show the **URL host** (e.g. EC2 public IP), not your ISP IP.

### K8s: `kubectl not found` in Jenkins

Run `k8s/setup-k3s-on-ec2.sh` and ensure `/var/lib/jenkins/.kube/config` is readable by `jenkins`.

### K8s pods not Ready / ImagePullBackOff

- Confirm Hub image exists: `dockermano1984/myhostip:v1`
- Check spelling/tag
- Ensure EC2 can pull from Docker Hub
- `kubectl describe pod <pod-name>`

### Ingress returns nothing on port 80

- Confirm Traefik is running: `kubectl get svc -n kube-system`
- Confirm `ingressClassName` matches your controller (`traefik` for k3s)
- Use NodePort `30080` as a reliable fallback

---

## Notes and limitations

1. **Static app** — no backend API; hostname comes from the browser location object.
2. **Single-node k3s** — fine for learning/demo; not a multi-AZ production HA cluster.
3. **LoadBalancer on EC2** — without AWS Load Balancer Controller, k3s ServiceLB/NodePort exposes the node IP/ports; open the security group accordingly.
4. **Secrets** — do not commit Docker Hub passwords, Jenkins credentials, or AWS keys to GitHub. Use Access Tokens and Jenkins Credentials Store.
5. **Port consistency** — keep `HOST_PORT` in `JenkinsFile` and the success message URL aligned with the port you open in the security group.

---

## Quick reference commands

```bash
# Build & run (Docker)
docker build -t whatismyip:v1 .
docker run -d -p 888:80 --name whatismyip-app whatismyip:v1

# Publish
docker tag whatismyip:v1 dockermano1984/myhostip:v1
docker push dockermano1984/myhostip:v1

# Kubernetes
sudo bash k8s/setup-k3s-on-ec2.sh
kubectl apply -f k8s/
kubectl get pods,svc,ingress -l app=myhostip
```

---

## License / purpose

Learning and demo project for Docker, Jenkins CI/CD, GitHub webhooks, and single-node Kubernetes on AWS EC2.
