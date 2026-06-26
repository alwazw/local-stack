Documentation

# 01 — Installation on Proxmox VM

## Prerequisites
1. Proxmox VM: Ubuntu 22.04/24.04, 4+ vCPU, 16GB+ RAM, 100GB+ disk
2. GPU passthrough if using Ollama locally
3. Domain: `home.local` or real domain with Cloudflare

## Step 1: Install Docker
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker version
```

Step 2: Install NVIDIA Toolkit (GPU only)

```
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

Step 3: Clone/Deploy AEF3
```
cd ~
mkdir docker && cd docker
# Paste aef3.sh here, then:
chmod +x aef3.sh
./aef3.sh ~/docker
```

Step 4: Configure

```
cd ~/docker
cp.env.example.env
nano.env
# Set: DOMAIN=home.local, CF_API_EMAIL
```

Step 5: Bootstrap
```
./scripts/bootstrap.sh
```
This creates: secrets + docker networks + data dirs

Step 6: Deploy Core Stack
```
# Networks must exist first
docker network create proxy
docker network create database --internal
docker network create ai-ml --internal

# Start in order
cd compose/data/postgres && docker compose up -d
cd../redis && docker compose up -d
cd../../network/traefik && docker compose up -d
cd../../security/authentik && docker compose up -d
```

Step 7: Authentik Setup

- Go to http://<vm-ip>:9000/if/flow/initial-setup/
- Create admin user
- Create Proxy Provider for each app

Step 8: Deploy Apps
```
cd ~/docker/compose/ai/ollama && docker compose up -d
cd../openwebui && docker compose up -d
```
Done. Check docker ps — you should see 6+ containers.
```

