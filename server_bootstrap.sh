#!/bin/bash
# =============================================================================
# Server Bootstrap Script — Run ONCE on 172.16.61.118 before first deployment
# =============================================================================
set -e

DEPLOY_DIR="/opt/dutychart"
NEXUS_REGISTRY="nexus.ntc.net.np"

echo "=== 1. Installing Docker (if not present) ==="
if ! command -v docker &> /dev/null; then
    apt-get update
    apt-get install -y docker.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
else
    echo "Docker already installed: $(docker --version)"
fi

echo "=== 2. Creating deployment directory ==="
mkdir -p "$DEPLOY_DIR"
echo "Directory ready: $DEPLOY_DIR"
echo "(Jenkins will upload .env and docker-compose.prod.yml here on every deploy)"

echo "=== 3. Allowing Nexus as insecure Docker registry ==="
cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["${NEXUS_REGISTRY}"]
}
EOF
systemctl restart docker
echo "Docker restarted with insecure-registries: ${NEXUS_REGISTRY}"

echo "=== 4. Done! Server is ready for Jenkins deployments. ==="
echo ""
echo "Note: On every push to 'main', Jenkins will:"
echo "  1. Copy .env and docker-compose.prod.yml to ${DEPLOY_DIR}"
echo "  2. Run: docker compose -f docker-compose.prod.yml pull"
echo "  3. Run: docker compose -f docker-compose.prod.yml up -d"
