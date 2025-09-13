#!/bin/bash
# Usage example: chmod +x generate-diag.sh 
# Kubernetes: ./generate-diag.sh -t kubernetes -n anomalo -d anomalo.your-domain.com
# Docker: ./generate-diag.sh -t docker -d anomalo.your-domain.com

# Enable strict error handling
set -euo pipefail

# Global variables
output_dir=""
type=""
namespace=""
base_domain=""
custom_output_dir=""
log_lines="250"
total_steps=0
current_step=0
max_pods=50
max_containers=50

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

# Progress bar functions
init_progress() {
    total_steps=$1
    current_step=0
    echo ""
    echo "Progress: [                    ] 0%"
}

update_progress() {
    current_step=$((current_step + 1))
    local percentage=$((current_step * 100 / total_steps))
    local filled=$((current_step * 20 / total_steps))
    local empty=$((20 - filled))
    
    # Build progress bar string
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # Move cursor to beginning of line and update progress
    printf "\rProgress: [%s] %d%% (%d/%d)" "$bar" "$percentage" "$current_step" "$total_steps"
}

complete_progress() {
    printf "\rProgress: [████████████████████] 100%% (%d/%d)\n" "$total_steps" "$total_steps"
    echo ""
}

# Handle large deployments
check_large_deployment() {
    local resource_type="$1"
    local count="$2"
    local max_count="$3"
    
    if [[ "$count" -gt "$max_count" ]]; then
        log_warning "Large deployment detected: $count $resource_type found (limit: $max_count)"
        echo ""
        echo "This deployment has a large number of $resource_type which could:"
        echo "  - Take a very long time to collect (potentially hours)"
        echo "  - Create very large diagnostic files (potentially GBs)"
        echo "  - Consume significant system resources"
        echo ""
        echo "Options:"
        echo "  1) Continue with all $resource_type (not recommended)"
        echo "  2) Collect only the first $max_count $resource_type (recommended)"
        echo "  3) Skip $resource_type collection entirely"
        echo "  4) Exit and adjust limits"
        echo ""
        
        while true; do
            read -p "Choose an option [2]: " choice
            case "${choice:-2}" in
                1)
                    log_warning "Proceeding with all $count $resource_type - this may take a very long time"
                    return 0
                    ;;
                2)
                    log_info "Limiting collection to first $max_count $resource_type"
                    return 1
                    ;;
                3)
                    log_info "Skipping $resource_type collection"
                    return 2
                    ;;
                4)
                    log_info "Exiting. You can adjust limits by setting max_pods or max_containers variables."
                    exit 0
                    ;;
                *)
                    echo "Invalid option. Please choose 1, 2, 3, or 4."
                    ;;
            esac
        done
    fi
    return 0
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
    
    # Validate log lines parameter
    if [[ -n "$log_lines" ]]; then
        if ! [[ "$log_lines" =~ ^[0-9]+$ ]]; then
            log_error "Log lines must be a positive integer. Got: $log_lines"
            exit 1
        fi
        if [[ "$log_lines" -lt 1 ]]; then
            log_error "Log lines must be at least 1. Got: $log_lines"
            exit 1
        fi
        if [[ "$log_lines" -gt 10000 ]]; then
            log_warning "Log lines is very large ($log_lines). This may create very large files."
        fi
        log_info "Using custom log lines: $log_lines"
    fi
    
    # Validate max pods parameter
    if [[ -n "$max_pods" ]]; then
        if ! [[ "$max_pods" =~ ^[0-9]+$ ]]; then
            log_error "Max pods must be a positive integer. Got: $max_pods"
            exit 1
        fi
        if [[ "$max_pods" -lt 1 ]]; then
            log_error "Max pods must be at least 1. Got: $max_pods"
            exit 1
        fi
        log_info "Using max pods limit: $max_pods"
    fi
    
    # Validate max containers parameter
    if [[ -n "$max_containers" ]]; then
        if ! [[ "$max_containers" =~ ^[0-9]+$ ]]; then
            log_error "Max containers must be a positive integer. Got: $max_containers"
            exit 1
        fi
        if [[ "$max_containers" -lt 1 ]]; then
            log_error "Max containers must be at least 1. Got: $max_containers"
            exit 1
        fi
        log_info "Using max containers limit: $max_containers"
    fi
    
    # Validate custom output directory if provided
    if [[ -n "$custom_output_dir" ]]; then
        # Convert to absolute path
        if [[ "$custom_output_dir" = /* ]]; then
            # Already absolute path
            custom_output_dir="$custom_output_dir"
        else
            # Relative path - convert to absolute
            custom_output_dir="$(pwd)/$custom_output_dir"
        fi
        
        # Check if parent directory exists
        local parent_dir
        parent_dir=$(dirname "$custom_output_dir")
        if [[ ! -d "$parent_dir" ]]; then
            log_error "Parent directory does not exist: $parent_dir"
            exit 1
        fi
        
        # Check if output directory already exists
        if [[ -e "$custom_output_dir" ]]; then
            log_warning "Output directory already exists: $custom_output_dir"
            read -p "Do you want to overwrite it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Exiting without overwriting existing directory."
                exit 0
            fi
        fi
        
        log_info "Using custom output directory: $custom_output_dir"
    fi
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

    # Initialize progress bar (estimate steps)
    local estimated_steps=15  # Base steps
    local pod_count=0
    local configmap_count=0
    
    # Count pods and configmaps for more accurate progress
    if pods=$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); then
        pod_count=$(echo "$pods" | grep -c . || echo "0")
    fi
    if configmaps=$(kubectl get configmaps -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); then
        configmap_count=$(echo "$configmaps" | grep -c . || echo "0")
    fi
    
    total_steps=$((estimated_steps + pod_count + configmap_count))
    init_progress $total_steps

    # Get all resources in the specified namespace
    safe_execute "kubectl get all -n '$namespace' -o wide" "$output_dir/all_resources_${namespace}.txt" "All resources in $namespace namespace"
    update_progress

    # Get events for the namespace
    safe_execute "kubectl get events -n '$namespace' --sort-by='.lastTimestamp'" "$output_dir/events_${namespace}.txt" "Events in $namespace namespace"
    update_progress

    # Get node information
    safe_execute "kubectl get nodes -o wide" "$output_dir/nodes.txt" "Cluster nodes information"
    update_progress

    # Get node metrics if available
    kubectl top nodes > "$output_dir/node_metrics.txt" 2>/dev/null || log_warning "Node metrics not available (metrics-server may not be installed)"
    update_progress

    # Check the status of each pod and fetch logs or describe
    log_info "Gathering pod information and logs..."
    local pods
    if pods=$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); then
        local pod_count=$(echo "$pods" | grep -c . || echo "0")
        
        # Check for large deployment
        check_large_deployment "pods" "$pod_count" "$max_pods"
        local large_deployment_result=$?
        
        if [[ "$large_deployment_result" -eq 2 ]]; then
            # Skip pod collection
            log_info "Skipping pod collection due to large deployment"
            # Update progress for skipped pods
            for ((i=0; i<pod_count; i++)); do
                update_progress
            done
        else
            local pods_to_process="$pods"
            if [[ "$large_deployment_result" -eq 1 ]]; then
                # Limit to first max_pods
                pods_to_process=$(echo "$pods" | head -n "$max_pods")
                log_info "Processing first $max_pods pods out of $pod_count total"
            fi
            
            while IFS= read -r pod; do
                if [[ -n "$pod" ]]; then
                    local status
                    if status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null); then
                        if [[ "$status" != "Running" ]]; then
                            # Describe pod if not in Running state
                            safe_execute "kubectl describe pod '$pod' -n '$namespace'" "$output_dir/describe_${pod}.txt" "Pod description for $pod"
                        else
                            # Get the last N lines of logs for running pods
                            safe_execute "kubectl logs '$pod' -n '$namespace' --all-containers=true --tail=$log_lines" "$output_dir/logs_${pod}_last${log_lines}.txt" "Logs for pod $pod"
                        fi
                    else
                        log_warning "Could not get status for pod: $pod"
                    fi
                    update_progress
                fi
            done <<< "$pods_to_process"
        fi
    else
        log_warning "Could not list pods in namespace: $namespace"
    fi

    # Get deployment configurations in the specified namespace
    safe_execute "kubectl get deployments -n '$namespace' -o yaml" "$output_dir/deployments_config_${namespace}.yaml" "Deployment configurations"
    update_progress

    # Get services
    safe_execute "kubectl get services -n '$namespace' -o wide" "$output_dir/services_${namespace}.txt" "Services in $namespace namespace"
    update_progress

    # Get ingress
    safe_execute "kubectl get ingress -n '$namespace' -o wide" "$output_dir/ingress_${namespace}.txt" "Ingress in $namespace namespace"
    update_progress

    # Get persistent volumes and claims
    safe_execute "kubectl get pv,pvc -n '$namespace'" "$output_dir/storage_${namespace}.txt" "Storage resources in $namespace namespace"
    update_progress

    # List ConfigMaps names, each on a new line, in the specified namespace
    safe_execute "kubectl get configmaps -n '$namespace' -o jsonpath=\"{range .items[*]}{.metadata.name}{'\n'}{end}\"" "$output_dir/configmaps_${namespace}.txt" "ConfigMap names in $namespace namespace"
    update_progress
    
    # Get the values from all ConfigMaps in the namespace
    log_info "Gathering all ConfigMap values..."
    local configmaps
    if configmaps=$(kubectl get configmaps -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); then
        while IFS= read -r configmap; do
            if [[ -n "$configmap" ]]; then
                safe_execute "kubectl get configmap '$configmap' -n '$namespace' -o yaml" "$output_dir/${configmap}_configmap.yaml" "ConfigMap $configmap"
                update_progress
            fi
        done <<< "$configmaps"
    else
        log_warning "Could not list ConfigMaps in namespace: $namespace"
    fi
    
    # List Secret names, each on a new line, in the specified namespace
    safe_execute "kubectl get secrets -n '$namespace' -o jsonpath=\"{range .items[*]}{.metadata.name}{'\n'}{end}\"" "$output_dir/secrets_${namespace}.txt" "Secret names in $namespace namespace"
    update_progress

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
    update_progress

    complete_progress
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
    
    # Initialize progress bar for Docker collection
    local estimated_steps=12  # Base steps
    local container_count=0
    
    # Count containers for more accurate progress
    if containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null); then
        container_count=$(echo "$containers" | grep -c . || echo "0")
    fi
    
    total_steps=$((estimated_steps + container_count * 2))  # *2 for logs and inspect
    init_progress $total_steps
    
    gather_host_info "$output_dir"
    check_docker_connection
    
    # Get the list of running containers
    safe_execute "docker ps" "$output_dir/running_containers.txt" "Running containers"
    update_progress

    # Get the list of all containers
    safe_execute "docker ps -a" "$output_dir/all_containers.txt" "All containers"
    update_progress

    # Get the list of all images
    safe_execute "docker images" "$output_dir/all_images.txt" "All images"
    update_progress

    # Get the list of all volumes
    safe_execute "docker volume ls" "$output_dir/all_volumes.txt" "All volumes"
    update_progress

    # Get the list of all networks
    safe_execute "docker network ls" "$output_dir/all_networks.txt" "All networks"
    update_progress

    # Get Docker system information
    safe_execute "docker system df" "$output_dir/docker_system_df.txt" "Docker system disk usage"
    update_progress
    safe_execute "docker version" "$output_dir/docker_version.txt" "Docker version information"
    update_progress

    # Get the list of all logs
    log_info "Gathering container logs..."
    local containers
    if containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null); then
        local container_count=$(echo "$containers" | grep -c . || echo "0")
        
        # Check for large deployment
        check_large_deployment "containers" "$container_count" "$max_containers"
        local large_deployment_result=$?
        
        if [[ "$large_deployment_result" -eq 2 ]]; then
            # Skip container collection
            log_info "Skipping container collection due to large deployment"
            # Update progress for skipped containers
            for ((i=0; i<container_count; i++)); do
                update_progress
            done
        else
            local containers_to_process="$containers"
            if [[ "$large_deployment_result" -eq 1 ]]; then
                # Limit to first max_containers
                containers_to_process=$(echo "$containers" | head -n "$max_containers")
                log_info "Processing first $max_containers containers out of $container_count total"
            fi
            
            while IFS= read -r name; do
                if [[ -n "$name" ]]; then
                    # Get container logs
                    if docker logs -n "$log_lines" "$name" >"${output_dir}/logs_${name}_stdout.txt" 2>"${output_dir}/logs_${name}_stderr.txt" 2>/dev/null; then
                        log_success "Logs for container $name"
                    else
                        log_warning "Could not get logs for container: $name"
                    fi
                    update_progress
                fi
            done <<< "$containers_to_process"
        fi
    else
        log_warning "Could not list containers"
    fi

    # Get the list of all inspect
    log_info "Gathering container inspection data..."
    if containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null); then
        local container_count=$(echo "$containers" | grep -c . || echo "0")
        
        # Check for large deployment
        check_large_deployment "containers" "$container_count" "$max_containers"
        local large_deployment_result=$?
        
        if [[ "$large_deployment_result" -eq 2 ]]; then
            # Skip container inspection
            log_info "Skipping container inspection due to large deployment"
            # Update progress for skipped containers
            for ((i=0; i<container_count; i++)); do
                update_progress
            done
        else
            local containers_to_process="$containers"
            if [[ "$large_deployment_result" -eq 1 ]]; then
                # Limit to first max_containers
                containers_to_process=$(echo "$containers" | head -n "$max_containers")
                log_info "Processing first $max_containers containers out of $container_count total"
            fi
            
            while IFS= read -r name; do
                if [[ -n "$name" ]]; then
                    if docker inspect "$name" > "$output_dir/inspect_${name}.txt" 2>/dev/null; then
                        log_success "Inspection data for container $name"
                    else
                        log_warning "Could not inspect container: $name"
                    fi
                    update_progress
                fi
            done <<< "$containers_to_process"
        fi
    fi

    # Remove any empty files
    find "$output_dir" -type f -empty -delete 2>/dev/null || true

    complete_progress
    log_success "Docker diagnostic information gathered successfully"
}
# End Docker Content

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -t, --type <type>            Specify the type of deployment. kubernetes/docker (default: kubernetes)"
    echo "  -n, --namespace <namespace>  Specify the namespace to gather information from (default: anomalo)"
    echo "  -d, --domain <base_domain>   Specify the base domain URL for your anomalo instance."
    echo "                               Examples: anomalo.your-domain.com, https://anomalo.company.com"
    echo "  -o, --output <directory>     Specify custom output directory (default: auto-generated timestamped name)"
    echo "  -l, --logs <number>          Number of log lines to collect per container/pod (default: 250)"
    echo "  -p, --max-pods <number>      Maximum number of pods to process (default: 50)"
    echo "  -c, --max-containers <number> Maximum number of containers to process (default: 50)"
    echo "  -h, --help                   Show this help message and exit"
    echo ""
    echo "Interactive Mode:"
    echo "  If you run the script without parameters, it will guide you through"
    echo "  the configuration with an interactive wizard showing defaults."
    echo ""
    echo "  Example: $0"
    echo ""
    echo "Note: The domain parameter accepts various formats:"
    echo "  - anomalo.your-domain.com"
    echo "  - https://anomalo.your-domain.com"
    echo "  - http://anomalo.your-domain.com"
    echo "  - www.anomalo.your-domain.com"
    echo "  The script will automatically normalize the domain format."
    echo ""
    echo "Output directory examples:"
    echo "  - ./my-diagnostics"
    echo "  - /tmp/anomalo-debug"
    echo "  - ~/diagnostics/anomalo-$(date +%Y%m%d)"
    echo ""
    echo "Log lines examples:"
    echo "  - 100 (for smaller files)"
    echo "  - 500 (for more detailed logs)"
    echo "  - 1000 (for comprehensive debugging)"
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
    if [[ -n "$custom_output_dir" ]]; then
        output_dir="$custom_output_dir"
    else
        output_dir="anomalo_diag_$(date +%Y%m%d_%H%M%S)"
    fi
    
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

    # Initialize progress for final steps
    init_progress 4

    # Fetch metrics from the specified URL
    log_info "Fetching health check metrics..."
    if curl -s --connect-timeout 30 --max-time 60 "$health_check_url" -o "$output_dir/metrics.json"; then
        log_success "Metrics data fetched successfully from $health_check_url"
    else
        log_warning "Failed to fetch metrics data from $health_check_url (continuing anyway)"
        echo "{}" > "$output_dir/metrics.json"  # Create empty JSON file
    fi
    update_progress

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
    update_progress

    # Compress the output directory
    log_info "Compressing diagnostic data..."
    if zip -rq "${output_dir}.zip" "$output_dir"; then
        log_success "Output directory compressed into ${output_dir}.zip"
    else
        log_error "Failed to compress output directory"
        exit 1
    fi
    update_progress

    complete_progress

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
        -o|--output)
        custom_output_dir="$2"
        shift
        shift
        ;;
        -l|--logs)
        log_lines="$2"
        shift
        shift
        ;;
        -p|--max-pods)
        max_pods="$2"
        shift
        shift
        ;;
        -c|--max-containers)
        max_containers="$2"
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

# Interactive wizard for missing parameters
echo ""
echo "=== Configuration Wizard ==="
echo ""

# Prompt for deployment type with default
if [[ -z "$type" ]]; then
    echo "Deployment type options:"
    echo "  1) kubernetes (default)"
    echo "  2) docker"
    echo ""
    read -p "Enter deployment type [kubernetes]: " type
    if [[ -z "$type" ]]; then
        type="kubernetes"
    fi
    echo "Selected: $type"
    echo ""
fi

# Prompt for namespace if Kubernetes with default
if [[ -z "$namespace" && "$type" == "kubernetes" ]]; then
    echo "Kubernetes namespace:"
    echo "  Default: anomalo"
    echo ""
    read -p "Enter namespace [anomalo]: " namespace
    if [[ -z "$namespace" ]]; then
        namespace="anomalo"
    fi
    echo "Selected: $namespace"
    echo ""
fi

# Prompt for base domain
if [[ -z "$base_domain" ]]; then
    echo "Anomalo instance domain:"
    echo "  Examples: anomalo.your-domain.com, https://anomalo.company.com"
    echo ""
    read -p "Enter base domain: " base_domain
    if [[ -z "$base_domain" ]]; then
        log_error "Base domain is required."
        exit 1
    fi
    echo "Selected: $base_domain"
    echo ""
fi

# Prompt for output directory with default
if [[ -z "$custom_output_dir" ]]; then
    echo "Output directory:"
    echo "  Default: anomalo_diag_$(date +%Y%m%d_%H%M%S)"
    echo ""
    read -p "Enter custom output directory (press Enter for default): " custom_output_dir
    if [[ -z "$custom_output_dir" ]]; then
        custom_output_dir=""
    else
        echo "Selected: $custom_output_dir"
    fi
    echo ""
fi

# Prompt for log lines with default
if [[ -z "$log_lines" ]]; then
    echo "Number of log lines to collect:"
    echo "  Default: 250"
    echo "  Examples: 100 (smaller files), 500 (more detail), 1000 (comprehensive)"
    echo ""
    read -p "Enter number of log lines [250]: " log_lines
    if [[ -z "$log_lines" ]]; then
        log_lines="250"
    fi
    echo "Selected: $log_lines"
    echo ""
fi

echo "=== Configuration Complete ==="
echo ""

main
