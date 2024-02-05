#!/bin/bash
# Usage example: chmod +x generate-diag.sh 
# Kubernetes: ./generate-diag.sh -t kubernetes -n anomalo -d anomalo.your-domain.com
# Docker: ./generate-diag.sh -t docker -d anomalo.your-domain.com

# Begin Kubernetes Content
check_kubectl_connection() {
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo "kubectl is not installed. Please install kubectl and try again."
        exit 1
    fi

    # Check if kubectl can connect to the Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        echo "Cannot connect to the Kubernetes cluster. Please check your configuration."
        exit 1
    fi
    local namespace=$1
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        echo "Namespace $namespace does not exist. Please specify a valid namespace."
        exit 1
    fi
}

gather_k8s_info() {
    local namespace=$1
    local output_dir=$2

    # Get all resources in the specified namespace
    echo "Gathering all resources in the $namespace namespace..."
    kubectl get all -n "$namespace" -o wide > "$output_dir/all_resources_${namespace}.txt"

    # Check the status of each pod and fetch logs or describe
    echo "Gathering pod logs and describe output..."
    kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read -r pod; do
        local status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}')
        if [ "$status" != "Running" ]; then
            # Describe pod if not in Running state
            kubectl describe pod "$pod" -n "$namespace" > "$output_dir/describe_${pod}.txt"
        else
            # Get the last 250 lines of logs for running pods
            kubectl logs "$pod" -n "$namespace" --all-containers=true --tail=250 > "$output_dir/logs_${pod}_last250.txt"
        fi
    done

    # Get deployment configurations in the specified namespace
    echo "Gathering deployment configurations..."
    kubectl get deployments -n "$namespace" -o yaml > "$output_dir/deployments_config_${namespace}.yaml"

    # List ConfigMaps names, each on a new line, in the specified namespace
    echo "Gathering ConfigMaps"
    kubectl get configmaps -n "$namespace" -o jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" > "$output_dir/configmaps_${namespace}.txt"
    
    # Get the values from the 'anomalo-env' and 'nginx-conf' ConfigMaps
    echo "Gathering ConfigMap values..."
    kubectl get configmap anomalo-env -n "$namespace" -o yaml > "$output_dir/anomalo-env_configmap.yaml"
    kubectl get configmap nginx-conf -n "$namespace" -o yaml > "$output_dir/nginx-conf_configmap.yaml"
    
    # List Secret names, each on a new line, in the specified namespace
    echo "Gathering Secret names, not values"
    kubectl get secrets -n "$namespace" -o jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" > "$output_dir/secrets_${namespace}.txt"
}

# End Kubernetes Content

# Begin Docker Content
check_docker_connection() {
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Please install Docker and try again."
        exit 1
    fi

    # Check if docker can connect to the Docker daemon
    if ! docker info &> /dev/null; then
        echo "Cannot connect to the Docker daemon. Please check your configuration."
        exit 1
    fi
}

gather_host_info() {
    # Get the host's OS and kernel version
    echo "Gathering host OS and kernel version..."
    uname -a > "$output_dir/host_os_kernel.txt"

    # Get the host's CPU and memory info
    echo "Gathering host CPU and memory info..."
    lscpu > "$output_dir/host_cpu_info.txt"
    free -h > "$output_dir/host_memory_info.txt"

    # Get the host's disk usage
    echo "Gathering host disk usage..."
    df -h > "$output_dir/host_disk_usage.txt"

    # Get the host's network interfaces and routing table
    echo "Gathering host network interfaces and routing table..."
    ip a > "$output_dir/host_network_interfaces.txt"
    ip route > "$output_dir/host_routing_table.txt"

}

gather_docker_info() {
    gather_host_info
    check_docker_connection
    # Get the list of running containers
    echo "Gathering list of running containers..."
    docker ps > "$output_dir/running_containers.txt"

    # Get the list of all containers
    echo "Gathering list of all containers..."
    docker ps -a > "$output_dir/all_containers.txt"

    # Get the list of all images
    echo "Gathering list of all images..."
    docker images > "$output_dir/all_images.txt"

    # Get the list of all volumes
    echo "Gathering list of all volumes..."
    docker volume ls > "$output_dir/all_volumes.txt"

    # Get the list of all networks
    echo "Gathering list of all networks..."
    docker network ls > "$output_dir/all_networks.txt"

    # Get the list of all logs
    echo "Gathering logs for all containers..."
    docker ps -a --format '{{.Names}}' | while read -r name; do
        docker logs -n 250 "$name" >"${output_dir}/logs_${name}_stdout.txt" 2>"${output_dir}/logs_${name}_stderr.txt"
    done

    # Get the list of all inspect
    echo "Gathering inspect for all containers..."
    docker ps -a --format '{{.Names}}' | while read -r name; do
        docker inspect "$name" > "$output_dir/inspect_${name}.txt"
    done

    # Remove any empty file
    find "$output_dir" -type f -empty -delete

    
}
# End Docker Content

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t, --type <type>            Specify the type of deployment. kubernetes/docker (default: kubernetes)"
    echo "  -n, --namespace <namespace>  Specify the namespace to gather information from (default: anomalo)"
    echo "  -d, --domain <base_domain>   Specify the base domain URL for your anomalo instance. Eg. anomalo.your-domain.com"
    echo "  -h, --help                   Show this help message and exit"
    echo ""
}

main() {
    # Construct the full URL for health check
    health_check_url="https://${base_domain}/health_check?metrics=1"

    # Directory to store output files
    output_dir="anomalo_diag_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$output_dir"


    if [[ "$type" == "docker" ]]; then
        gather_docker_info
    fi
    if [[ "$type" == "kubernetes" ]]; then
        echo "Gathering diagnostic information for Kubernetes deployment..."
        check_kubectl_connection "$namespace"
        # Call the function to gather Kubernetes info
        gather_k8s_info "$namespace" "$output_dir"
    fi

    # Fetch metrics from the specified URL
    if curl "$health_check_url" -o "$output_dir/metrics.json"; then
        echo "Metrics data fetched successfully from $health_check_url."
    else
        echo "Failed to fetch metrics data from $health_check_url but continuing..."
    fi

    zip -rq "${output_dir}.zip" "$output_dir"
    echo "Output directory compressed into ${output_dir}.zip"

    # clean up output directory
    echo "Cleaning up..."
    rm -rf "$output_dir"

    echo "Please send the ${output_dir}.zip file to Anomalo Support."
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

if [[ -z "$type" ]]; then
    type="kubernetes"
    read -p "Enter the type of deployment (kubernetes/docker): " type
    if [[ "$type" != "kubernetes" && "$type" != "docker" ]]; then
        echo "Invalid deployment type. Please specify 'kubernetes' or 'docker'."
        exit 1
    fi
fi

if [[ -z "$namespace" && "$type" == "kubernetes" ]]; then
    namespace="anomalo"
    echo "No namespace specified, defaulting to $namespace"
fi

if [[ -z "$base_domain" ]]; then
    # Prompt for the base domain if not provided
    read -p "Enter the base domain (e.g., anomalo.your-domain.com): " base_domain
fi

main
