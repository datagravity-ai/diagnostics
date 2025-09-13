# Anomalo Diagnostics

This repository contains comprehensive diagnostic tools for Anomalo deployments. These tools help collect system information, logs, and configuration data to assist with troubleshooting and support.

## Features

- **Multi-platform support**: Kubernetes and Docker deployments
- **Comprehensive data collection**: System info, logs, configurations, and metrics
- **Robust error handling**: Graceful failure handling with clear error messages
- **Cross-platform compatibility**: Works on Linux, macOS, and Windows (with WSL/Git Bash)
- **Automated validation**: Checks for required tools and validates inputs
- **Progress reporting**: Real-time feedback during data collection

## Quick Start

### One-Command Installation and Execution

**Linux/macOS:**
```bash
curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.sh -o generate-diag.sh && chmod +x generate-diag.sh && ./generate-diag.sh
```

**Windows:**
```cmd
curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.bat -o generate-diag.bat && generate-diag.bat
```

This will:
1. Download the diagnostic script (and Windows helper if on Windows)
2. Make it executable (Linux/macOS) or run the Windows helper
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
| `--domain` | `-d` | Base domain URL for your Anomalo instance (supports various formats) | *required* |
| `--help` | `-h` | Show help message and exit | - |

## Domain Format

The `--domain` parameter is flexible and accepts various formats. The script will automatically normalize the input:

**Supported formats:**
- `anomalo.your-domain.com`
- `https://anomalo.your-domain.com`
- `http://anomalo.your-domain.com`
- `www.anomalo.your-domain.com`
- `https://www.anomalo.your-domain.com/`

**Examples:**
```bash
# All of these work the same way:
./generate-diag.sh -d anomalo.company.com
./generate-diag.sh -d https://anomalo.company.com
./generate-diag.sh -d http://anomalo.company.com
./generate-diag.sh -d www.anomalo.company.com
```

The script will automatically:
- Remove `http://` or `https://` prefixes
- Remove `www.` prefixes
- Remove trailing slashes
- Use the normalized domain for health check requests

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

## Windows Support

The diagnostic script is a bash script and requires a Unix-like environment to run on Windows. Here are your options:

### Option 1: Windows Subsystem for Linux (WSL) - Recommended
1. **Install WSL2**: Follow [Microsoft's WSL installation guide](https://docs.microsoft.com/en-us/windows/wsl/install)
2. **Install required tools** in your WSL environment:
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt install curl zip kubectl docker.io
   
   # Or use the script directly
   curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.sh -o generate-diag.sh && chmod +x generate-diag.sh && ./generate-diag.sh
   ```

### Option 0: Windows Batch Helper - Easiest
1. **Download and run the Windows batch file**:
   ```cmd
   curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.bat -o generate-diag.bat && generate-diag.bat
   ```
2. **The batch file will**:
   - Check for required tools (bash, curl, zip)
   - Download and run the diagnostic script
   - Provide helpful error messages if tools are missing

### Option 2: Git Bash
1. **Install Git for Windows** (includes Git Bash)
2. **Install additional tools**:
   - `kubectl`: Download from [Kubernetes releases](https://github.com/kubernetes/kubernetes/releases)
   - `curl` and `zip`: Usually included with Git Bash
3. **Run the script** in Git Bash terminal

### Option 3: Docker Desktop
If you're using Docker Desktop on Windows:
1. **Use Docker Desktop's built-in terminal**
2. **Install kubectl** if needed for Kubernetes deployments
3. **Run the script** from the Docker Desktop terminal

### Windows-Specific Notes
- **File paths**: Use forward slashes (`/`) in paths, even on Windows
- **Permissions**: You may need to run as Administrator for some system information
- **Docker access**: Ensure Docker Desktop is running and accessible
- **kubectl config**: Your kubeconfig should be in `~/.kube/config` (WSL) or `%USERPROFILE%\.kube\config` (Windows)

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

**Windows-specific Issues**

**"bash: command not found" or "script won't run"**
- Use WSL2, Git Bash, or Docker Desktop terminal
- Ensure you're in a Unix-like environment
- Check that the script has execute permissions: `chmod +x generate-diag.sh`

**"kubectl: command not found" on Windows**
- Install kubectl for Windows: Download from [Kubernetes releases](https://github.com/kubernetes/kubernetes/releases)
- Add kubectl to your PATH environment variable
- Or use WSL2 where kubectl installation is easier

**"Cannot connect to Docker daemon" on Windows**
- Ensure Docker Desktop is running
- In WSL2, you may need to start Docker Desktop's WSL2 integration
- Check Docker Desktop settings: Settings → Resources → WSL Integration

**"Permission denied" errors on Windows**
- Run your terminal as Administrator
- In WSL2, you may need to use `sudo` for some commands
- Check file permissions and ownership

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