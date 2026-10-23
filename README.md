# Blog App – EKS DevSecOps Deployment

## Overview

This repository contains a **containerised Blog application** (frontend + backend) that is built, scanned, pushed to Amazon ECR, and deployed to an **Amazon EKS** cluster using **GitOps** with **Argo CD**.  The deployment also provisions a **monitoring stack** (Prometheus + Grafana) and enables end‑to‑end CI/CD via **GitHub Actions**.

The repository layout (relevant folders) is:

```
.
├─ backend/                # Node.js backend source
├─ frontend/               # React/Vite frontend source
├─ Dockerfile              # Multi‑stage build for the backend image
├─ .github/workflows/      # GitHub Actions CI/CD pipeline
│   └─ DevSecOps.yml       # Build → Trivy scan → ECR push → GitOps update
├─ K8's/                  # Kustomize manifests for the app and monitoring
│   ├─ kustomization.yaml  # Base Kustomization file
│   ├─ namespace.yaml
│   ├─ backend/            # Backend Deployment & Service
│   ├─ frontend/           # Frontend Deployment & Service
│   └─ monitoring/         # Prometheus & Grafana manifests
└─ README.md               # ← this file
```

---

## Prerequisites (Windows)

| Tool | Why needed | Install command / link |
|------|------------|------------------------|
| **Git** | Source control, push/pull | <https://git-scm.com/downloads> |
| **PowerShell 7+** (or cmd) | Run the commands below | <https://github.com/PowerShell/PowerShell/releases> |
| **Docker Desktop** | Build multi‑stage images | <https://www.docker.com/products/docker-desktop> |
| **AWS CLI** (`aws`) | Authenticate with EKS & ECR | `winget install --id Amazon.AWSCLI` |
| **kubectl** | Interact with the cluster | `winget install Kubernetes.kubectl` |
| **eksctl** | Create / update EKS clusters (optional) | `winget install eksctl` |
| **kustomize** | Render manifests for Argo CD | `choco install kustomize` (or `winget install kustomize`) |
| **jq** (optional) | JSON parsing for scripts | `choco install jq` |
| **Node.js 22 (LTS)** | Build the frontend locally (optional) | <https://nodejs.org/en/download> |
| **Python 3.11+** | Required for some helper scripts | <https://www.python.org/downloads/> |
| **Helm** (optional for extra charts) | Install other tools via Helm | `winget install Helm.Helm` |
| **Trivy** (static image scanner) | Security scanning in CI | `winget install AquaSecurity.Trivy` |

> **Tip**: After installing Docker Desktop, ensure the Docker daemon is running before executing any `docker` commands.

---

## Local Development Setup

1. **Clone the repository**
   ```powershell
   git clone https://github.com/pratikgayakwad07/blog-app-eks-devsecops.git
   cd blog-app-eks-devsecops
   ```

2. **Configure AWS credentials** (profile `default` is assumed).  You need a user/role with permissions for EKS, ECR and IAM.
   ```powershell
   aws configure   # set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, region, output
   ```

3. **Verify you can reach the EKS cluster**
   ```powershell
   # Replace <cluster-name> with the name defined in your kubeconfig (see below)
   aws eks update-kubeconfig --region us-east-1 --name blog-prod-eks
   kubectl get nodes
   ```
   You should see a list of worker nodes.

4. **Optional – Build images locally** (useful for testing before CI runs)
   ```powershell
   # Build backend image (multi‑stage Dockerfile)
   docker build -t backend:local .

   # Tag and push to your own ECR (replace <account-id> and <repo>)
   $accountId = (aws sts get-caller-identity --query Account --output text)
   $ecrRepo  = "$accountId.dkr.ecr.us-east-1.amazonaws.com/backend-blog-app"
   docker tag backend:local $ecrRepo:dev
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $accountId.dkr.ecr.us-east-1.amazonaws.com
   docker push $ecrRepo:dev
   ```

---

## GitHub Actions CI/CD Pipeline (`.github/workflows/DevSecOps.yml`)

The workflow runs on every push to `main` and performs the following steps:

1. **Checkout repository**
2. **Set up Docker** (Docker Buildx) – needed for multi‑arch builds.
3. **Build backend image** (Dockerfile) – produces a slim `nodejs22` image.
4. **Trivy scan** – fails the pipeline if any CVEs with severity ≥ `HIGH` are found.
5. **Push image to Amazon ECR** – the image is tagged with the Git SHA.
6. **Update `kustomization.yaml`** – `kustomize edit set image …` rewrites the image tag in `K8's/kustomization.yaml` and commits the change back to the repo.
7. **Argo CD sync** – the GitOps update triggers Argo CD (already installed on the cluster) to roll out the new image.
8. **Verification** – a lightweight job checks that the pods are `Ready` after the rollout.

