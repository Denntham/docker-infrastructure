# PostgreSQL Database Setup
# Generates configuration and docker-compose for PostgreSQL with pgAdmin

set -e

GENERATED_DIR=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source utilities
source "${SCRIPT_DIR}/scripts/utils.sh"

setup_postgresql_config() {
    log_info "Setting up PostgreSQL configuration..."
    
    local config_dir
    config_dir=$(ensure_config_dir "postgresql" "$GENERATED_DIR")
    
    # Create PostgreSQL configuration
    cat > "${config_dir}/postgresql.conf" << 'EOF'
# PostgreSQL Configuration
# Basic production-ready settings

# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB

# WAL settings
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB

# Logging settings
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 10MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_min_duration_statement = 1000

# Performance settings
random_page_cost = 1.1
effective_io_concurrency = 200
EOF

    # Create pg_hba.conf for authentication
    cat > "${config_dir}/pg_hba.conf" << 'EOF'
# PostgreSQL Client Authentication Configuration File
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust

# IPv4 local connections:
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 local connections:
host    all             all             ::1/128                 scram-sha-256

# Allow connections from Docker network
host    all             all             172.22.0.0/24           scram-sha-256

# Allow connections from other Docker networks
host    all             all             172.20.0.0/16           scram-sha-256
EOF

    # Create initialization script
    cat > "${config_dir}/init.sql" << 'EOF'
-- PostgreSQL Initialization Script
-- Creates default database and user if they don't exist

-- Create application database
SELECT 'CREATE DATABASE ' || :'app_db_name'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'app_db_name')\gexec

-- Create application user
DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = :'app_user') THEN

      EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password');
   END IF;
END
$do$;

-- Grant privileges
\c :app_db_name
GRANT ALL PRIVILEGES ON DATABASE :"app_db_name" TO :"app_user";
GRANT ALL ON SCHEMA public TO :"app_user";
EOF
    
    log_success "PostgreSQL configuration created at ${config_dir}/"
}

setup_pgadmin_config() {
    log_info "Setting up pgAdmin configuration..."
    
    local config_dir
    config_dir=$(ensure_config_dir "pgadmin" "$GENERATED_DIR")
    
    # Create pgAdmin servers configuration
    cat > "${config_dir}/servers.json" << 'EOF'
{
    "Servers": {
        "1": {
            "Name": "PostgreSQL Server",
            "Group": "Servers",
            "Port": 5432,
            "Username": "",
            "Host": "postgresql",
            "SSLMode": "prefer",
            "MaintenanceDB": "postgres",
            "PassFile": "/var/lib/pgadmin/passfile"
        }
    }
}
EOF

    # Create passfile template (will be populated by environment variables)
    cat > "${config_dir}/passfile.template" << 'EOF'
# pgAdmin passfile template
# Format: hostname:port:database:username:password
postgresql:5432:*:${POSTGRES_USER}:${POSTGRES_PASSWORD}
EOF
    
    log_success "pgAdmin configuration created at ${config_dir}/"
}

