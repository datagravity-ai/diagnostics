#!/bin/bash
# Usage example: chmod +x generate-diag.sh 
# Kubernetes: ./generate-diag.sh -t kubernetes -n anomalo -d anomalo.your-domain.com
# Docker: ./generate-diag.sh -t docker -d anomalo.your-domain.com

# Enable strict error handling
set -euo pipefail

# Global variables
output_dir=""
type="kubernetes"
namespace="anomalo"
base_domain=""

# Error handling and utility functions
log_error() {
    echo "ERROR: $1" >&2
}

log_warning() {
    echo "WARNING: $1" >&2
}

log_info() {
    echo "INFO: $1"
}

log_success() {
    echo "✓ $1"
}

log_failure() {
    echo "✗ $1"
}

# Safe execution wrapper for critical commands
safe_execute() {
    local cmd="$1"
    local output_file="$2"
    local description="${3:-$(basename "$output_file")}"
    
    if eval "$cmd" > "$output_file" 2>&1; then
        log_success "$description"
        return 0
    else
        log_failure "$description"
        return 1
    fi
}

# Validate required tools are installed
validate_required_tools() {
    local missing_tools=()
    
    # Check for common tools
    local tools=("curl" "zip")
    
    if [[ "$type" == "kubernetes" ]]; then
        tools+=("kubectl")
    elif [[ "$type" == "docker" ]]; then
        tools+=("docker")
    fi
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again."
        exit 1
    fi
}

# Clean and normalize domain input
normalize_domain() {
    local domain="$1"
    
    # Remove protocol if present
    domain="${domain#http://}"
    domain="${domain#https://}"
    
    # Remove trailing slash if present
    domain="${domain%/}"
    
    # Remove www. prefix if present (optional, but cleaner)
    domain="${domain#www.}"
    
    echo "$domain"
}

