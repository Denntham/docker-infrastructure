# Core Infrastructure Setup (HAProxy + Nginx)
# Generates configuration and docker-compose for HAProxy and Nginx

set -e

GENERATED_DIR=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source utilities
source "${SCRIPT_DIR}/scripts/utils.sh"

setup_haproxy() {
    log_info "Setting up HAProxy configuration..."
    
    local config_dir
    config_dir=$(ensure_config_dir "haproxy" "$GENERATED_DIR")
    
    # Create HAProxy configuration
    cat > "${config_dir}/haproxy.cfg" << 'EOF'
global
    maxconn 4096
    log stdout local0
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode http
    log global
    option httplog
    option dontlognull
    option log-health-checks
    option forwardfor
    option http-server-close
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend main
    bind *:80
    
    # Route to nginx for static content and web interfaces
    default_backend nginx_servers

frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

backend nginx_servers
    balance roundrobin
    option httpchk GET /health
    server nginx1 nginx:80 check
EOF
    
    log_success "HAProxy configuration created at ${config_dir}/haproxy.cfg"
}

setup_nginx() {
    log_info "Setting up Nginx configuration..."
    
    local config_dir
    config_dir=$(ensure_config_dir "nginx" "$GENERATED_DIR")
    
    # Create Nginx main configuration
    cat > "${config_dir}/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Create conf.d directory
    mkdir -p "${config_dir}/conf.d"
    
    # Create default server configuration
    cat > "${config_dir}/conf.d/default.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Future API proxy configuration
    location /api/ {
        # Will be configured when backend services are added
        return 503 "Backend services not configured";
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF
    
    log_success "Nginx configuration created at ${config_dir}/"
}

create_static_content() {
    log_info "Creating static content..."
    
    local static_dir="${GENERATED_DIR}/static"
    mkdir -p "$static_dir"
    
    # Create index.html
    cat > "${static_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Infrastructure Services</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .service { 
            margin: 15px 0; 
            padding: 15px; 
            border: 1px solid #ddd; 
            border-radius: 5px; 
            background-color: #fafafa;
        }
        .service h3 { 
            margin-top: 0; 
            color: #333; 
            border-bottom: 2px solid #007bff;
            padding-bottom: 5px;
        }
        .port { 
            color: #666; 
            font-family: monospace;
        }
        .status {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 12px;
            font-weight: bold;
        }
        .status.running { background-color: #d4edda; color: #155724; }
        .status.admin { background-color: #fff3cd; color: #856404; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Infrastructure Services Dashboard</h1>
        <p>Infrastructure services are running successfully!</p>
        
        <div class="service">
            <h3>HAProxy Load Balancer <span class="status running">RUNNING</span></h3>
            <p class="port">Port: 1000 | <a href="http://localhost:1001/stats" target="_blank">Stats Dashboard</a></p>
            <p>Main entry point for all web traffic with load balancing capabilities.</p>
        </div>
        
        <div class="service">
            <h3>Nginx Web Server <span class="status running">RUNNING</span></h3>
            <p class="port">Port: 1100 | <a href="http://localhost:1100" target="_blank">Direct Access</a></p>
            <p>Static content server and reverse proxy for application services.</p>
        </div>
        
        <div id="database-services" style="display: none;">
            <div class="service">
                <h3>PostgreSQL Admin <span class="status admin">ADMIN</span></h3>
                <p class="port">Port: 4011 | <a href="http://localhost:4011" target="_blank">pgAdmin Interface</a></p>
                <p>Web-based PostgreSQL administration interface (admin profile only).</p>
            </div>
            
            <div class="service">
                <h3>MongoDB Admin <span class="status admin">ADMIN</span></h3>
                <p class="port">Port: 4021 | <a href="http://localhost:4021" target="_blank">Mongo Express</a></p>
                <p>Web-based MongoDB administration interface (admin profile only).</p>
            </div>
        </div>
        
        <div class="service">
            <h3>Service Status</h3>
            <p>Check all service status with: <code>docker-compose ps</code></p>
            <p>Enable database admin tools: <code>docker-compose --profile admin up -d</code></p>
        </div>
    </div>
    
    <script>
        // Show/hide database services based on what's available
        if (window.location.search.includes('admin') || document.referrer.includes('4011') || document.referrer.includes('4021')) {
            document.getElementById('database-services').style.display = 'block';
        }
    </script>
</body>
</html>
EOF
    
    # Create logs directory
    mkdir -p "${GENERATED_DIR}/logs/nginx"
    
    log_success "Static content created at ${static_dir}/"
}

generate_compose() {
    log_info "Generating Docker Compose configuration for core services..."
    
    local compose_dir="${GENERATED_DIR}/compose"
    mkdir -p "$compose_dir"
    
    # Create volumes
    create_volume_entry "nginx_logs" "$GENERATED_DIR"
    
    # Generate core services compose
    cat > "${compose_dir}/core.yml" << 'EOF'

  # =============================================================================
  # CORE INFRASTRUCTURE (1000-1999)
  # =============================================================================
  
  haproxy:
    image: haproxy:2.8-alpine
    container_name: haproxy
    ports:
      - "1000:80"
      - "1001:8404"  # HAProxy stats
    volumes:
      - ./config/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    networks:
      - frontend
      - backend
    depends_on:
      - nginx
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.2'
        reservations:
          memory: 64M
          cpus: '0.1'
    healthcheck:
      test: ["CMD", "haproxy", "-c", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
      interval: 30s
      timeout: 10s
      retries: 3

  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    ports:
      - "1100:80"
      - "1101:443"
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./static:/var/www/html:ro
      - nginx_logs:/var/log/nginx
    networks:
      - frontend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.3'
        reservations:
          memory: 128M
          cpus: '0.15'
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    
    log_success "Core services compose generated at ${compose_dir}/core.yml"
}

main() {
    log_info "Setting up core infrastructure (HAProxy + Nginx)..."
    
    # Setup configurations
    setup_haproxy
    setup_nginx
    create_static_content
    
    # Generate compose file
    generate_compose
    
    log_success "Core infrastructure setup completed successfully!"
}

# Run main function
main