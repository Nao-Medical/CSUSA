#!/bin/bash

# Add swap space to prevent OOM issues
echo "Setting up swap space..."
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Check swap status
echo "Verifying swap space..."
free -h

# Create required directories
echo "Creating directories..."
mkdir -p images uploads logs data-node meili_data_v1.12

# Check if .env exists, create if not
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << 'EOF'
PORT=3080
MEILI_MASTER_KEY=YourSecureMasterKeyHere
UID=$(id -u)
GID=$(id -g)
RAG_PORT=8000
EOF
    echo "Created default .env file. Edit with your settings if needed."
fi

# Pull the images first to avoid timeout issues
echo "Pulling Docker images..."
docker pull mongo
docker pull getmeili/meilisearch:v1.12.3
docker pull ankane/pgvector:latest
docker pull ghcr.io/danny-avila/librechat-rag-api-dev-lite:latest

# Ask which docker-compose file to use
echo "Which deployment would you like to use?"
echo "1. Regular docker-compose (with build)"
echo "2. Deploy docker-compose (with Nginx)"
read -p "Enter choice (1 or 2): " choice

# Start MongoDB first regardless of choice
echo "Starting services one by one to manage resource usage..."

if [ "$choice" = "1" ]; then
    # Save the docker-compose file
    cat > docker-compose.yml << 'EOF'
services:
  api:
    container_name: LibreChat
    ports:
      - "${PORT}:${PORT}"
    depends_on:
      - mongodb
      - rag_api
    # Replaced image with build configuration
    build:
      context: .
      dockerfile: Dockerfile
    restart: always
    user: "${UID}:${GID}"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - HOST=0.0.0.0
      - MONGO_URI=mongodb+srv://sid1:wz4IAN1kwI6GBBfy@thechangecompanies.q7m62.mongodb.net/thechangecompanies?retryWrites=true
      - MEILI_HOST=http://meilisearch:7700
      - RAG_PORT=${RAG_PORT:-8000}
      - RAG_API_URL=http://rag_api:${RAG_PORT:-8000}
    volumes:
      - type: bind
        source: ./.env
        target: /app/.env
      - ./images:/app/client/public/images
      - ./uploads:/app/uploads
      - ./logs:/app/api/logs
  mongodb:
    container_name: chat-mongodb
    image: mongo
    restart: always
    user: "${UID}:${GID}"
    volumes:
      - ./data-node:/data/db
    command: mongod --noauth
  meilisearch:
    container_name: chat-meilisearch
    image: getmeili/meilisearch:v1.12.3
    restart: always
    user: "${UID}:${GID}"
    environment:
      - MEILI_HOST=http://meilisearch:7700
      - MEILI_NO_ANALYTICS=true
      - MEILI_MASTER_KEY=${MEILI_MASTER_KEY}
    volumes:
      - ./meili_data_v1.12:/meili_data
  vectordb:
    container_name: vectordb
    image: ankane/pgvector:latest
    environment:
      POSTGRES_DB: mydatabase
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
    restart: always
    volumes:
      - pgdata2:/var/lib/postgresql/data
  rag_api:
    container_name: rag_api
    image: ghcr.io/danny-avila/librechat-rag-api-dev-lite:latest
    environment:
      - DB_HOST=vectordb
      - RAG_PORT=${RAG_PORT:-8000}
    restart: always
    depends_on:
      - vectordb
    env_file:
      - .env
volumes:
  pgdata2:
EOF

    echo "Starting MongoDB..."
    docker-compose up -d mongodb
    sleep 10  # Give MongoDB time to initialize

    echo "Starting Meilisearch..."
    docker-compose up -d meilisearch
    sleep 5

    echo "Starting Vector DB..."
    docker-compose up -d vectordb
    sleep 10

    echo "Starting RAG API..."
    docker-compose up -d rag_api
    sleep 5

    echo "Building and starting LibreChat API..."
    echo "Note: Building the image might take some time on a resource-constrained VM."
    docker-compose up -d api

    echo "Deployment complete! LibreChat should be available at http://localhost:${PORT}"

