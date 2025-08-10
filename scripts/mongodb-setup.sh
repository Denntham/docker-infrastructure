# MongoDB Database Setup
# Generates configuration and docker-compose for MongoDB with Mongo Express

set -e

GENERATED_DIR=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source utilities
source "${SCRIPT_DIR}/scripts/utils.sh"

setup_mongodb_config() {
    log_info "Setting up MongoDB configuration..."
    
    local config_dir
    config_dir=$(ensure_config_dir "mongodb" "$GENERATED_DIR")
    
    # Create MongoDB configuration
    cat > "${config_dir}/mongod.conf" << 'EOF'
# MongoDB Configuration File

# Network interfaces
net:
  port: 27017
  bindIp: 0.0.0.0

# Storage settings
storage:
  dbPath: /data/db
  # Journal is enabled by default in modern MongoDB versions
  wiredTiger:
    engineConfig:
      cacheSizeGB: 0.25

# Logging
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  logRotate: rename
  verbosity: 1

# Process management
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

# Security
security:
  authorization: enabled

# Operation profiling
operationProfiling:
  slowOpThresholdMs: 100
  mode: slowOp

# Replication (for future use)
#replication:
#  replSetName: "rs0"

# Sharding (for future use)
#sharding:
#  clusterRole: configsvr
EOF

    # Create initialization script
    cat > "${config_dir}/init-mongo.js" << 'EOF'
// MongoDB Initialization Script
// Creates admin user and application database

// Switch to admin database
db = db.getSiblingDB('admin');

// Create admin user
db.createUser({
  user: process.env.MONGO_INITDB_ROOT_USERNAME,
  pwd: process.env.MONGO_INITDB_ROOT_PASSWORD,
  roles: [
    { role: 'userAdminAnyDatabase', db: 'admin' },
    { role: 'dbAdminAnyDatabase', db: 'admin' },
    { role: 'readWriteAnyDatabase', db: 'admin' }
  ]
});

// Create application database and user
db = db.getSiblingDB(process.env.MONGO_APP_DB || 'appdb');

db.createUser({
  user: process.env.MONGO_APP_USER || 'appuser',
  pwd: process.env.MONGO_APP_PASSWORD || 'changeme',
  roles: [
    { role: 'readWrite', db: process.env.MONGO_APP_DB || 'appdb' }
  ]
});

// Create initial collection
db.createCollection('initialized');
db.initialized.insertOne({
  message: 'Database initialized successfully',
  timestamp: new Date()
});

print('MongoDB initialization completed');
EOF

    # Create log directory script
    cat > "${config_dir}/create-log-dir.sh" << 'EOF'
#!/bin/bash
# Create log directory and set permissions
mkdir -p /var/log/mongodb
chown -R mongodb:mongodb /var/log/mongodb
EOF
    
    chmod +x "${config_dir}/create-log-dir.sh"
    
    log_success "MongoDB configuration created at ${config_dir}/"
}

setup_mongo_express_config() {
    log_info "Setting up Mongo Express configuration..."
    
    local config_dir
    config_dir=$(ensure_config_dir "mongo-express" "$GENERATED_DIR")
    
    # Create Mongo Express configuration
    cat > "${config_dir}/config.js" << 'EOF'
'use strict';

module.exports = {
  mongodb: {
    server: process.env.ME_CONFIG_MONGODB_SERVER || 'mongodb',
    port: parseInt(process.env.ME_CONFIG_MONGODB_PORT) || 27017,
    
    // Admin credentials
    admin: true,
    adminUsername: process.env.ME_CONFIG_MONGODB_ADMINUSERNAME || '',
    adminPassword: process.env.ME_CONFIG_MONGODB_ADMINPASSWORD || '',
    
    // Authentication database
    auth: [
      {
        database: process.env.ME_CONFIG_MONGODB_AUTH_DATABASE || 'admin',
        username: process.env.ME_CONFIG_MONGODB_ADMINUSERNAME || '',
        password: process.env.ME_CONFIG_MONGODB_ADMINPASSWORD || ''
      }
    ]
  },

  site: {
    baseUrl: '/',
    cookieKeyName: 'mongo-express',
    cookieSecret: process.env.ME_CONFIG_SITE_COOKIESECRET || 'cookiesecret',
    host: process.env.VCAP_APP_HOST || 'localhost',
    port: process.env.VCAP_APP_PORT || 8081,
    requestSizeLimit: process.env.ME_CONFIG_REQUEST_SIZE || '50mb',
    sessionSecret: process.env.ME_CONFIG_SITE_SESSIONSECRET || 'sessionsecret',
    sslEnabled: process.env.ME_CONFIG_SITE_SSL_ENABLED || false,
    sslCert: process.env.ME_CONFIG_SITE_SSL_CRT_PATH || '',
    sslKey: process.env.ME_CONFIG_SITE_SSL_KEY_PATH || ''
  },

  options: {
    console: true,
    //documentsPerPage: 10,
    //editorTheme: "ambiance",
    gridFSEnabled: process.env.ME_CONFIG_SITE_GRIDFS_ENABLED || false,
    maximumTimeout: 60000,
    noDelete: false,
    noExport: false,
    readOnly: false,
    //collapsibleJSON: true,
    //collapsibleJSONDefaultUnfold: 1,
    //validator: undefined,
  },

  // Set useUnifiedTopology: true to opt in to the MongoDB driver's replica set
  // and sharded cluster monitoring engine
  useUnifiedTopology: process.env.ME_CONFIG_MONGODB_ENABLE_ADMIN !== 'false'
    ? process.env.ME_CONFIG_MONGODB_CA_FILE || process.env.ME_CONFIG_MONGODB_SSLVALIDATE || true
    : true
};
EOF
    
    log_success "Mongo Express configuration created at ${config_dir}/"
}