generate_compose() {
    log_info "Generating Docker Compose configuration for PostgreSQL..."
    
    local compose_dir="${GENERATED_DIR}/compose"
    mkdir -p "$compose_dir"
    
    # Create volumes
    create_volume_entry "postgres_data" "$GENERATED_DIR"
    create_volume_entry "pgadmin_data" "$GENERATED_DIR"
    
    # Generate PostgreSQL compose
    cat > "${compose_dir}/postgresql.yml" << 'EOF'

  # =============================================================================
  # POSTGRESQL DATABASE (4010)
  # =============================================================================
  
  postgresql:
    image: postgres:15-alpine
    container_name: postgresql
    # No external ports exposed - internal access only
    expose:
      - "5432"
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"
      # Application database settings
      APP_DB_NAME: ${APP_DB_NAME}
      APP_USER: ${APP_USER}
      APP_PASSWORD: ${APP_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./config/postgresql/postgresql.conf:/etc/postgresql/postgresql.conf:ro
      - ./config/postgresql/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro
      - ./config/postgresql/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - database
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 10s
      retries: 3
    command: >
      postgres
      -c config_file=/etc/postgresql/postgresql.conf
      -c hba_file=/etc/postgresql/pg_hba.conf

  # =============================================================================
  # PGADMIN WEB INTERFACE (4011) - ADMIN PROFILE ONLY
  # =============================================================================
  
  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: pgadmin
    profiles:
      - admin
    ports:
      - "4011:80"
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
      PGADMIN_CONFIG_SERVER_MODE: 'False'
      PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: 'False'
    volumes:
      - pgadmin_data:/var/lib/pgadmin
      - ./config/pgadmin/servers.json:/pgadmin4/servers.json:ro
    networks:
      - database
      - frontend
    depends_on:
      - postgresql
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
      test: ["CMD-SHELL", "curl -f http://localhost:80/misc/ping || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    
    log_success "PostgreSQL compose generated at ${compose_dir}/postgresql.yml"
}

generate_env_template() {
    log_info "Adding PostgreSQL environment variables to template..."
    
    local env_template="${SCRIPT_DIR}/.env.example"
    
    # Add PostgreSQL variables if not already present
    if ! grep -q "POSTGRES_" "$env_template" 2>/dev/null; then
        cat >> "$env_template" << 'EOF'

# PostgreSQL Configuration
POSTGRES_DB=appdb
POSTGRES_USER=admin
POSTGRES_PASSWORD=changeme_postgres_password

# Application Database
APP_DB_NAME=appdb
APP_USER=appuser
APP_PASSWORD=changeme_app_password

# pgAdmin Configuration
PGADMIN_EMAIL=admin@example.com
PGADMIN_PASSWORD=changeme_pgadmin_password
EOF
        log_success "PostgreSQL environment variables added to .env.example"
    fi
}

create_documentation() {
    log_info "Creating PostgreSQL documentation..."
    
    local docs_dir="${GENERATED_DIR}/docs"
    mkdir -p "$docs_dir"
    
    cat > "${docs_dir}/postgresql.md" << 'EOF'
# PostgreSQL Database Setup

## Overview

PostgreSQL database server with web-based administration interface.

## Services

### PostgreSQL Database
- **Internal Port**: 5432
- **Container**: postgresql
- **Networks**: database
- **Volumes**: postgres_data

### pgAdmin (Admin Profile Only)
- **External Port**: 4011
- **Container**: pgadmin
- **Networks**: database, frontend
- **Volumes**: pgadmin_data

## Configuration

### Environment Variables
- `POSTGRES_DB`: Main database name
- `POSTGRES_USER`: Admin username
- `POSTGRES_PASSWORD`: Admin password
- `APP_DB_NAME`: Application database name
- `APP_USER`: Application user
- `APP_PASSWORD`: Application user password
- `PGADMIN_EMAIL`: pgAdmin login email
- `PGADMIN_PASSWORD`: pgAdmin login password

### Database Access

#### Internal Access (from other containers)
```
Host: postgresql
Port: 5432
Database: ${POSTGRES_DB}
```

#### Development Access (admin profile)
1. Start with admin profile:
   ```bash
   docker-compose --profile admin up -d
   ```
2. Access pgAdmin: http://localhost:4011
3. Login with `PGADMIN_EMAIL` and `PGADMIN_PASSWORD`

#### Production Access
Use SSH tunneling:
```bash
ssh -L 4011:localhost:4011 user@server
```

## Database Initialization

The setup includes automatic database and user creation:
- Creates application database (`APP_DB_NAME`)
- Creates application user (`APP_USER`)
- Grants necessary privileges

## Backup Recommendations

Regular backups using pg_dump:
```bash
docker exec postgresql pg_dump -U admin appdb > backup.sql
```

## Security Notes

- Database ports are not exposed externally
- Uses scram-sha-256 authentication
- Admin interface only available with admin profile
- Custom pg_hba.conf for network access control
EOF
    
    log_success "PostgreSQL documentation created at ${docs_dir}/postgresql.md"
}

main() {
    log_info "Setting up PostgreSQL database..."
    
    # Setup configurations
    setup_postgresql_config
    setup_pgadmin_config
    
    # Generate compose file
    generate_compose
    
    # Update environment template
    generate_env_template
    
    # Create documentation
    create_documentation
    
    log_success "PostgreSQL setup completed successfully!"
    log_info "Remember to update database credentials in .env file"
    log_info "Use --profile admin to enable pgAdmin web interface"
}

# Run main function
main