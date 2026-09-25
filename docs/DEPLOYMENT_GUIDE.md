# AWS EC2 & Docker Production Deployment Guide

This operations runbook details the setup, configuration, data initialization, and deployment of the **Zero-Trust Clinical EHR Decision Support Platform** on AWS EC2.

---

## 1. AWS EC2 Provisioning

### Recommended Hardware Specs
- **OS**: Ubuntu 24.04 LTS (x86_64)
- **Instance Type**: `t3.large` or `c6i.large` (2 vCPU, 8 GB RAM minimum for PyTorch and Presidio transformers)
- **Storage**: 30–40 GB gp3 SSD
- **Public IPv4**: Enabled

### Security Group Inbound Rules
| Type | Port | Protocol | Source | Description |
|---|---|---|---|---|
| SSH | 22 | TCP | Your IP | Secure shell management |
| Custom TCP | 8501 | TCP | 0.0.0.0/0 (or VPN CIDR) | Streamlit Clinical Console |
| Custom TCP | 5432 | TCP | EC2 Security Group ID | PostgreSQL Database (if external) |

> **Note**: Port `8000` (FastAPI) is handled internally within the container and should **not** be opened to the public internet.

---

## 2. PostgreSQL 14 & pgvector Setup

If hosting the database on EC2 or self-managed server:

```bash
# 1. Add PostgreSQL official APT repository
sudo apt update && sudo apt install -y curl ca-certificates lsb-release
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# 2. Install PostgreSQL 14 and pgvector
sudo apt update
sudo apt install -y postgresql-14 postgresql-contrib-14 postgresql-14-pgvector

# 3. Create database and administrative user
sudo -u postgres psql -c "CREATE DATABASE ehr_db;"
sudo -i -u postgres psql
```

Inside the PostgreSQL shell:
```sql
CREATE USER ehr_admin WITH PASSWORD 'SecureClinical2026!';
ALTER ROLE ehr_admin SET client_encoding TO 'utf8';
ALTER ROLE ehr_admin SET default_transaction_isolation TO 'read committed';
ALTER ROLE ehr_admin SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE ehr_db TO ehr_admin;

\c ehr_db
CREATE EXTENSION IF NOT EXISTS vector;
GRANT ALL ON SCHEMA public TO ehr_admin;
\q
```

---

## 3. Docker & Host Preparation

```bash
# Update Ubuntu packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl git nano

# Install Docker CE
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable Docker and add current user
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

---

## 4. Repository Initialization & Configuration

```bash
# Clone the repository
cd ~
git clone git@github.com:superezzdev/coldchain-ai.git clinical-ehr-rag
cd clinical-ehr-rag

# Configure production environment variables
cp .env.example .env
nano .env
```

Ensure `.env` contains:
```env
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=ehr_db
DB_USER=ehr_admin
DB_PASSWORD=SecureClinical2026!

OPENAI_API_KEY=your_deepseek_or_openai_key
OPENAI_BASE_URL=https://api.deepseek.com/v1
```

Set secure permissions on `.env`:
```bash
chmod 600 .env
```

---

## 5. Data Ingestion & Embedding Generation

Run the pipeline scripts in sequence:

```bash
# Create local virtual environment for setup tasks
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 1. Ingest baseline relational patient encounters
python scripts/01_ingest_baseline_data.py

# 2. Verify record counts and schema
python scripts/02_verify_ingestion.py

# 3. Apply pgvector schema migration
python scripts/03_apply_vector_schema.py

# 4. Generate BioClinical ModernBERT embeddings (768-dim)
python scripts/04_generate_embeddings.py

# 5. Test semantic vector retrieval
python scripts/05_test_vector_search.py

# 6. Verify NeMo safety guardrails firewall
python scripts/06_test_guardrails.py

deactivate
```

---

## 6. Container Build & Orchestration

Deploy using Docker Compose:

```bash
# Build and run container in detached mode
docker compose up -d --build

# Inspect active container status
docker ps

# Stream application logs
docker logs -f clinical-ehr-rag
```

---

## 7. Health Checks & Verification

Verify the Streamlit health endpoint:
```bash
curl http://localhost:8501/_stcore/health
# Expected: ok
```

Verify the FastAPI backend from inside the container:
```bash
docker exec clinical-ehr-rag curl -fsS http://127.0.0.1:8000/openapi.json > /dev/null && echo "FastAPI is operational"
```

Access the web console in your browser:
```text
http://YOUR_EC2_PUBLIC_IP:8501
```
