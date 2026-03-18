pipeline {
    agent any

    // ─────────────────────────────────────────────────────────────────
    // All configurable values live here. Change these if anything moves.
    // ─────────────────────────────────────────────────────────────────
    environment {
        // Nexus Docker registry  (no http://, just host:port)
        NEXUS_REGISTRY  = "nexus.ntc.net.np"
        PROJECT         = "dutychart"

        // Image names (must match docker-compose.prod.yml)
        BACKEND_IMAGE   = "${NEXUS_REGISTRY}/${PROJECT}/dcms-backend"
        FRONTEND_IMAGE  = "${NEXUS_REGISTRY}/${PROJECT}/dcms-frontend"

        // Tag: Jenkins build number so every build is traceable
        IMAGE_TAG       = "${BUILD_NUMBER}"

        // Deploy server
        DEPLOY_HOST     = "172.16.61.118"
        DEPLOY_USER     = "ubuntu"          // ← change to your server OS user

        // Jenkins credential IDs (set up in Manage Jenkins → Credentials)
        NEXUS_CREDS_ID  = "nexus-docker-creds"   // Username/password
        DEPLOY_SSH_ID   = "deploy-server-ssh"     // SSH private key
        DOT_ENV_ID      = "dutychart-dot-env"     // Secret file → .env on server

    }

    stages {

        // ── 1. Checkout ────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ── 2. Build Images ────────────────────────────────────────────
        stage('Build Images') {
            parallel {

                stage('Build Backend') {
                    steps {
                        sh """
                            docker build \
                              -t ${BACKEND_IMAGE}:${IMAGE_TAG} \
                              -t ${BACKEND_IMAGE}:latest \
                              -f backend/Dockerfile \
                              ./backend
                        """
                    }
                }

                stage('Build Frontend') {
                    steps {
                        sh """
                            docker build \
                              --build-arg VITE_BACKEND_HOST="" \
                              -t ${FRONTEND_IMAGE}:${IMAGE_TAG} \
                              -t ${FRONTEND_IMAGE}:latest \
                              -f frontend/Dockerfile \
                              ./frontend
                        """
                    }
                }
            }
        }

        // ── 3. Push to Nexus ───────────────────────────────────────────
        stage('Push to Nexus') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${NEXUS_CREDS_ID}",
                    usernameVariable: 'NEXUS_USER',
                    passwordVariable: 'NEXUS_PASS'
                )]) {
                    sh '''
                        echo "$NEXUS_PASS" | docker login $NEXUS_REGISTRY \
                            -u "$NEXUS_USER" --password-stdin

                        # Push backend (versioned + latest)
                        docker push $BACKEND_IMAGE:$IMAGE_TAG
                        docker push $BACKEND_IMAGE:latest

                        # Push frontend (versioned + latest)
                        docker push $FRONTEND_IMAGE:$IMAGE_TAG
                        docker push $FRONTEND_IMAGE:latest

                        docker logout $NEXUS_REGISTRY
                    '''
                }
            }
        }

        // ── 4. Deploy to Server ────────────────────────────────────────
        stage('Deploy to Server') {
            steps {
                // Copy the .env secret file to the server, then pull & recreate containers
                withCredentials([
                    usernamePassword(
                        credentialsId: "${NEXUS_CREDS_ID}",
                        usernameVariable: 'NEXUS_USER',
                        passwordVariable: 'NEXUS_PASS'
                    ),
                    sshUserPrivateKey(
                        credentialsId: "${DEPLOY_SSH_ID}",
                        keyFileVariable: 'SSH_KEY'
                    ),
                    file(
                        credentialsId: "${DOT_ENV_ID}",
                        variable: 'ENV_FILE'
                    )
                ]) {
                    sh '''
                        # Upload files to server
                        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                            "$ENV_FILE" \
                            $DEPLOY_USER@$DEPLOY_HOST:/opt/dutychart/.env

                        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                            docker-compose.prod.yml \
                            $DEPLOY_USER@$DEPLOY_HOST:/opt/dutychart/docker-compose.prod.yml

                        # SSH in and deploy (heredoc lets the Jenkins shell expand secrets
                        # before sending the script to the remote server)
                        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                            $DEPLOY_USER@$DEPLOY_HOST bash -s << REMOTE_EOF
set -e
cd /opt/dutychart

# Login to Nexus on the server
echo "$NEXUS_PASS" | docker login $NEXUS_REGISTRY \\
    -u "$NEXUS_USER" --password-stdin

# Export the image tag so docker-compose.prod.yml can use it
export IMAGE_TAG="$IMAGE_TAG"

# Pull new images
docker compose -f docker-compose.prod.yml pull

# Recreate only changed containers (zero-downtime for others)
docker compose -f docker-compose.prod.yml up -d --remove-orphans

# Logout from registry
docker logout $NEXUS_REGISTRY

# Remove dangling images to free disk space
docker image prune -f
REMOTE_EOF
                    '''
                }
            }
        }
    }

    // ── Post Actions ───────────────────────────────────────────────────
    post {
        success {
            echo """
            ✅ Deployment successful!
               Backend  → ${BACKEND_IMAGE}:${IMAGE_TAG}
               Frontend → ${FRONTEND_IMAGE}:${IMAGE_TAG}
               Server   → http://${DEPLOY_HOST}
            """
        }
        failure {
            echo "❌ Pipeline failed. Check logs above."
        }
        always {
            // Clean up local Docker images to keep Jenkins disk usage low
            sh '''
                docker rmi $BACKEND_IMAGE:$IMAGE_TAG  || true
                docker rmi $FRONTEND_IMAGE:$IMAGE_TAG || true
                docker rmi $BACKEND_IMAGE:latest        || true
                docker rmi $FRONTEND_IMAGE:latest       || true
            '''
        }
    }
}
