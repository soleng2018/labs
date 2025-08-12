#!/bin/bash

# Lab Infrastructure Setup Script
# This script sets up Traefik, Cloudflared tunnel, and Authentik

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if parameters.txt exists and is configured
check_parameters_file() {
    if [[ ! -f "parameters.txt" ]]; then
        print_error "parameters.txt file not found!"
        print_error "Please ensure parameters.txt exists and is properly configured before running this script."
        exit 1
    fi
    
    # Check if file contains placeholder values
    if grep -q "YOUR_" "parameters.txt" || grep -q "REPLACE_" "parameters.txt" || grep -q "CHANGEME" "parameters.txt"; then
        print_error "parameters.txt contains placeholder values!"
        print_error "Please configure all variables in parameters.txt before running this script."
        exit 1
    fi
    
    print_success "parameters.txt found and appears to be configured"
}

# Function to load variables from parameters.txt
load_parameters() {
    print_info "Loading parameters from parameters.txt..."
    source parameters.txt
    
    # Validate required variables
    required_vars=(
        "DOMAIN_NAME"
        "TRAEFIK_SUBDOMAIN" 
        "TRAEFIK_VERSION"
        "EMAIL"
        "CLOUDFLARE_API_KEY"
        "CLOUDFLARE_EMAIL"
        "CLOUDFLARE_ORIGIN_CERT"
        "CLOUDFLARE_ORIGIN_KEY"
        "CLOUDFLARED_TOKEN"
        "AUTHENTIK_SECRET_KEY"
        "PG_PASS"
        "AUTHENTIK_SUBDOMAIN"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            print_error "Required variable $var is not set in parameters.txt"
            exit 1
        fi
    done
    
    print_success "All required parameters loaded successfully"
}

# Function to create Docker network
create_network() {
    print_info "Creating Docker network 'traefik'..."
    
    if docker network ls | grep -q "traefik"; then
        print_warning "Network 'traefik' already exists, skipping creation"
    else
        docker network create traefik
        print_success "Docker network 'traefik' created successfully"
    fi
}

# Function to create directory structure
create_directories() {
    print_info "Creating directory structure..."
    
    directories=(
        "cloudflared"
        "traefik/secrets"
        "traefik/conf"
        "traefik/certs"
        "authentik/media"
        "authentik/custom-templates"
        "authentik/certs"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        print_info "Created directory: $dir"
    done
    
    print_success "Directory structure created successfully"
}

# Function to create Cloudflared files
create_cloudflared_files() {
    print_info "Creating Cloudflared configuration files..."
    
    # Create cloudflared/.env
    cat > cloudflared/.env << EOF
TUNNEL_TOKEN=${CLOUDFLARED_TOKEN}
EOF
    
    # Create cloudflared/docker-compose.yml
    cat > cloudflared/docker-compose.yml << 'EOF'
services:
  tunnel:
    container_name: cloudflared-tunnel
    image: cloudflare/cloudflared
    restart: unless-stopped
    command: tunnel run
    env_file:
      - .env
    networks:
      - traefik

networks:
  traefik:
    external: true
EOF
    
    print_success "Cloudflared files created successfully"
}

# Function to create Traefik files
create_traefik_files() {
    print_info "Creating Traefik configuration files..."
    
    # Create traefik/.env
    cat > traefik/.env << EOF
TRAEFIK_VERSION=${TRAEFIK_VERSION}
DOMAIN_NAME=${DOMAIN_NAME}
TRAEFIK_SUBDOMAIN=${TRAEFIK_SUBDOMAIN}
EMAIL=${EMAIL}
EOF
    
    # Create traefik/secrets/cf_api.secret
    echo "${CLOUDFLARE_API_KEY}" > traefik/secrets/cf_api.secret
    
    # Create traefik/secrets/cf_email.secret
    echo "${CLOUDFLARE_EMAIL}" > traefik/secrets/cf_email.secret
    
    # Create traefik/conf/cf_origin_cert.cert
    echo "${CLOUDFLARE_ORIGIN_CERT}" > traefik/conf/cf_origin_cert.cert
    
    # Create traefik/conf/cf_origin_key.key
    echo "${CLOUDFLARE_ORIGIN_KEY}" > traefik/conf/cf_origin_key.key
    
    # Create traefik/conf/cloudflare_origin_certs.yml
    cat > traefik/conf/cloudflare_origin_certs.yml << 'EOF'
tls:
  certificates:
    - certFile: /etc/traefik/conf/cf_origin_cert.cert
      keyFile: /etc/traefik/conf/cf_origin_key.key
EOF
    
    # Create traefik/conf/traefik_middleware.yml
    cat > traefik/conf/traefik_middleware.yml << 'EOF'
http:
  middlewares:
    authentik:
      forwardAuth:
        address: http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
          - X-authentik-name
          - X-authentik-uid
          - X-authentik-jwt
          - X-authentik-meta-jwks
          - X-authentik-meta-outpost
          - X-authentik-meta-provider
          - X-authentik-meta-app
          - X-authentik-meta-version
EOF
    
    # Create traefik/docker-compose.yml
    cat > traefik/docker-compose.yml << 'EOF'
services:
  traefik:
    container_name: traefik
    image: ${TRAEFIK_VERSION}
    restart: always
    ports:
      - 443:443
      - 80:80
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file=true
      - --providers.file.directory=/etc/traefik/conf/
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --entrypoints.websecure.address=:443
      - --entrypoints.websecure.forwardedheaders.insecure=true
      - --serverstransport.insecureskipverify=true
      - --log.level=DEBUG
      - --api=true
      - --api.insecure=true
      - --api.dashboard=true
      - --api.debug=true
      - --entrypoints.websecure.http.tls.certResolver=letsencrypt
      - --entrypoints.websecure.http.tls.domains[0].main=${DOMAIN_NAME}
      - --entrypoints.websecure.http.tls.domains[0].sans=*.${DOMAIN_NAME}
      - --certificatesresolvers.letsencrypt.acme.email=${EMAIL}
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.letsencrypt.acme.dnschallenge=true
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare
      - --certificatesResolvers.cfresolver.acme.dnsChallenge.resolvers=1.1.1.1:53,1.0.0.1:53
    secrets:
      - cf_email
      - cf_api
    environment:
      CF_API_EMAIL_FILE: /run/secrets/cf_email
      CF_API_KEY_FILE: /run/secrets/cf_api
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./certs:/letsencrypt
      - ./conf:/etc/traefik/conf/
    labels:
      traefik.enable: true
      traefik.http.routers.traefik.tls: true
      traefik.http.routers.traefik.rule: Host(`${TRAEFIK_SUBDOMAIN}.${DOMAIN_NAME}`)
      traefik.http.routers.traefik.entrypoints: websecure
      traefik.http.routers.traefik.service: api@internal
      traefik.http.routers.traefik.tls.certresolver: letsencrypt
      traefik.http.routers.traefik.middlewares: authentik@file
    networks:
      - traefik
    env_file:
      - .env

networks:
  traefik:
    external: true

secrets:
  cf_email:
    file: ./secrets/cf_email.secret
  cf_api:
    file: ./secrets/cf_api.secret
EOF
    
    print_success "Traefik files created successfully"
}

# Function to create Authentik files
create_authentik_files() {
    print_info "Creating Authentik configuration files..."
    
    # Create authentik/.env
    cat > authentik/.env << EOF
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
AUTHENTIK_ERROR_REPORTING__ENABLED=true
AUTHENTIK_DISABLE_UPDATE_CHECK=false
AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true
AUTHENTIK_AVATARS=initials
PG_PASS=${PG_PASS}
PG_USER=${PG_USER:-authentik}
PG_DB=${PG_DB:-authentik}
AUTHENTIK_IMAGE=${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}
AUTHENTIK_TAG=${AUTHENTIK_TAG:-2024.2.2}
EOF
    
    # Create authentik/docker-compose.yml
    cat > authentik/docker-compose.yml << 'EOF'
services:
  postgresql:
    image: docker.io/library/postgres:12-alpine
    container_name: authentik-db
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"]
      start_period: 20s
      interval: 30s
      retries: 5
      timeout: 5s
    volumes:
      - database:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${PG_PASS:?database password required}
      POSTGRES_USER: ${PG_USER:-authentik}
      POSTGRES_DB: ${PG_DB:-authentik}
    env_file:
      - .env
    networks:
      - traefik

  redis:
    image: docker.io/library/redis:alpine
    container_name: authentik-redis
    command: --save 60 1 --loglevel warning
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
      start_period: 20s
      interval: 30s
      retries: 5
      timeout: 3s
    volumes:
      - redis:/data
    networks:
      - traefik

  server:
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2024.2.2}
    container_name: authentik-server
    restart: unless-stopped
    command: server
    environment:
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
    volumes:
      - ./media:/media
      - ./custom-templates:/templates
    env_file:
      - .env
    depends_on:
      - postgresql
      - redis
    labels:
      traefik.enable: true
      traefik.http.routers.authentik.tls: true
      traefik.http.routers.authentik.rule: Host(`${AUTHENTIK_SUBDOMAIN}.${DOMAIN_NAME}`)
      traefik.http.routers.authentik.tls.certresolver: letsencrypt
      traefik.http.routers.authentik.entrypoints: websecure
      traefik.http.routers.authentik.service: authentik-svc
      traefik.http.services.authentik-svc.loadBalancer.server.port: 9000
    networks:
      - traefik

  worker:
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2024.2.2}
    container_name: authentik-worker
    restart: unless-stopped
    command: worker
    environment:
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
    user: root
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./media:/media
      - ./certs:/certs
      - ./custom-templates:/templates
    env_file:
      - .env
    depends_on:
      - postgresql
      - redis
    networks:
      - traefik

networks:
  traefik:
    external: true

volumes:
  database:
    driver: local
  redis:
    driver: local
EOF
    
    # Update the authentik docker-compose.yml to use variables from .env
    sed -i "s/authentik\.nilenetworks\.com/\${AUTHENTIK_SUBDOMAIN}.\${DOMAIN_NAME}/g" authentik/docker-compose.yml
    
    print_success "Authentik files created successfully"
}

