# ============================================
# DevOps Trainee Runbook & Architecture Guide
# Simple Blog App on AWS EKS (GitOps + Monitoring)
# ============================================

## 1. Project Overview & Architecture
This project is an end-to-end containerized three-tier application deployed to Amazon EKS using GitOps (Argo CD), GitHub Actions CI/CD (replacing Jenkins), and full-stack observability with Prometheus, Grafana, and AWS CloudWatch.

### Architecture Topology
- **Frontend**: React 18 SPA built with Vite, served via Nginx on port 3000 (Kubernetes LoadBalancer Service on Port 80).
- **Backend API**: Node.js + Express REST API on port 5000 (ClusterIP Service on Port 5000), interacting with MySQL.
- **Database**: MySQL 8.0 StatefulSet backed by AWS EBS (`gp3` StorageClass via aws-ebs-csi-driver).
- **CI/CD Automation**: GitHub Actions workflow (`.github/workflows/DevSecOps.yml`) handling Gitleaks secret scan, npm security audit, Trivy vulnerability scan, multi-stage Docker build, push to Amazon ECR, and GitOps manifest updates.
- **GitOps Continuous Delivery**: Argo CD automatically reconciles changes from the Git repository into the `blog-app` Kubernetes namespace.
- **Observability**:
  - Prometheus scraping Node & Pod metrics, with alerting rules for CPU spikes and CrashLoopBackOff.
  - Grafana pre-provisioned with Prometheus data source and interactive dashboards.
  - AWS CloudWatch enabled for EKS Control Plane logs (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`).

---

## 2. Prerequisites
- **AWS CLI v2** configured with appropriate permissions (`aws sts get-caller-identity`).
- **Terraform >= 1.5**
- **kubectl >= 1.28**
- **Git**

---

## 3. Fast Deployment Guide (Trainee Step-by-Step)

### Step 1: Configure Terraform Variables
Edit `infra/terraform.tfvars`:
```hcl
aws_region     = "us-east-1"
environment    = "prod"
cluster_name   = "blog-prod-eks"
cluster_version = "1.31"
instance_types = ["t3.small"]
desired_size   = 2

github_org  = "pratikgayakwad07"
github_repo = "blog-app-eks-devsecops"
```

### Step 2: Provision AWS Infrastructure with Terraform
```bash
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```
*Creates: VPC with public/private subnets, NAT Gateway, ECR repositories (`prod/blog-app`, `prod/backend-blog-app`), GitHub Actions IAM OIDC Role, and EKS Cluster with EBS CSI Addon.*

### Step 3: Update Kubeconfig
```bash
aws eks update-kubeconfig --name blog-prod-eks --region us-east-1
kubectl get nodes
```

### Step 4: Deploy Monitoring Stack (Prometheus & Grafana)
```bash
kubectl apply -k "K8's/monitoring"
kubectl get pods -n monitoring
```
Access Grafana:
```bash
kubectl get svc grafana -n monitoring
# Open the LoadBalancer external hostname in your browser
# Default Credentials: admin / admin123
```

### Step 5: Install & Connect Argo CD
```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=10m

# Get Initial Argo CD Admin Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Register Application in Argo CD:
kubectl apply -f argocd/application.yaml
```

### Step 6: Verify Application Workloads
```bash
kubectl get all -n blog-app
kubectl get svc frontend-service -n blog-app
```
Open the `EXTERNAL-IP` (AWS Network/Application Load Balancer URL) to interact with the Blog Application!

---

## 4. DevOps Troubleshooting Guide (As Required by Assessment)

### Issue 1: Pod in CrashLoopBackOff
- **Diagnosis**:
  ```bash
  kubectl get pods -n blog-app
  kubectl describe pod <pod-name> -n blog-app
  kubectl logs <pod-name> -n blog-app --previous
  ```
- **Common Root Causes**:
  - Missing database credentials or inability to resolve `mysql-service`.
  - Application startup crash or uncaught runtime exception.
  - File permissions violation when running as non-root user (`securityContext`).
- **Resolution**: Verify Secret keys in `mysql-secret` and ConfigMap `mysql-config`. Ensure MySQL statefulset is `Ready` before backend starts.

### Issue 2: Argo CD Application OutOfSync
- **Diagnosis**:
  ```bash
  kubectl get application -n argocd
  kubectl describe application simple-blog-app -n argocd
  ```
- **Common Root Causes**:
  - Outdated Git revision or path mismatch in `argocd/application.yaml`.
  - Manual changes made to cluster (`kubectl edit`) conflicting with desired Git state.
- **Resolution**: Click "SYNC" in Argo CD dashboard or run `argocd app sync simple-blog-app --prune`. Ensure automated sync with self-heal is enabled in `spec.syncPolicy`.

### Issue 3: CI/CD Pipeline Failure (DevSecOps / GitHub Actions)
- **Diagnosis**: Inspect GitHub Actions job console logs under the failed step.
- **Common Root Causes**:
  - **Trivy / Gitleaks fail**: Unresolved high/critical vulnerabilities or dummy secret strings committed.
  - **ECR push denied**: AWS IAM OIDC Role ARN misconfigured or token expiration.
- **Resolution**:
  - Add specific CVE false positives to `.trivyignore`.
  - Check IAM condition string `repo:<org>/<repo>:*` matches repository name exactly.

### Issue 4: Application / Service Connectivity Issue
- **Diagnosis**:
  ```bash
  kubectl get endpoints -n blog-app
  kubectl exec -it deployment/backend -n blog-app -- curl -v http://mysql-service:3306
  ```
- **Common Root Causes**:
  - Misconfigured `targetPort` vs container port.
  - Service selector labels not matching pod labels.
  - CoreDNS failure or AWS Security Group blocking inter-node traffic.
- **Resolution**: Compare `spec.selector` in Service YAML with `metadata.labels` in Deployment YAML. Check Security Group rules for worker nodes.

---

## 5. Teardown & Cost Cleanup
To prevent unwanted AWS billing:
```bash
cd infra
terraform destroy -auto-approve
```