# Validate input parameters
validate_inputs() {
    # Validate deployment type
    if [[ "$type" != "kubernetes" && "$type" != "docker" ]]; then
        log_error "Invalid deployment type: $type. Must be 'kubernetes' or 'docker'."
        exit 1
    fi
    
    # Validate namespace (for Kubernetes)
    if [[ "$type" == "kubernetes" ]]; then
        if [[ -z "$namespace" ]]; then
            log_error "Namespace is required for Kubernetes deployments."
            exit 1
        fi
        # Basic namespace validation (alphanumeric and hyphens only)
        if [[ ! "$namespace" =~ ^[a-zA-Z0-9-]+$ ]]; then
            log_error "Invalid namespace format: $namespace. Must contain only alphanumeric characters and hyphens."
            exit 1
        fi
    fi
    
    # Validate domain
    if [[ -z "$base_domain" ]]; then
        log_error "Base domain is required."
        exit 1
    fi
    
    # Normalize the domain (remove protocol, trailing slash, etc.)
    base_domain=$(normalize_domain "$base_domain")
    
    # Basic domain validation after normalization
    if [[ ! "$base_domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $base_domain. Must be a valid domain name."
        log_error "Examples: anomalo.your-domain.com, my-anomalo.company.com"
        exit 1
    fi
    
    log_info "Using normalized domain: $base_domain"
}

# Cleanup function for error handling
cleanup() {
    if [[ -n "${output_dir:-}" && -d "$output_dir" ]]; then
        log_info "Cleaning up temporary directory: $output_dir"
        rm -rf "$output_dir"
    fi
}

# Set up error handling
trap cleanup EXIT

# Begin Kubernetes Content
check_kubectl_connection() {
    local namespace=$1
    
    log_info "Checking kubectl connection and namespace access..."
    
    # Check if kubectl can connect to the Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to the Kubernetes cluster. Please check your configuration."
        log_error "Make sure kubectl is configured and you have access to the cluster."
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log_error "Namespace '$namespace' does not exist or you don't have access to it."
        log_error "Available namespaces:"
        kubectl get namespaces --no-headers -o custom-columns=":metadata.name" 2>/dev/null || log_warning "Could not list namespaces"
        exit 1
    fi
    
    log_success "kubectl connection and namespace access verified"
}

gather_k8s_info() {
    local namespace=$1
    local output_dir=$2

    log_info "Gathering Kubernetes diagnostic information for namespace: $namespace"

    # Get all resources in the specified namespace
    safe_execute "kubectl get all -n '$namespace' -o wide" "$output_dir/all_resources_${namespace}.txt" "All resources in $namespace namespace"

    # Get events for the namespace
    safe_execute "kubectl get events -n '$namespace' --sort-by='.lastTimestamp'" "$output_dir/events_${namespace}.txt" "Events in $namespace namespace"

    # Get node information
    safe_execute "kubectl get nodes -o wide" "$output_dir/nodes.txt" "Cluster nodes information"

    # Get node metrics if available
    kubectl top nodes > "$output_dir/node_metrics.txt" 2>/dev/null || log_warning "Node metrics not available (metrics-server may not be installed)"

    # Check the status of each pod and fetch logs or describe
    log_info "Gathering pod information and logs..."
    local pods
    if pods=$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); then
        while IFS= read -r pod; do
            if [[ -n "$pod" ]]; then
                local status
                if status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null); then
                    if [[ "$status" != "Running" ]]; then
                        # Describe pod if not in Running state
                        safe_execute "kubectl describe pod '$pod' -n '$namespace'" "$output_dir/describe_${pod}.txt" "Pod description for $pod"
                    else
                        # Get the last 250 lines of logs for running pods
                        safe_execute "kubectl logs '$pod' -n '$namespace' --all-containers=true --tail=250" "$output_dir/logs_${pod}_last250.txt" "Logs for pod $pod"
                    fi
                else
                    log_warning "Could not get status for pod: $pod"
                fi
            fi
        done <<< "$pods"
    else
        log_warning "Could not list pods in namespace: $namespace"
    fi

    # Get deployment configurations in the specified namespace
    safe_execute "kubectl get deployments -n '$namespace' -o yaml" "$output_dir/deployments_config_${namespace}.yaml" "Deployment configurations"

    # Get services
    safe_execute "kubectl get services -n '$namespace' -o wide" "$output_dir/services_${namespace}.txt" "Services in $namespace namespace"

    # Get ingress
    safe_execute "kubectl get ingress -n '$namespace' -o wide" "$output_dir/ingress_${namespace}.txt" "Ingress in $namespace namespace"

    # Get persistent volumes and claims
    safe_execute "kubectl get pv,pvc -n '$namespace'" "$output_dir/storage_${namespace}.txt" "Storage resources in $namespace namespace"

    # List ConfigMaps names, each on a new line, in the specified namespace
    safe_execute "kubectl get configmaps -n '$namespace' -o jsonpath=\"{range .items[*]}{.metadata.name}{'\n'}{end}\"" "$output_dir/configmaps_${namespace}.txt" "ConfigMap names in $namespace namespace"
    
    # Get the values from specific ConfigMaps if they exist
    log_info "Gathering ConfigMap values..."
    for configmap in "anomalo-env" "nginx-conf"; do
        if kubectl get configmap "$configmap" -n "$namespace" &> /dev/null; then
            safe_execute "kubectl get configmap '$configmap' -n '$namespace' -o yaml" "$output_dir/${configmap}_configmap.yaml" "ConfigMap $configmap"
        else
            log_warning "ConfigMap '$configmap' not found in namespace '$namespace'"
        fi
    done
    
    # List Secret names, each on a new line, in the specified namespace
    safe_execute "kubectl get secrets -n '$namespace' -o jsonpath=\"{range .items[*]}{.metadata.name}{'\n'}{end}\"" "$output_dir/secrets_${namespace}.txt" "Secret names in $namespace namespace"

    # Get the values from specific Secrets if they exist (for debugging purposes)
    log_info "Gathering Secret values for debugging..."
    for secret in "anomalo-env-secrets"; do
        if kubectl get secret "$secret" -n "$namespace" &> /dev/null; then
            log_warning "Collecting values from Secret '$secret' (contains sensitive data)"
            safe_execute "kubectl get secret '$secret' -n '$namespace' -o yaml" "$output_dir/${secret}_secret.yaml" "Secret $secret values"
        else
            log_info "Secret '$secret' not found in namespace '$namespace'"
        fi
    done

    log_success "Kubernetes diagnostic information gathered successfully"
}

# End Kubernetes Content

# Begin Docker Content
check_docker_connection() {
    log_info "Checking Docker connection..."
    
    # Check if docker can connect to the Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Cannot connect to the Docker daemon. Please check your configuration."
        log_error "Make sure Docker is running and you have permission to access it."
        exit 1
    fi
    
    log_success "Docker connection verified"
}