You can view the full workflow file in the repo under `.github/workflows/DevSecOps.yml`.

---

## Deploying the Application with GitOps (Argo CD)

### 1️⃣ Install Argo CD (one‑time)
```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# Wait for all pods to be Ready (~1 minute)
kubectl wait --for=condition=Ready pod -n argocd --all --timeout=180s
```

### 2️⃣ Access the Argo CD UI
```powershell
# Port‑forward to localhost (run in a separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Open <http://localhost:8080>. Retrieve the admin password:
```powershell
kubectl -n argocd get secret argocd-initial-admin-secret \
   -o jsonpath="{.data.password}" | % { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

### 3️⃣ Register the repository in Argo CD
* In the UI click **Settings → Repositories → Connect Repo URL**
* Repo URL: `https://github.com/pratikgayakwad07/blog-app-eks-devsecops.git`
* Choose **GitHub** as provider and authenticate with a **personal access token** that has `repo` scope.

### 4️⃣ Create the Application
* Click **+ New App**
* **Application name**: `blog-app`
* **Project**: `default`
* **Sync policy**: *Automated* (optional: enable *Prune* & *Self‑heal*)
* **Repository URL**: the repo you just added
* **Path**: `K8's`
* **Cluster URL**: `https://kubernetes.default.svc`
* **Namespace**: `blog-app` (or any namespace you prefer; the manifest includes a `Namespace.yaml` that will be created)
* Save & click **Sync**.

Argo CD will now render the Kustomize overlays, pull the images from ECR and create the backend, frontend, Prometheus & Grafana resources.

---

## Monitoring Stack (Prometheus + Grafana)

All monitoring manifests live under `K8's/monitoring`.  They are applied automatically by the GitOps sync because they are listed in the root `kustomization.yaml`.

If you need to apply them manually (for debugging):
```powershell
kubectl apply -k "C:/Users/prati/Desktop/blog-app-fixed/K8's/monitoring"
```

**Access Grafana**
```powershell
kubectl port-forward svc/grafana -n monitoring 3000:80
```
Open <http://localhost:3000> (default credentials: `admin / admin`).

**Access Prometheus**
```powershell
kubectl port-forward svc/prometheus -n monitoring 9090:9090
```
Open <http://localhost:9090>.

---

## Full Deployment Workflow (summary)

1. **Developer makes code change** → pushes to `main`.
2. GitHub Actions workflow builds the Docker image, runs Trivy, pushes to ECR, updates `K8's/kustomization.yaml` with the new image tag and pushes that change back to the repo.
3. Argo CD detects the commit, renders the Kustomize overlays and applies the new manifests to the EKS cluster.
4. Pods roll out the new image; the CI job verifies that all pods become `Ready`.
5. Prometheus scrapes the `frontend` and `backend`; Grafana dashboards are automatically populated.

---

## Cleanup (optional)

```powershell
# Delete the GitOps app from Argo CD
argocd app delete blog-app --cascade
# Or via kubectl
kubectl delete -k "C:/Users/prati/Desktop/blog-app-fixed/K8's"
# Remove Argo CD installation
kubectl delete namespace argocd
# Remove monitoring stack
kubectl delete namespace monitoring
```

---

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| `kubectl get pods` shows `ImagePullBackOff` | Verify the image tag in `K8's/kustomization.yaml` matches what exists in ECR. | Re‑run the CI pipeline or manually tag the image and push. |
| Argo CD UI shows **OutOfSync** and **error** | Look at the **Events** tab of the failing resource. Common causes are missing ConfigMaps or mismatched resource names. | Ensure the `monitoring` Kustomization resources are present and that the `namespace.yaml` creates the correct namespace. |
| Prometheus not scraping pods | Verify the `prometheus-config.yaml` contains the correct `scrape_configs` for `frontend` and `backend` services. | Re‑apply the monitoring Kustomization or patch the ConfigMap. |
| `kubectl` cannot connect (TLS handshake timeout) | Your local `~/.kube/config` may be outdated. | Run `aws eks update-kubeconfig --region us-east-1 --name blog-prod-eks` again. |

---

## License

This project is licensed under the **MIT License** – see the `LICENSE` file for details.

---

## Contact & Contributions

* **Author**: Pratik Gayakwad (GitHub: `pratikgayakwad07`)
* **Issues & Feature Requests**: Open a GitHub Issue.
* **Pull Requests**: Feel free to fork the repo, make improvements and submit a PR.