generate_compose() {
    log_info "Generating Docker Compose configuration for MongoDB..."
    
    local compose_dir="${GENERATED_DIR}/compose"
    mkdir -p "$compose_dir"
    
    # Create volumes
    create_volume_entry "mongodb_data" "$GENERATED_DIR"
    create_volume_entry "mongodb_logs" "$GENERATED_DIR"
    
    # Generate MongoDB compose
    cat > "${compose_dir}/mongodb.yml" << 'EOF'

  # =============================================================================
  # MONGODB DATABASE (4020)
  # =============================================================================
  
  mongodb:
    image: mongo:7.0
    container_name: mongodb
    # No external ports exposed - internal access only
    expose:
      - "27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_INITDB_DATABASE}
      # Application database settings
      MONGO_APP_DB: ${MONGO_APP_DB}
      MONGO_APP_USER: ${MONGO_APP_USER}
      MONGO_APP_PASSWORD: ${MONGO_APP_PASSWORD}
    volumes:
      - mongodb_data:/data/db
      - mongodb_logs:/var/log/mongodb
      - ./config/mongodb/mongod.conf:/etc/mongod.conf:ro
      - ./config/mongodb/init-mongo.js:/docker-entrypoint-initdb.d/init-mongo.js:ro
      - ./config/mongodb/create-log-dir.sh:/docker-entrypoint-initdb.d/01-create-log-dir.sh:ro
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
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 3
    command: ["mongod", "--config", "/etc/mongod.conf"]

  # =============================================================================
  # MONGO EXPRESS WEB INTERFACE (4021) - ADMIN PROFILE ONLY
  # =============================================================================
  
  mongo-express:
    image: mongo-express:1.0.0-20-alpine3.18
    container_name: mongo-express
    profiles:
      - admin
    ports:
      - "4021:8081"
    environment:
      ME_CONFIG_MONGODB_SERVER: mongodb
      ME_CONFIG_MONGODB_PORT: 27017
      ME_CONFIG_MONGODB_ENABLE_ADMIN: 'true'
      ME_CONFIG_MONGODB_ADMINUSERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      ME_CONFIG_MONGODB_ADMINPASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
      ME_CONFIG_MONGODB_AUTH_DATABASE: admin
      ME_CONFIG_BASICAUTH_USERNAME: ${MONGO_EXPRESS_USER}
      ME_CONFIG_BASICAUTH_PASSWORD: ${MONGO_EXPRESS_PASSWORD}
      ME_CONFIG_SITE_COOKIESECRET: ${MONGO_EXPRESS_COOKIE_SECRET}
      ME_CONFIG_SITE_SESSIONSECRET: ${MONGO_EXPRESS_SESSION_SECRET}
    volumes:
      - ./config/mongo-express/config.js:/node_modules/mongo-express/config.js:ro
    networks:
      - database
      - frontend
    depends_on:
      - mongodb
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
      test: ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:8081 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    
    log_success "MongoDB compose generated at ${compose_dir}/mongodb.yml"
}

