#!/bin/bash
# Usage example: chmod +x generate-diag.sh && ./generate-diag.sh

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

# Check kubectl installation and connection
check_kubectl_connection

# Prompt the user for a namespace, default to "anomalo"
read -p "Enter the Kubernetes namespace (default: anomalo): " namespace
namespace=${namespace:-anomalo}

# Prompt the user for the base domain
read -p "Enter the base domain (e.g., anomalo.your-domain.com): " base_domain

# Construct the full URL for health check
health_check_url="https://${base_domain}/health_check?metrics=1"

# Directory to store output files
output_dir="anomalo_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$output_dir"

# Call the function to gather Kubernetes info
gather_k8s_info "$namespace" "$output_dir"

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