elif [ "$choice" = "2" ]; then
    # Save the docker-compose.deploy.yml file
    cat > docker-compose.yml << 'EOF'
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile.multi
      target: api-build
    container_name: LibreChat-API
    ports:
      - 3080:3080
    depends_on:
      - mongodb
      - rag_api
    restart: always
    extra_hosts:
    - "host.docker.internal:host-gateway"
    env_file:
      - .env
    environment:
      - HOST=0.0.0.0
      - NODE_ENV=production
      - MONGO_URI=mongodb+srv://sid1:wz4IAN1kwI6GBBfy@thechangecompanies.q7m62.mongodb.net/thechangecompanies?retryWrites=true
      - MEILI_HOST=http://meilisearch:7700
      - RAG_PORT=${RAG_PORT:-8000}
      - RAG_API_URL=http://rag_api:${RAG_PORT:-8000}
    volumes:
      - type: bind
        source: ./librechat.yaml
        target: /app/librechat.yaml
      - ./images:/app/client/public/images
      - ./uploads:/app/uploads
      - ./logs:/app/api/logs
  client:
    image: nginx:1.27.0-alpine
    container_name: LibreChat-NGINX
    ports:
      - 80:80
      - 443:443
    depends_on:
      - api
    restart: always
    volumes:
      - ./client/nginx.conf:/etc/nginx/conf.d/default.conf
      - /etc/letsencrypt/live/chat.changecompanies.net:/etc/letsencrypt/live/chat.changecompanies.net
      - /etc/letsencrypt/archive/chat.changecompanies.net:/etc/letsencrypt/archive/chat.changecompanies.net
      - /etc/letsencrypt/options-ssl-nginx.conf:/etc/letsencrypt/options-ssl-nginx.conf
      - /etc/letsencrypt/ssl-dhparams.pem:/etc/letsencrypt/ssl-dhparams.pem
  mongodb:
    container_name: chat-mongodb
    image: mongo
    restart: always
    volumes:
      - ./data-node:/data/db
    command: mongod --noauth
  meilisearch:
    container_name: chat-meilisearch
    image: getmeili/meilisearch:v1.12.3
    restart: always
    env_file:
      - .env
    environment:
      - MEILI_HOST=http://meilisearch:7700
      - MEILI_NO_ANALYTICS=true
    volumes:
      - ./meili_data_v1.12:/meili_data
  vectordb:
    image: ankane/pgvector:latest
    environment:
      POSTGRES_DB: mydatabase
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
    restart: always
    volumes:
      - pgdata2:/var/lib/postgresql/data
  rag_api:
    image: ghcr.io/danny-avila/librechat-rag-api-dev-lite:latest
    environment:
      - DB_HOST=vectordb
      - RAG_PORT=${RAG_PORT:-8000}
    restart: always
    depends_on:
      - vectordb
    env_file:
      - .env
volumes:
  pgdata2:
EOF

    # Check for required files
    if [ ! -f librechat.yaml ]; then
        echo "Creating sample librechat.yaml file..."
        echo "# Sample configuration" > librechat.yaml
        echo "CAUTION: Make sure to create a proper librechat.yaml file for production use."
    fi

    if [ ! -d client ]; then
        mkdir -p client
    fi

    if [ ! -f client/nginx.conf ]; then
        echo "Creating sample nginx.conf file..."
        cat > client/nginx.conf << 'EOF'
server {
    listen 80;
    server_name chat.changecompanies.net;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name chat.changecompanies.net;

    ssl_certificate /etc/letsencrypt/live/chat.changecompanies.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chat.changecompanies.net/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://api:3080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
        echo "CAUTION: The nginx.conf is a sample. You will need to update it for your domain."
    fi

    # Check for Dockerfile.multi
    if [ ! -f Dockerfile.multi ]; then
        echo "Error: Dockerfile.multi is missing. This is required for the deployment setup."
        exit 1
    fi

    echo "Starting MongoDB..."
    docker-compose up -d mongodb
    sleep 10  # Give MongoDB time to initialize

    echo "Starting Meilisearch..."
    docker-compose up -d meilisearch
    sleep 5

    echo "Starting Vector DB..."
    docker-compose up -d vectordb
    sleep 10

    echo "Starting RAG API..."
    docker-compose up -d rag_api
    sleep 5

    echo "Building and starting LibreChat API..."
    echo "Note: Building the image might take some time on a resource-constrained VM."
    docker-compose up -d api
    sleep 10

    echo "Starting NGINX..."
    docker-compose up -d client

    echo "Deployment complete! LibreChat should be available at https://chat.changecompanies.net"
    echo "Make sure your DNS is properly configured and SSL certificates are valid."
else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo "Check logs with: docker logs LibreChat or docker logs LibreChat-API"