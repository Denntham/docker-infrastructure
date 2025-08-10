# Infrastructure Deployment Setup Script (Portable Version)
# Usage: ./setup.sh [options] [components...]
# Example: ./setup.sh core postgresql mongodb
# Compatible with bash 3.2+ and older systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATED_DIR="${SCRIPT_DIR}/generated"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Options
FORCE_CLEAN=true  # Default to always clean for fresh generation
KEEP_BACKUPS=true

# Source utilities
source "${SCRIPTS_DIR}/utils.sh"

# Available components (using simple arrays instead of associative)
AVAILABLE_COMPONENTS="core postgresql mongodb redis rabbitmq prometheus grafana elk jaeger"

print_header() {
    echo -e "${BLUE}"
    echo "=================================="
    echo "Infrastructure Deployment Setup"
    echo "=================================="
    echo -e "${NC}"
}

get_component_description() {
    case "$1" in
        "core")         echo "HAProxy + Nginx" ;;
        "postgresql")   echo "PostgreSQL Database" ;;
        "mongodb")      echo "MongoDB Database" ;;
        "redis")        echo "Redis Cache" ;;
        "rabbitmq")     echo "RabbitMQ Message Queue" ;;
        "prometheus")   echo "Prometheus Monitoring" ;;
        "grafana")      echo "Grafana Dashboards" ;;
        "elk")          echo "ELK Stack (Elasticsearch, Logstash, Kibana)" ;;
        "jaeger")       echo "Jaeger Tracing" ;;
        *)              echo "Unknown component" ;;
    esac
}

get_component_dependency() {
    case "$1" in
        "grafana")      echo "prometheus" ;;
        "elk")          echo "elasticsearch" ;;
        *)              echo "" ;;
    esac
}

print_usage() {
    echo "Usage: $0 [options] [components...]"
    echo ""
    echo "Options:"
    echo "  --clean         Force clean generated directory (default)"
    echo "  --no-clean      Keep existing generated files (not recommended)"
    echo "  --keep-backups  Keep backup files (default)"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Available components:"
    for comp in $AVAILABLE_COMPONENTS; do
        echo "  ${comp}: $(get_component_description "$comp")"
    done
    echo ""
    echo "Examples:"
    echo "  $0 core postgresql mongodb"
    echo "  $0 --clean core postgresql mongodb redis"
    echo "  $0 --no-clean core  # Keep existing configs"
    echo ""
}

parse_options() {
    local components=""
    
    while [ $# -gt 0 ]; do
        case $1 in
            --clean)
                FORCE_CLEAN=true
                shift
                ;;
            --no-clean)
                FORCE_CLEAN=false
                shift
                ;;
            --keep-backups)
                KEEP_BACKUPS=true
                shift
                ;;
            --no-backups)
                KEEP_BACKUPS=false
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            --*)
                echo -e "${RED}Error: Unknown option $1${NC}"
                print_usage
                exit 1
                ;;
            *)
                components="$components $1"
                shift
                ;;
        esac
    done
    
    echo "$components"
}

validate_components() {
    local requested="$*"
    local invalid=""
    
    for comp in $requested; do
        local found=false
        for available in $AVAILABLE_COMPONENTS; do
            if [ "$comp" = "$available" ]; then
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            invalid="$invalid $comp"
        fi
    done
    
    if [ -n "$invalid" ]; then
        echo -e "${RED}Error: Invalid components:${invalid}${NC}"
        echo ""
        print_usage
        exit 1
    fi
}

resolve_dependencies() {
    local requested="$*"
    local resolved="$requested"
    local added=""
    
    # Add dependencies
    for comp in $requested; do
        local dep=$(get_component_dependency "$comp")
        if [ -n "$dep" ]; then
            # Check if dependency is already in the list
            local found=false
            for existing in $resolved; do
                if [ "$existing" = "$dep" ]; then
                    found=true
                    break
                fi
            done
            
            if [ "$found" = false ]; then
                added="$added $dep"
                echo -e "${YELLOW}Adding dependency: ${dep} (required by ${comp})${NC}"
            fi
        fi
    done
    
    # Combine requested and dependencies
    echo "$resolved $added"
}

clean_generated_directory() {
    if [ -d "${GENERATED_DIR}" ]; then
        echo -e "${YELLOW}Found existing generated directory.${NC}"
        echo -e "${YELLOW}Cleaning generated directory to ensure fresh configuration...${NC}"
        
        # Backup docker-compose.yml if it exists
        if [ -f "${GENERATED_DIR}/docker-compose.yml" ]; then
            cp "${GENERATED_DIR}/docker-compose.yml" "${GENERATED_DIR}/docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            echo -e "${BLUE}Backed up existing docker-compose.yml${NC}"
        fi
        
        # Remove generated content but preserve backups
        rm -rf "${GENERATED_DIR}"/{config,compose,volumes,static,docs}
        rm -f "${GENERATED_DIR}/docker-compose.yml"
        
        echo -e "${GREEN}Generated directory cleaned successfully.${NC}"
    fi
}