generate_env_template() {
    log_info "Adding MongoDB environment variables to template..."
    
    local env_template="${SCRIPT_DIR}/.env.example"
    
    # Add MongoDB variables if not already present
    if ! grep -q "MONGO_" "$env_template" 2>/dev/null; then
        cat >> "$env_template" << 'EOF'

# MongoDB Configuration
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=changeme_mongo_password
MONGO_INITDB_DATABASE=admin

# Application Database
MONGO_APP_DB=appdb
MONGO_APP_USER=appuser
MONGO_APP_PASSWORD=changeme_app_password

# Mongo Express Configuration
MONGO_EXPRESS_USER=admin
MONGO_EXPRESS_PASSWORD=changeme_express_password
MONGO_EXPRESS_COOKIE_SECRET=changeme_cookie_secret
MONGO_EXPRESS_SESSION_SECRET=changeme_session_secret
EOF
        log_success "MongoDB environment variables added to .env.example"
    fi
}

create_documentation() {
    log_info "Creating MongoDB documentation..."
    
    local docs_dir="${GENERATED_DIR}/docs"
    mkdir -p "$docs_dir"
    
    cat > "${docs_dir}/mongodb.md" << 'EOF'
# MongoDB Database Setup

## Overview

MongoDB document database with web-based administration interface.

## Services

### MongoDB Database
- **Internal Port**: 27017
- **Container**: mongodb
- **Networks**: database
- **Volumes**: mongodb_data, mongodb_logs

### Mongo Express (Admin Profile Only)
- **External Port**: 4021
- **Container**: mongo-express
- **Networks**: database, frontend
- **Authentication**: Basic auth enabled

## Configuration

### Environment Variables
- `MONGO_INITDB_ROOT_USERNAME`: Admin username
- `MONGO_INITDB_ROOT_PASSWORD`: Admin password
- `MONGO_INITDB_DATABASE`: Initial database
- `MONGO_APP_DB`: Application database name
- `MONGO_APP_USER`: Application user
- `MONGO_APP_PASSWORD`: Application user password
- `MONGO_EXPRESS_USER`: Web interface username
- `MONGO_EXPRESS_PASSWORD`: Web interface password

### Database Access

#### Internal Access (from other containers)
```javascript
// Connection string
mongodb://appuser:password@mongodb:27017/appdb

// Connection options
{
  host: 'mongodb',
  port: 27017,
  database: 'appdb',
  username: 'appuser',
  password: 'password'
}
```

#### Development Access (admin profile)
1. Start with admin profile:
   ```bash
   docker-compose --profile admin up -d
   ```
2. Access Mongo Express: http://localhost:4021
3. Login with `MONGO_EXPRESS_USER` and `MONGO_EXPRESS_PASSWORD`

#### Production Access
Use SSH tunneling:
```bash
ssh -L 4021:localhost:4021 user@server
```

## Database Initialization

The setup includes automatic user and database creation:
- Creates root admin user
- Creates application database (`MONGO_APP_DB`)
- Creates application user (`MONGO_APP_USER`)
- Sets up proper authentication

## Connection Examples

### Node.js (MongoDB Driver)
```javascript
const { MongoClient } = require('mongodb');

const client = new MongoClient('mongodb://appuser:password@mongodb:27017/appdb');
```

### Node.js (Mongoose)
```javascript
const mongoose = require('mongoose');

mongoose.connect('mongodb://appuser:password@mongodb:27017/appdb');
```

### Python (PyMongo)
```python
from pymongo import MongoClient

client = MongoClient('mongodb://appuser:password@mongodb:27017/appdb')
```

## Backup Recommendations

Regular backups using mongodump:
```bash
docker exec mongodb mongodump --username admin --password password --authenticationDatabase admin --out /backup
```

## Security Notes

- Database ports are not exposed externally
- Authentication enabled by default
- Admin interface only available with admin profile
- Basic authentication on web interface
- Separate application user with limited privileges

## Performance Tuning

The configuration includes:
- WiredTiger storage engine with optimized cache
- Operation profiling for slow queries
- Appropriate logging levels
- Journal enabled for durability
EOF
    
    log_success "MongoDB documentation created at ${docs_dir}/mongodb.md"
}

main() {
    log_info "Setting up MongoDB database..."
    
    # Setup configurations
    setup_mongodb_config
    setup_mongo_express_config
    
    # Generate compose file
    generate_compose
    
    # Update environment template
    generate_env_template
    
    # Create documentation
    create_documentation
    
    log_success "MongoDB setup completed successfully!"
    log_info "Remember to update database credentials in .env file"
    log_info "Use --profile admin to enable Mongo Express web interface"
}

# Run main function
main