gather_host_info() {
    local output_dir=$1
    
    log_info "Gathering host system information..."

    # Get the host's OS and kernel version
    safe_execute "uname -a" "$output_dir/host_os_kernel.txt" "Host OS and kernel version"

    # Get the host's CPU and memory info (Linux-specific commands)
    if command -v lscpu &> /dev/null; then
        safe_execute "lscpu" "$output_dir/host_cpu_info.txt" "Host CPU information"
    else
        log_warning "lscpu not available, trying alternative..."
        safe_execute "sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'CPU info not available'" "$output_dir/host_cpu_info.txt" "Host CPU information (alternative)"
    fi

    if command -v free &> /dev/null; then
        safe_execute "free -h" "$output_dir/host_memory_info.txt" "Host memory information"
    else
        log_warning "free command not available, trying alternative..."
        safe_execute "vm_stat 2>/dev/null || echo 'Memory info not available'" "$output_dir/host_memory_info.txt" "Host memory information (alternative)"
    fi

    # Get the host's disk usage
    safe_execute "df -h" "$output_dir/host_disk_usage.txt" "Host disk usage"

    # Get the host's network interfaces and routing table
    if command -v ip &> /dev/null; then
        safe_execute "ip a" "$output_dir/host_network_interfaces.txt" "Host network interfaces"
        safe_execute "ip route" "$output_dir/host_routing_table.txt" "Host routing table"
    else
        log_warning "ip command not available, trying alternative..."
        safe_execute "ifconfig 2>/dev/null || echo 'Network info not available'" "$output_dir/host_network_interfaces.txt" "Host network interfaces (alternative)"
        safe_execute "netstat -rn 2>/dev/null || echo 'Routing info not available'" "$output_dir/host_routing_table.txt" "Host routing table (alternative)"
    fi

    log_success "Host system information gathered"
}

gather_docker_info() {
    local output_dir=$1
    
    log_info "Gathering Docker diagnostic information..."
    
    gather_host_info "$output_dir"
    check_docker_connection
    
    # Get the list of running containers
    safe_execute "docker ps" "$output_dir/running_containers.txt" "Running containers"

    # Get the list of all containers
    safe_execute "docker ps -a" "$output_dir/all_containers.txt" "All containers"

    # Get the list of all images
    safe_execute "docker images" "$output_dir/all_images.txt" "All images"

    # Get the list of all volumes
    safe_execute "docker volume ls" "$output_dir/all_volumes.txt" "All volumes"

    # Get the list of all networks
    safe_execute "docker network ls" "$output_dir/all_networks.txt" "All networks"

    # Get Docker system information
    safe_execute "docker system df" "$output_dir/docker_system_df.txt" "Docker system disk usage"
    safe_execute "docker version" "$output_dir/docker_version.txt" "Docker version information"

    # Get the list of all logs
    log_info "Gathering container logs..."
    local containers
    if containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null); then
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                # Get container logs
                if docker logs -n 250 "$name" >"${output_dir}/logs_${name}_stdout.txt" 2>"${output_dir}/logs_${name}_stderr.txt" 2>/dev/null; then
                    log_success "Logs for container $name"
                else
                    log_warning "Could not get logs for container: $name"
                fi
            fi
        done <<< "$containers"
    else
        log_warning "Could not list containers"
    fi

    # Get the list of all inspect
    log_info "Gathering container inspection data..."
    if containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null); then
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                if docker inspect "$name" > "$output_dir/inspect_${name}.txt" 2>/dev/null; then
                    log_success "Inspection data for container $name"
                else
                    log_warning "Could not inspect container: $name"
                fi
            fi
        done <<< "$containers"
    fi

    # Remove any empty files
    find "$output_dir" -type f -empty -delete 2>/dev/null || true

    log_success "Docker diagnostic information gathered successfully"
}
# End Docker Content

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t, --type <type>            Specify the type of deployment. kubernetes/docker (default: kubernetes)"
    echo "  -n, --namespace <namespace>  Specify the namespace to gather information from (default: anomalo)"
    echo "  -d, --domain <base_domain>   Specify the base domain URL for your anomalo instance."
    echo "                               Examples: anomalo.your-domain.com, https://anomalo.company.com"
    echo "  -h, --help                   Show this help message and exit"
    echo ""
    echo "Note: The domain parameter accepts various formats:"
    echo "  - anomalo.your-domain.com"
    echo "  - https://anomalo.your-domain.com"
    echo "  - http://anomalo.your-domain.com"
    echo "  - www.anomalo.your-domain.com"
    echo "  The script will automatically normalize the domain format."
    echo ""
}

