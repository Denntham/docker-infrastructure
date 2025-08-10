# Utility functions for infrastructure setup
# Compatible with bash 3.2+

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Generate random password
generate_password() {
    local length=${1:-16}
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
}

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create config directory if it doesn't exist
ensure_config_dir() {
    local service=$1
    local generated_dir=$2
    local config_dir="${generated_dir}/config/${service}"
    
    mkdir -p "$config_dir"
    echo "$config_dir"
}

# Create volume entry
create_volume_entry() {
    local volume_name=$1
    local generated_dir=$2
    local volumes_dir="${generated_dir}/volumes"
    
    mkdir -p "$volumes_dir"
    
    cat >> "${volumes_dir}/${volume_name}.yml" << EOF
  ${volume_name}:
    driver: local
EOF
    
    log_info "Created volume: ${volume_name}"
}

# Generate basic service template with common settings
generate_service_template() {
    local service_name=$1
    local image=$2
    local ports=$3
    local networks=$4
    local volumes=$5
    local environment=$6
    local depends_on=$7
    local healthcheck=$8
    local resources=$9
    local restart_policy=${10:-unless-stopped}
    
    cat << EOF
  ${service_name}:
    image: ${image}
    container_name: ${service_name}
EOF

    # Add ports if provided
    if [[ -n "$ports" ]]; then
        echo "    ports:"
        echo "$ports" | sed 's/^/      - /'
    fi
    
    # Add networks if provided
    if [[ -n "$networks" ]]; then
        echo "    networks:"
        echo "$networks" | sed 's/^/      - /'
    fi
    
    # Add volumes if provided
    if [[ -n "$volumes" ]]; then
        echo "    volumes:"
        echo "$volumes" | sed 's/^/      - /'
    fi
    
    # Add environment if provided
    if [[ -n "$environment" ]]; then
        echo "    environment:"
        echo "$environment" | sed 's/^/      /'
    fi
    
    # Add depends_on if provided
    if [[ -n "$depends_on" ]]; then
        echo "    depends_on:"
        echo "$depends_on" | sed 's/^/      - /'
    fi
    
    # Add healthcheck if provided
    if [[ -n "$healthcheck" ]]; then
        echo "    healthcheck:"
        echo "$healthcheck" | sed 's/^/      /'
    fi
    
    # Add resource limits if provided
    if [[ -n "$resources" ]]; then
        echo "    deploy:"
        echo "      resources:"
        echo "$resources" | sed 's/^/        /'
    fi
    
    # Add restart policy
    echo "    restart: ${restart_policy}"
    echo ""
}

# Generate standard resource limits
get_resource_limits() {
    local memory_limit=$1
    local cpu_limit=$2
    local memory_reservation=${3:-$(echo "$memory_limit" | sed 's/[0-9]*[MG]$//'| awk '{print int($1/2)}')}
    local cpu_reservation=${4:-$(echo "$cpu_limit" | awk '{print $1/2}')}
    
    cat << EOF
limits:
  memory: ${memory_limit}
  cpus: '${cpu_limit}'
reservations:
  memory: ${memory_reservation}
  cpus: '${cpu_reservation}'
EOF
}

# Generate standard healthcheck
get_healthcheck() {
    local test_command=$1
    local interval=${2:-30s}
    local timeout=${3:-10s}
    local retries=${4:-3}
    
    cat << EOF
test: ${test_command}
interval: ${interval}
timeout: ${timeout}
retries: ${retries}
EOF
}

# Validate required environment variable
check_env_var() {
    local var_name=$1
    local default_value=$2
    
    if [[ -z "${!var_name}" ]]; then
        if [[ -n "$default_value" ]]; then
            log_warning "Environment variable ${var_name} not set, using default: ${default_value}"
            export "$var_name"="$default_value"
        else
            log_error "Required environment variable ${var_name} is not set"
            return 1
        fi
    fi
    return 0
}

# Create network configuration
create_network_config() {
    local network_name=$1
    local subnet=$2
    
    cat << EOF
  ${network_name}:
    driver: bridge
    ipam:
      config:
        - subnet: ${subnet}
EOF
}

# Load environment variables from .env file
load_env_file() {
    local env_file="${1:-$(dirname "$0")/.env}"
    
    if [[ -f "$env_file" ]]; then
        # Export variables from .env file
        set -a
        source "$env_file"
        set +a
        log_info "Loaded environment from ${env_file}"
    else
        log_warning "Environment file ${env_file} not found"
    fi
}

# Check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        return 1
    fi
    return 0
}

# Check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "docker-compose is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Backup existing configuration
backup_existing_config() {
    local config_file=$1
    
    if [[ -f "$config_file" ]]; then
        local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup_file"
        log_info "Backed up existing config to ${backup_file}"
    fi
}