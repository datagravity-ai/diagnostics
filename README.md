# Anomalo Diagnostics

This repository contains comprehensive diagnostic tools for Anomalo deployments. These tools help collect system information, logs, and configuration data to assist with troubleshooting and support.

## Features

- **Multi-platform support**: Kubernetes and Docker deployments
- **Comprehensive data collection**: System info, logs, configurations, and metrics
- **Robust error handling**: Graceful failure handling with clear error messages
- **Cross-platform compatibility**: Works on Linux, macOS, and Windows (with WSL/Git Bash)
- **Automated validation**: Checks for required tools and validates inputs
- **Progress reporting**: Real-time progress bars and feedback during data collection

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
3. Run the interactive configuration wizard

## Interactive Configuration Wizard

When you run the script without parameters, it will guide you through the configuration with a user-friendly wizard:

```
=== Configuration Wizard ===

Deployment type options:
  1) kubernetes (default)
  2) docker

Enter deployment type [kubernetes]: 

Kubernetes namespace:
  Default: anomalo

Enter namespace [anomalo]: 

Anomalo instance domain:
  Examples: anomalo.your-domain.com, https://anomalo.company.com

Enter base domain: anomalo.company.com

Output directory:
  Default: anomalo_diag_20241201_143022

Enter custom output directory (press Enter for default): 

=== Configuration Complete ===
```

The wizard shows clear defaults and examples, making it easy to configure the diagnostic tool.

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
| `--output` | `-o` | Custom output directory for diagnostic files | Auto-generated timestamped name |
| `--logs` | `-l` | Number of log lines to collect per container/pod | `250` |
| `--max-pods` | `-p` | Maximum number of pods to process (large deployments) | `50` |
| `--max-containers` | `-c` | Maximum number of containers to process (large deployments) | `50` |
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

## Output Directory Options

By default, the script creates a timestamped directory (e.g., `anomalo_diag_20241201_143022`). You can specify a custom output directory using the `--output` option.

### Examples

```bash
# Use default timestamped directory
./generate-diag.sh -d anomalo.company.com

# Specify custom directory
./generate-diag.sh -d anomalo.company.com -o ./my-diagnostics

# Use absolute path
./generate-diag.sh -d anomalo.company.com -o /tmp/anomalo-debug

# Use relative path (relative to current directory)
./generate-diag.sh -d anomalo.company.com -o ../diagnostics/anomalo-$(date +%Y%m%d)
```

### Output Directory Behavior

- **Auto-creation**: The script will create the directory if it doesn't exist
- **Parent directory check**: The parent directory must exist
- **Overwrite protection**: If the directory exists, you'll be prompted to confirm overwrite
- **Absolute paths**: Relative paths are converted to absolute paths for consistency

## Log Collection Options

The script collects logs from all containers/pods with configurable line counts:

### Examples

```bash
# Default log collection (250 lines)
./generate-diag.sh -d anomalo.company.com

# Collect more logs for detailed debugging
./generate-diag.sh -d anomalo.company.com -l 1000

# Collect fewer logs for smaller files
./generate-diag.sh -d anomalo.company.com -l 100

# Collect comprehensive logs
./generate-diag.sh -d anomalo.company.com -l 5000
```

### Log Collection Behavior

- **Kubernetes**: Collects logs from all pods in the namespace
- **Docker**: Collects logs from all containers
- **File naming**: Log files are named with the line count (e.g., `logs_pod-name_last500.txt`)
- **Validation**: Log line count must be a positive integer (1-10000)
- **Warning**: Large log counts (>10000) will show a warning about file size

## Progress Tracking

The diagnostic script provides real-time progress tracking with visual progress bars:

### Progress Bar Features

- **Visual progress**: Animated progress bar showing completion percentage
- **Step counting**: Shows current step and total steps (e.g., "15/25")
- **Dynamic sizing**: Progress bar adjusts based on actual workload
- **Real-time updates**: Progress updates as each operation completes

### Progress Bar Display

```
Progress: [████████████░░░░░░░░] 60% (15/25)
```

- **Filled blocks (█)**: Completed steps
- **Empty blocks (░)**: Remaining steps
- **Percentage**: Overall completion percentage
- **Step counter**: Current step / total steps

### What's Tracked

**Kubernetes deployments:**
- Resource collection (nodes, events, services, etc.)
- Pod log collection (each pod is a step)
- ConfigMap collection (each ConfigMap is a step)
- Secret collection and final processing steps

**Docker deployments:**
- System information gathering
- Container listing and inspection
- Log collection (each container is a step)
- Final processing and compression

## Large Deployment Handling

The diagnostic script includes intelligent handling for large deployments with many pods or containers:

### Automatic Detection

When the script detects more than 50 pods or containers, it will:

1. **Warn the user** about the large deployment
2. **Explain the risks** (long collection time, large files, resource usage)
3. **Present options** for handling the large deployment

### User Options

When a large deployment is detected, you'll see:

```
WARNING: Large deployment detected: 150 pods found (limit: 50)

This deployment has a large number of pods which could:
  - Take a very long time to collect (potentially hours)
  - Create very large diagnostic files (potentially GBs)
  - Consume significant system resources

Options:
  1) Continue with all pods (not recommended)
  2) Collect only the first 50 pods (recommended)
  3) Skip pod collection entirely
  4) Exit and adjust limits
```

### Command Line Overrides

You can pre-configure limits to avoid interactive prompts:

```bash
# Increase pod limit to 100
./generate-diag.sh -d anomalo.company.com -p 100

# Increase container limit to 200
./generate-diag.sh -d anomalo.company.com -c 200

# Set both limits
./generate-diag.sh -d anomalo.company.com -p 100 -c 200

# Disable limits (collect all - use with caution)
./generate-diag.sh -d anomalo.company.com -p 9999 -c 9999
```

### Recommended Strategies

**For large Kubernetes deployments:**
- Use `-p 50` to limit pod collection
- Focus on problematic pods first
- Collect logs from specific pods manually if needed

**For large Docker deployments:**
- Use `-c 50` to limit container collection
- Prioritize running containers over stopped ones
- Consider collecting logs from specific containers manually

**For very large deployments:**
- Use `-p 20 -c 20` for quick diagnostics
- Collect only essential information
- Use targeted kubectl/docker commands for specific issues

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
├── anomalo-env_configmap.yaml
├── nginx-conf_configmap.yaml
├── [other-configmap]_configmap.yaml  # All ConfigMaps in namespace
├── secrets_anomalo.txt
├── anomalo-env-secrets_secret.yaml  # Contains sensitive data
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

- **Secrets**: Only secret names are collected by default, except for `anomalo-env-secrets` which contains values for debugging
- **Sensitive Data**: ConfigMap values and the `anomalo-env-secrets` Secret values are collected (review before sharing)
- **Network Access**: Script connects to your Anomalo instance for health metrics
- **File Permissions**: Ensure the script has appropriate permissions to read system information

### Sensitive Data Collection

The script collects the following sensitive data for debugging purposes:
- **ConfigMap values**: All ConfigMaps in the namespace (including `anomalo-env`, `nginx-conf`, etc.)
- **Secret values**: `anomalo-env-secrets` Secret (if it exists)

**Important**: These files contain sensitive information like passwords, API keys, and configuration data. Review the contents before sharing with support teams.