main() {
    # Validate inputs first
    validate_inputs
    
    # Validate required tools
    validate_required_tools

    # Construct the full URL for health check
    local health_check_url="https://${base_domain}/health_check?metrics=1"

    # Directory to store output files
    output_dir="anomalo_diag_$(date +%Y%m%d_%H%M%S)"
    
    log_info "Creating output directory: $output_dir"
    if ! mkdir -p "$output_dir"; then
        log_error "Failed to create output directory: $output_dir"
        exit 1
    fi

    # Gather diagnostic information based on deployment type
    if [[ "$type" == "docker" ]]; then
        log_info "Starting Docker diagnostic collection..."
        gather_docker_info "$output_dir"
    elif [[ "$type" == "kubernetes" ]]; then
        log_info "Starting Kubernetes diagnostic collection..."
        check_kubectl_connection "$namespace"
        gather_k8s_info "$namespace" "$output_dir"
    fi

    # Fetch metrics from the specified URL
    log_info "Fetching health check metrics..."
    if curl -s --connect-timeout 30 --max-time 60 "$health_check_url" -o "$output_dir/metrics.json"; then
        log_success "Metrics data fetched successfully from $health_check_url"
    else
        log_warning "Failed to fetch metrics data from $health_check_url (continuing anyway)"
        echo "{}" > "$output_dir/metrics.json"  # Create empty JSON file
    fi

    # Create summary file
    log_info "Creating diagnostic summary..."
    cat > "$output_dir/diagnostic_summary.txt" << EOF
Anomalo Diagnostic Collection Summary
=====================================
Collection Date: $(date)
Deployment Type: $type
Base Domain: $base_domain
EOF

    if [[ "$type" == "kubernetes" ]]; then
        echo "Namespace: $namespace" >> "$output_dir/diagnostic_summary.txt"
    fi

    echo "Output Directory: $output_dir" >> "$output_dir/diagnostic_summary.txt"
    echo "Files Collected:" >> "$output_dir/diagnostic_summary.txt"
    find "$output_dir" -type f -name "*.txt" -o -name "*.yaml" -o -name "*.json" | sort >> "$output_dir/diagnostic_summary.txt"

    # Compress the output directory
    log_info "Compressing diagnostic data..."
    if zip -rq "${output_dir}.zip" "$output_dir"; then
        log_success "Output directory compressed into ${output_dir}.zip"
    else
        log_error "Failed to compress output directory"
        exit 1
    fi

    # Display final instructions
    echo ""
    echo "================================================================"
    echo "✓ Diagnostic collection completed successfully!"
    echo "✓ Output file: ${output_dir}.zip"
    echo ""
    echo "Please send the ${output_dir}.zip file to Anomalo Support:"
    echo "  - Support Portal: https://anomalo.zendesk.com"
    echo "  - Email: support@anomalo.com"
    echo "================================================================"
}

echo -e "\033[1;36m========================================================\033[0m"
echo -e "\033[1;33m     Welcome to the \033[1;32mAnomalo Diagnostic Tool"
echo ""
echo -e "\033[1;33m This tool will gather diagnostic information about"
echo -e "\033[1;33m your Anomalo deployment"
echo ""
echo -e "\033[1;33m Attach the generated zip file to your support ticket in"
echo -e "\033[1;33m the Anomalo Support Portal: https://anomalo.zendesk.com"
echo -e "\033[1;33m or send it to support@anomalo.com"
echo -e "\033[1;36m========================================================\033[0m"
echo "" # Empty line for spacing



# Loop through arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -t | --type)
        type="$2"
        shift
        shift
        ;;
        -n|--namespace)
        namespace="$2"
        shift
        shift
        ;;
        -d|--domain)
        base_domain="$2"
        shift
        shift
        ;;
        -h|--help)
        show_help
        exit 0
        ;;
        *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Set defaults and prompt for missing required parameters
if [[ -z "$type" ]]; then
    type="kubernetes"
    read -p "Enter the type of deployment (kubernetes/docker): " type
fi

if [[ -z "$namespace" && "$type" == "kubernetes" ]]; then
    namespace="anomalo"
    log_info "No namespace specified, defaulting to $namespace"
fi

if [[ -z "$base_domain" ]]; then
    # Prompt for the base domain if not provided
    read -p "Enter the base domain (e.g., anomalo.your-domain.com): " base_domain
fi

main