setup_directories() {
    echo -e "${BLUE}Setting up directories...${NC}"
    
    # Clean existing generated content
    clean_generated_directory
    
    # Create fresh directory structure
    mkdir -p "${GENERATED_DIR}"/{config,compose,volumes,static,docs}
    mkdir -p "${SCRIPT_DIR}/backups"
    
    # Create .env file if it doesn't exist
    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
        cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
        echo -e "${YELLOW}Created .env file from template. Please review and update credentials.${NC}"
    fi
}

run_component_setup() {
    local component=$1
    local setup_script="${SCRIPTS_DIR}/${component}-setup.sh"
    
    if [ -f "$setup_script" ]; then
        echo -e "${GREEN}Setting up ${component}...${NC}"
        bash "$setup_script" "$GENERATED_DIR"
    else
        echo -e "${YELLOW}Warning: Setup script not found for ${component}${NC}"
    fi
}

generate_base_compose() {
    cat > "${GENERATED_DIR}/docker-compose.yml" << 'EOF'
# Generated by Infrastructure Deployment Setup
# Do not edit this file directly - it will be overwritten

services:
EOF
}

generate_networks() {
    cat >> "${GENERATED_DIR}/docker-compose.yml" << 'EOF'

# =============================================================================
# NETWORKS
# =============================================================================

networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
  
  backend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.21.0.0/24
  
  database:
    driver: bridge
    ipam:
      config:
        - subnet: 172.22.0.0/24
  
  monitoring:
    driver: bridge
    ipam:
      config:
        - subnet: 172.23.0.0/24

EOF
}

generate_volumes() {
    cat >> "${GENERATED_DIR}/docker-compose.yml" << 'EOF'
# =============================================================================
# VOLUMES
# =============================================================================

volumes:
EOF
}

combine_compose_files() {
    local components="$*"
    
    # Add component-specific compose fragments
    for comp in $components; do
        local compose_fragment="${GENERATED_DIR}/compose/${comp}.yml"
        if [ -f "$compose_fragment" ]; then
            echo "  # ${comp} services" >> "${GENERATED_DIR}/docker-compose.yml"
            tail -n +2 "$compose_fragment" >> "${GENERATED_DIR}/docker-compose.yml"
            echo "" >> "${GENERATED_DIR}/docker-compose.yml"
        fi
    done
}

finalize_compose() {
    # Add networks and volumes sections
    generate_networks
    generate_volumes
    
    # Add volumes from component files
    for volume_file in "${GENERATED_DIR}/volumes"/*.yml; do
        if [ -f "$volume_file" ]; then
            cat "$volume_file" >> "${GENERATED_DIR}/docker-compose.yml"
        fi
    done
}

print_summary() {
    local components="$*"
    
    echo -e "${GREEN}"
    echo "=================================="
    echo "Setup Complete!"
    echo "=================================="
    echo -e "${NC}"
    
    echo "Generated components:"
    for comp in $components; do
        echo "  ✓ ${comp}: $(get_component_description "$comp")"
    done

    echo "Copying .env file:"
    cp .env generated/.env
    
    echo ""
    echo "Next steps:"
    echo "1. Review and update credentials in .env file"
    echo "2. Review generated configuration in generated/ directory"
    echo "3. Start services:"
    echo "   cd ${SCRIPT_DIR}"
    echo "   docker-compose -f generated/docker-compose.yml up -d"
    echo ""
    echo "4. For database administration (development):"
    echo "   docker-compose -f generated/docker-compose.yml --profile admin up -d"
    echo ""
    echo "5. Check service status:"
    echo "   docker-compose -f generated/docker-compose.yml ps"
    echo ""
}

main() {
    print_header
    
    # Parse command line options and get components
    components=$(parse_options "$@")
    
    # Check if we have any components
    if [ -z "$components" ]; then
        echo -e "${RED}Error: No components specified${NC}"
        echo ""
        print_usage
        exit 1
    fi
    
    # Show what we're doing
    if [ "$FORCE_CLEAN" = true ]; then
        echo -e "${BLUE}Mode: Clean generation (fresh configuration)${NC}"
    else
        echo -e "${YELLOW}Mode: Incremental generation (keeping existing files)${NC}"
    fi
    
    # Validate components
    validate_components $components
    
    # Resolve dependencies
    resolved_components=$(resolve_dependencies $components)
    
    echo "Components to setup: $resolved_components"
    echo ""
    
    # Setup
    setup_directories
    generate_base_compose
    
    # Run component setup scripts
    for comp in $resolved_components; do
        run_component_setup "$comp"
    done
    
    # Combine all compose files
    combine_compose_files $resolved_components
    finalize_compose
    
    # Print summary
    print_summary $resolved_components
}

# Run main function with all arguments
main "$@"