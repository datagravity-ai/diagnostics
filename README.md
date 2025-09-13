# Anomalo Diagnostics

This repository contains comprehensive diagnostic tools for Anomalo deployments. These tools help collect system information, logs, and configuration data to assist with troubleshooting and support.

## Features

- **Multi-platform support**: Kubernetes and Docker deployments
- **Comprehensive data collection**: System info, logs, configurations, and metrics
- **Robust error handling**: Graceful failure handling with clear error messages
- **Cross-platform compatibility**: Works on Linux, macOS, and Windows
- **Automated validation**: Checks for required tools and validates inputs
- **Progress reporting**: Real-time feedback during data collection

## Quick Start

### One-Command Installation and Execution

```bash
curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.sh -o generate-diag.sh && chmod +x generate-diag.sh && ./generate-diag.sh
```

This will:
1. Download the diagnostic script
2. Make it executable
3. Run it with interactive prompts for required parameters

## Supported Deployment Types

### Kubernetes Deployments

The script collects comprehensive Kubernetes diagnostic information including:

- **Cluster Information**: Nodes, events, and cluster health
- **Namespace Resources**: Pods, services, deployments, ingress, storage
- **Pod Details**: Logs, descriptions, and status for all pods
- **Configuration**: ConfigMaps, Secrets (names only), and deployment YAML
- **Metrics**: Node metrics and resource usage (if available)

#### Kubernetes Usage Examples

```bash
# Basic usage with prompts
./generate-diag.sh

# Specify all parameters
./generate-diag.sh -t kubernetes -n anomalo -d anomalo.your-domain.com

# Use different namespace
./generate-diag.sh -t kubernetes -n my-anomalo-namespace -d anomalo.company.com
```

### Docker Deployments

The script collects Docker-specific diagnostic information including:

- **Container Information**: Running and stopped containers, images, volumes, networks
- **Container Logs**: Recent logs from all containers
- **System Information**: Host OS, CPU, memory, disk usage, network configuration
- **Docker Details**: Version, system usage, and container inspection data

#### Docker Usage Examples

```bash
# Docker deployment
./generate-diag.sh -t docker -d anomalo.your-domain.com
```

## Command Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--type` | `-t` | Deployment type: `kubernetes` or `docker` | `kubernetes` |
| `--namespace` | `-n` | Kubernetes namespace (Kubernetes only) | `anomalo` |
| `--domain` | `-d` | Base domain URL for your Anomalo instance | *required* |
| `--help` | `-h` | Show help message and exit | - |

## Prerequisites

### Required Tools
- `curl` - For downloading the script and fetching health metrics
- `zip` - For compressing the diagnostic data

### Kubernetes Deployments
- `kubectl` - Kubernetes command-line tool
- Access to the target Kubernetes cluster
- Permissions to read resources in the specified namespace

### Docker Deployments
- `docker` - Docker command-line tool
- Access to Docker daemon (may require `sudo` on some systems)

## Output

The script generates a timestamped ZIP file containing:

- **Diagnostic Summary**: Overview of collected information
- **System Information**: Host OS, CPU, memory, disk, network details
- **Application Logs**: Recent logs from all containers/pods
- **Configuration Data**: YAML configurations and environment details
- **Health Metrics**: Application health check data (if accessible)
- **Resource Information**: Kubernetes resources or Docker containers/volumes

### Example Output Structure
```
anomalo_diag_20241201_143022.zip
├── diagnostic_summary.txt
├── all_resources_anomalo.txt
├── events_anomalo.txt
├── nodes.txt
├── pods/
│   ├── logs_anomalo-web_last250.txt
│   └── describe_anomalo-worker.txt
├── configmaps_anomalo.txt
├── services_anomalo.txt
├── storage_anomalo.txt
└── metrics.json
```

## Troubleshooting

### Common Issues

**"kubectl is not installed"**
- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/
- Ensure it's in your PATH

**"Cannot connect to the Kubernetes cluster"**
- Check your kubeconfig: `kubectl config current-context`
- Verify cluster access: `kubectl cluster-info`

**"Namespace does not exist"**
- Verify the namespace name: `kubectl get namespaces`
- Check your permissions: `kubectl auth can-i get pods -n <namespace>`

**"Cannot connect to the Docker daemon"**
- Start Docker service
- Add your user to the docker group: `sudo usermod -aG docker $USER`
- Log out and back in, or use `sudo` with the script

**"Failed to fetch metrics data"**
- This is non-critical - the script will continue
- Check if your Anomalo instance is accessible at the provided domain
- Verify the health check endpoint is available

### Getting Help

If you encounter issues not covered here:

1. **Check the diagnostic summary** in the generated ZIP file
2. **Review error messages** - they often contain specific guidance
3. **Contact Anomalo Support**:
   - Support Portal: https://anomalo.zendesk.com
   - Email: support@anomalo.com
   - Include the generated ZIP file with your support request

## Security Notes

- **Secrets**: Only secret names are collected, not values
- **Sensitive Data**: ConfigMap values are collected (review before sharing)
- **Network Access**: Script connects to your Anomalo instance for health metrics
- **File Permissions**: Ensure the script has appropriate permissions to read system information

## Contributing

To contribute improvements to the diagnostic tools:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on different platforms
5. Submit a pull request

## License

This diagnostic tool is provided as-is for Anomalo customers and support teams.