# Function to set proper permissions
set_permissions() {
    print_info "Setting proper file permissions..."
    
    # Set restrictive permissions on secret files
    chmod 600 traefik/secrets/*
    chmod 600 traefik/conf/cf_origin_cert.cert
    chmod 600 traefik/conf/cf_origin_key.key
    chmod 600 *//.env
    
    # Set directory permissions
    chmod 755 cloudflared traefik authentik
    chmod 755 traefik/secrets traefik/conf authentik/media authentik/custom-templates
    
    print_success "File permissions set successfully"
}

# Function to display summary
display_summary() {
    print_success "=================================="
    print_success "Lab setup completed successfully!"
    print_success "=================================="
    echo
    print_info "Created services:"
    print_info "  • Traefik reverse proxy at: https://${TRAEFIK_SUBDOMAIN}.${DOMAIN_NAME}"
    print_info "  • Authentik SSO at: https://${AUTHENTIK_SUBDOMAIN}.${DOMAIN_NAME}"
    print_info "  • Cloudflared tunnel configured"
    echo
    print_info "Next steps:"
    print_info "  1. Start Traefik: cd traefik && docker-compose up -d"
    print_info "  2. Start Cloudflared: cd cloudflared && docker-compose up -d"
    print_info "  3. Start Authentik: cd authentik && docker-compose up -d"
    echo
    print_warning "Note: Make sure your DNS records point to your Cloudflare tunnel before starting the services."
}

# Main execution
main() {
    print_info "Starting lab infrastructure setup..."
    echo
    
    check_parameters_file
    load_parameters
    create_network
    create_directories
    create_cloudflared_files
    create_traefik_files
    create_authentik_files
    set_permissions
    display_summary
}

# Run main function
main "$@"