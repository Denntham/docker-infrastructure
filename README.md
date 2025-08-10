# Infrastructure Deployment

A modular, production-ready infrastructure deployment system using Docker Compose. Deploy and manage core services, databases, monitoring, and more with a simple command-line interface.

## 🚀 Quick Start

```bash
# Make scripts executable
chmod +x setup.sh scripts/*.sh

# Deploy core infrastructure with PostgreSQL and MongoDB
./setup.sh core postgresql mongodb

# Review and update credentials
cp .env.example .env
nano .env  # Update passwords - REQUIRED before starting services

# Start services
docker-compose -f generated/docker-compose.yml up -d

# Start with database admin interfaces
docker-compose -f generated/docker-compose.yml --profile admin up -d
```

## 📋 Table of Contents

-   [Overview](#overview)
-   [Components](#components)
-   [Port Allocation](#port-allocation)
-   [Usage](#usage)
-   [Security](#security)
-   [Administration](#administration)
-   [Configuration](#configuration)
-   [Troubleshooting](#troubleshooting)
-   [Contributing](#contributing)

## 🎯 Overview

This project provides a modular approach to deploying infrastructure services with the following principles:

-   **Security First**: Databases are internal-only, admin interfaces require profiles
-   **Production Ready**: Resource limits, health checks, restart policies
-   **Modular Design**: Deploy only what you need
-   **Network Segmentation**: Proper network isolation between service tiers
-   **Easy Administration**: Web-based interfaces for database management

#### Operational Features

-   **Health Checks**: All services include health monitoring
-   **Resource Limits**: Memory and CPU limits prevent resource exhaustion
-   **Restart Policies**: Automatic service recovery
-   **Volume Management**: Persistent data storage
-   **Log Management**: Centralized logging configuration

#### Security Features

-   Database ports not exposed to host system
-   Web-based admin interfaces behind authentication
-   Admin interfaces only available with `--profile admin`
-   Network segmentation between service tiers
-   Secure configuration templates with authentication enabled

## 🧩 Components

### Available Components

| Component      | Description             | Ports                         | Status       |
| -------------- | ----------------------- | ----------------------------- | ------------ |
| **core**       | HAProxy + Nginx         | 1000-1001, 1100-1101          | ✅ Available |
| **postgresql** | PostgreSQL + pgAdmin    | 4010 (internal), 4011 (admin) | ✅ Available |
| **mongodb**    | MongoDB + Mongo Express | 4020 (internal), 4021 (admin) | ✅ Available |

### Network Architecture

```
┌─────────────┐    ┌─────────────┐
│   HAProxy   │────│    Nginx    │
│ (1000,1001) │    │ (1100,1101) │
│  frontend   │    │  frontend   │
│  backend    │    │             │
└─────────────┘    └─────────────┘
       │
   ┌───▼────┐    ┌──────────┐
   │PostgreSQL│  │ MongoDB  │
   │   4010   │  │   4020   │
   │ database │  │ database │
   └──────────┘  └──────────┘
       │              │
   ┌───▼────┐    ┌────▼─────┐
   │ pgAdmin│    │  Mongo   │
   │  4011  │    │ Express  │
   │ (admin)│    │   4021   │
   └────────┘    │ (admin)  │
                 └──────────┘
```

## 🔢 Port Allocation

Our systematic port allocation strategy:

### Core Infrastructure (1000-1999)

-   **1000**: HAProxy (main)
-   **1001**: HAProxy stats
-   **1100**: Nginx (main)
-   **1101**: Nginx SSL

### Databases (4000-4999)

-   **4000**: Redis (internal)
-   **4010**: PostgreSQL (internal)
-   **4011**: pgAdmin (admin profile)
-   **4020**: MongoDB (internal)
-   **4021**: Mongo Express (admin profile)

## 🔧 Usage

### Basic Commands

```bash
# Deploy specific components
./setup.sh core                           # HAProxy + Nginx only
./setup.sh core postgresql                # Core + PostgreSQL
./setup.sh core postgresql mongodb        # Core + Both databases

# Start services
docker-compose -f generated/docker-compose.yml up -d

# Start with admin interfaces
docker-compose -f generated/docker-compose.yml --profile admin up -d

# Check service status
docker-compose -f generated/docker-compose.yml ps

# View logs
docker-compose -f generated/docker-compose.yml logs [service_name]

# Stop services
docker-compose -f generated/docker-compose.yml down

# Stop and remove volumes (⚠️ DATA LOSS)
docker-compose -f generated/docker-compose.yml down -v
```

### Service Management

```bash
# Restart specific service
docker-compose -f generated/docker-compose.yml restart postgresql

# Scale services (if supported)
docker-compose -f generated/docker-compose.yml up -d --scale nginx=2

# Update service
docker-compose -f generated/docker-compose.yml pull postgresql
docker-compose -f generated/docker-compose.yml up -d postgresql
```

## 🔒 Security

### Database Security

-   **No External Exposure**: Database ports are not exposed to the host
-   **Internal Networks**: Databases communicate via Docker networks only
-   **Admin Profiles**: Management interfaces require `--profile admin`
-   **Authentication**: All services require authentication

### Access Methods

#### Development Environment

```bash
# Enable admin interfaces
docker-compose --profile admin up -d

# Access web interfaces
# PostgreSQL: http://localhost:4011
# MongoDB: http://localhost:4021
```

#### Production Environment

```bash
# SSH tunneling for secure access
ssh -L 4011:localhost:4011 user@production-server
ssh -L 4021:localhost:4021 user@production-server

# Then access locally
# http://localhost:4011 (pgAdmin)
# http://localhost:4021 (Mongo Express)
```

### Network Segmentation

-   **Frontend Network**: Public-facing services (HAProxy, Nginx)
-   **Backend Network**: Application services
-   **Database Network**: Database servers only
-   **Monitoring Network**: Monitoring and logging services

## 👨‍💼 Administration

### Database Administration

#### PostgreSQL (pgAdmin)

1. Start with admin profile: `docker-compose --profile admin up -d`
2. Access: http://localhost:4011
3. Login: Use `PGADMIN_EMAIL` and `PGADMIN_PASSWORD` from `.env`
4. Server is pre-configured as "PostgreSQL Server"

#### MongoDB (Mongo Express)

1. Start with admin profile: `docker-compose --profile admin up -d`
2. Access: http://localhost:4021
3. Login: Use `MONGO_EXPRESS_USER` and `MONGO_EXPRESS_PASSWORD` from `.env`
4. All databases are accessible through the interface

### Service Monitoring

#### HAProxy Stats

-   URL: http://localhost:1001/stats
-   No authentication required (configure in production)

#### Health Checks

```bash
# Check all service health
docker-compose -f generated/docker-compose.yml ps

# View health check logs
docker inspect --format='{{json .State.Health}}' postgresql
```

## ⚙️ Configuration

### Environment Variables

Copy `.env.example` to `.env` and update:

```bash
cp .env.example .env
```

**Critical Variables to Update (REQUIRED):**

-   `POSTGRES_PASSWORD`
-   `MONGO_INITDB_ROOT_PASSWORD`
-   `PGADMIN_PASSWORD`
-   `MONGO_EXPRESS_PASSWORD`
-   `APP_PASSWORD`
-   `MONGO_APP_PASSWORD`

**Note**: All services will fail to start with secure authentication if these passwords are not updated from the template values.

### Resource Limits

Default resource allocations:

| Service       | Memory Limit | CPU Limit | Memory Reservation | CPU Reservation |
| ------------- | ------------ | --------- | ------------------ | --------------- |
| HAProxy       | 128M         | 0.2       | 64M                | 0.1             |
| Nginx         | 256M         | 0.3       | 128M               | 0.15            |
| PostgreSQL    | 512M         | 0.5       | 256M               | 0.25            |
| MongoDB       | 512M         | 0.5       | 256M               | 0.25            |
| pgAdmin       | 256M         | 0.3       | 128M               | 0.15            |
| Mongo Express | 128M         | 0.2       | 64M                | 0.1             |

### Custom Configuration

Generated configurations are stored in `generated/config/[service]/`. You can modify these files and restart services:

```bash
# Edit configuration
nano generated/config/postgresql/postgresql.conf

# Restart service to apply changes
docker-compose -f generated/docker-compose.yml restart postgresql
```

## 🐛 Troubleshooting

### Common Issues

#### Port Already in Use

```bash
# Check what's using the port
sudo lsof -i :4011

# Kill the process or choose different ports in setup
```

#### Service Won't Start

```bash
# Check logs
docker-compose -f generated/docker-compose.yml logs postgresql

# Check service status
docker-compose -f generated/docker-compose.yml ps
```

#### Database Connection Issues

```bash
# Verify network connectivity
docker exec -it nginx ping postgresql
docker exec -it nginx ping mongodb

# Check database logs
docker-compose -f generated/docker-compose.yml logs postgresql
docker-compose -f generated/docker-compose.yml logs mongodb
```

#### Permission Issues

```bash
# Fix file permissions
sudo chown -R $USER:$USER generated/
sudo chmod -R 755 generated/
```

### Debugging Commands

```bash
# Enter service container
docker exec -it postgresql bash
docker exec -it mongodb bash

# Check service configuration
docker exec -it postgresql cat /etc/postgresql/postgresql.conf
docker exec -it mongodb cat /etc/mongod.conf

# Test database connectivity
docker exec -it postgresql psql -U admin -d appdb
docker exec -it mongodb mongosh --username admin --password
```

## 📁 Project Structure

```
infrastructure-deployment/
├── README.md                   # This file
├── CHANGELOG.md                # Version history
├── setup.sh                    # Main setup script
├── .env.example                # Environment template
├── scripts/                    # Setup scripts
│   ├── utils.sh                # Shared utilities
│   ├── core-setup.sh           # HAProxy + Nginx
│   ├── postgresql-setup.sh     # PostgreSQL + pgAdmin
│   └── mongodb-setup.sh        # MongoDB + Mongo Express
└── generated/                  # Generated files (created by setup)
    ├── docker-compose.yml      # Main compose file
    ├── config/                 # Service configurations
    ├── compose/                # Compose fragments
    ├── volumes/                # Volume definitions
    ├── static/                 # Static web content
    └── docs/                   # Documentation
```

## 📄 License

[MIT License](LICENSE) - see LICENSE file for details.

---

**⚠️ Security Note**: Always change default passwords in `.env` before deploying to production. Never commit `.env` files to version control.
