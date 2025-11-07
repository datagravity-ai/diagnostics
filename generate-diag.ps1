<# 
Anomalo Diagnostic Tool (Windows PowerShell)
===========================================
For IN-VPC customers running Anomalo on their own infrastructure.
Windows-native collector focused on Kubernetes (no Docker collection).

Usage (PowerShell 7+ recommended):
  .\anomalo-diagnostics.ps1 -Namespace anomalo -Domain anomalo.your-domain.com -Logs 500 -MaxPods 50 -Output .\my-diag

Notes:
- Requires kubectl.
- Creates a zip next to the output folder.
- Does NOT display secret values unless -CollectSecrets is specified.
#>

[CmdletBinding()]
param(
  [string]$Namespace = 'anomalo',
  [Parameter(Mandatory=$true)]
  [string]$Domain,
  [string]$Output = '',
  [int]$Logs = 250,
  [int]$MaxPods = 50,
  [switch]$CollectSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info   { param($m) Write-Host ("INFO: " + $m) }
function Write-Ok     { param($m) Write-Host (([char]0x2713) + " " + $m) -ForegroundColor Green }
function Write-Warn   { param($m) Write-Warning $m }
function Write-Err    { param($m) Write-Error $m }

# Normalize domain (remove protocol, trailing slash, www.)
function Normalize-Domain {
  param([string]$d)
  $d = $d -replace '^https?://',''
  $d = $d.TrimEnd('/')
  $d = $d -replace '^www\.',''
  return $d
}

# Simple progress helper
class ProgressCounter {
  [int]$Total
  [int]$Current
  ProgressCounter([int]$t){ $this.Total = [Math]::Max(1,$t); $this.Current = 0 }
  [void]Step([string]$Activity){
    $this.Current++
    $p = [Math]::Min(100,[Math]::Floor(($this.Current / $this.Total) * 100))
    Write-Progress -Activity $Activity -Status "$($this.Current)/$($this.Total)" -PercentComplete $p
  }
  [void]Complete(){
    Write-Progress -Activity "Done" -Completed -Status "$($this.Total)/$($this.Total)"
  }
}

# Run a command safely and capture output to file
function Invoke-Safe {
  param(
    [Parameter(Mandatory=$true)][scriptblock]$Script,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [string]$Description = $(Split-Path -Path $OutFile -Leaf)
  )
  try {
    $parent = Split-Path -Path $OutFile -Parent
    if (!(Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $result = & $Script
    if ($null -eq $result) { 
      $result = "" 
    } elseif ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string])) {
      # Handle arrays and collections
      $result = @($result | ForEach-Object { if ($null -ne $_) { "$_" } }) -join "`r`n"
    } elseif ($result -is [System.Object[]]) {
      # Explicitly handle Object[] arrays
      $result = @($result | ForEach-Object { if ($null -ne $_) { "$_" } }) -join "`r`n"
    } else {
      # Convert to string for other types
      $result = "$result"
    }
    $result | Out-File -FilePath $OutFile -Encoding utf8
    Write-Ok $Description
  } catch {
    Write-Warn "$Description - failed: $($_.Exception.Message)"
  }
}

# Validate inputs
$Domain = Normalize-Domain $Domain
if ($Domain -notmatch '^[a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$') {
  throw "Invalid domain format: $Domain"
}
if ($Logs -lt 1) { throw "-Logs must be >= 1" }
if ($MaxPods -lt 1) { throw "-MaxPods must be >= 1" }

# Output directory
if ([string]::IsNullOrWhiteSpace($Output)) {
  $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
  $Output = "anomalo_diag_$timestamp"
}
Write-Info "Creating output directory: $Output"
New-Item -ItemType Directory -Force -Path $Output | Out-Null

# Directory structure
$dirs = @("$Output\logs", "$Output\configs", "$Output\system", "$Output\network", "$Output\metrics",
          "$Output\kubernetes\pods", "$Output\kubernetes\logs", "$Output\kubernetes\configs", "$Output\kubernetes\events")
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

# Tool checks
function Test-Binary { param([string]$Name) (Get-Command $Name -ErrorAction SilentlyContinue) -ne $null }
$missing = @()
if (-not (Test-Binary 'kubectl')) { $missing += 'kubectl' }
if ($missing.Count -gt 0) { throw "Missing required tools: $($missing -join ', ')" }

# Kubernetes diagnostics
function Assert-KubeAccess {
  param([string]$Ns)
  Write-Info "Checking kubectl connection and namespace access..."
  try { kubectl cluster-info | Out-Null } catch { throw "Cannot connect to Kubernetes cluster (`"kubectl cluster-info`")." }
  try { kubectl get namespace $Ns | Out-Null } catch { 
    $names = try { kubectl get namespaces --no-headers -o custom-columns=":metadata.name" } catch { @() }
    throw "Namespace '$Ns' not found or inaccessible. Available: $($names -join ', ')"
  }
  Write-Ok "kubectl connection and namespace verified"
}

function Gather-K8s {
  param([string]$Ns,[string]$Root,[int]$LogLines,[int]$MaxPods,[switch]$CollectSecrets)

  Write-Info "Gathering Kubernetes diagnostics for namespace: $Ns"

  # get pods/configmaps using JSON (avoid jsonpath escaping issues)
  $pods = @()
  try {
    $podsJson = kubectl get pods -n $Ns -o json
    if ($podsJson) {
      $items = (ConvertFrom-Json $podsJson).items
      if ($items) {
        $pods = @($items | ForEach-Object { if ($_.metadata.name) { $_.metadata.name } } | Where-Object { $_ -and $_.Trim() -ne '' })
      }
    }
  } catch { 
    $pods = @() 
  }
  if ($null -eq $pods) { $pods = @() }

  $configmaps = @()
  try {
    $cmsJson = kubectl get configmaps -n $Ns -o json
    if ($cmsJson) {
      $items = (ConvertFrom-Json $cmsJson).items
      if ($items) {
        $configmaps = @($items | ForEach-Object { if ($_.metadata.name) { $_.metadata.name } } | Where-Object { $_ -and $_.Trim() -ne '' })
      }
    }
  } catch { 
    $configmaps = @() 
  }
  if ($null -eq $configmaps) { $configmaps = @() }

  $toProcessPods = if ($pods) { $pods } else { @() }
  $podCount = if ($toProcessPods) { $toProcessPods.Count } else { 0 }
  if ($podCount -gt $MaxPods) {
    Write-Warn "Large deployment: $podCount pods found; limiting to first $MaxPods."
    $toProcessPods = $toProcessPods | Select-Object -First $MaxPods
  }

  $podCountEst = if ($toProcessPods) { $toProcessPods.Count } else { 0 }
  $cmCountEst = if ($configmaps) { $configmaps.Count } else { 0 }
  $est = 15 + $podCountEst + $cmCountEst
  $progress = [ProgressCounter]::new($est)

  Invoke-Safe { kubectl get all -n $Ns -o wide } "$Root\kubernetes\all_resources_${Ns}.txt" "All resources in $Ns"; $progress.Step("k8s")
  Invoke-Safe { kubectl get events -n $Ns --sort-by='.lastTimestamp' } "$Root\kubernetes\events\events_${Ns}.txt" "Events in $Ns"; $progress.Step("k8s")
  Invoke-Safe { kubectl get nodes -o wide } "$Root\system\nodes.txt" "Cluster nodes information"; $progress.Step("k8s")
  Invoke-Safe { kubectl top nodes } "$Root\metrics\node_metrics.txt" "Node metrics"; $progress.Step("k8s")

  foreach ($pod in $toProcessPods) {
    try {
      $phase = kubectl get pod $pod -n $Ns -o json | ConvertFrom-Json | Select-Object -ExpandProperty status | Select-Object -ExpandProperty phase
      if ($phase -ne 'Running') {
        Invoke-Safe { kubectl describe pod $pod -n $Ns } "$Root\kubernetes\pods\describe_${pod}.txt" "Describe pod $pod"
      } else {
        Invoke-Safe { kubectl logs $pod -n $Ns --all-containers=true --tail=$LogLines } "$Root\kubernetes\logs\logs_${pod}_last${LogLines}.txt" "Logs for pod $pod"
      }
    } catch {
      Write-Warn "Pod ${pod}: $($_.Exception.Message)"
    }
    $progress.Step("k8s")
  }

  Invoke-Safe { kubectl get deployments -n $Ns -o yaml } "$Root\kubernetes\configs\deployments_config_${Ns}.yaml" "Deployment configurations"; $progress.Step("k8s")
  Invoke-Safe { kubectl get services -n $Ns -o wide } "$Root\kubernetes\services_${Ns}.txt" "Services in $Ns"; $progress.Step("k8s")
  Invoke-Safe { kubectl get ingress -n $Ns -o wide } "$Root\kubernetes\ingress_${Ns}.txt" "Ingress in $Ns"; $progress.Step("k8s")
  Invoke-Safe { kubectl get pv,pvc -n $Ns } "$Root\kubernetes\storage_${Ns}.txt" "Storage in $Ns"; $progress.Step("k8s")

  # Names lists without jsonpath (and produce a single string)
  try {
    $items = (ConvertFrom-Json (kubectl get configmaps -n $Ns -o json)).items
    $names = @($items | ForEach-Object { $_.metadata.name } | Where-Object { $_ -and $_.Trim() -ne '' })
    $content = if ($names.Count -gt 0) { $names -join "`r`n" } else { "" }
    $parent = Split-Path -Path "$Root\kubernetes\configs\configmaps_${Ns}.txt" -Parent
    if (!(Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $content | Out-File -FilePath "$Root\kubernetes\configs\configmaps_${Ns}.txt" -Encoding utf8
    Write-Ok "ConfigMap names"
  } catch {
    Write-Warn "ConfigMap names - failed: $($_.Exception.Message)"
  }
  $progress.Step("k8s")

  try {
    $items = (ConvertFrom-Json (kubectl get secrets -n $Ns -o json)).items
    $names = @($items | ForEach-Object { $_.metadata.name } | Where-Object { $_ -and $_.Trim() -ne '' })
    $content = if ($names.Count -gt 0) { $names -join "`r`n" } else { "" }
    $parent = Split-Path -Path "$Root\kubernetes\configs\secrets_${Ns}.txt" -Parent
    if (!(Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $content | Out-File -FilePath "$Root\kubernetes\configs\secrets_${Ns}.txt" -Encoding utf8
    Write-Ok "Secret names"
  } catch {
    Write-Warn "Secret names - failed: $($_.Exception.Message)"
  }
  $progress.Step("k8s")

  # Collect all ConfigMaps
  Write-Info "Gathering all ConfigMap values..."
  foreach ($cm in $configmaps) {
    if ($cm -and $cm.Trim() -ne '') {
      try {
        $parent = Split-Path -Path "$Root\kubernetes\configs\${cm}_configmap.yaml" -Parent
        if (!(Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        kubectl get configmap $cm -n $Ns -o yaml | Out-File -FilePath "$Root\kubernetes\configs\${cm}_configmap.yaml" -Encoding utf8
        Write-Ok "ConfigMap $cm"
      } catch {
        Write-Warn "ConfigMap $cm - failed: $($_.Exception.Message)"
      }
      $progress.Step("k8s")
    }
  }

  if ($CollectSecrets) {
    $secret = 'anomalo-env-secrets'
    try {
      kubectl get secret $secret -n $Ns -o yaml | Out-File -FilePath "$Root\kubernetes\configs\${secret}_secret.yaml" -Encoding utf8
      Write-Warn "Collected values from Secret '$secret' (contains sensitive data)"
    } catch {
      Write-Info "Secret '$secret' not found in '$Ns'"
    }
    $progress.Step("k8s")
  }

  $progress.Complete()
  Write-Ok "Kubernetes diagnostics collected"
}

# Run
Assert-KubeAccess -Ns $Namespace
Gather-K8s -Ns $Namespace -Root $Output -LogLines $Logs -MaxPods $MaxPods -CollectSecrets:$CollectSecrets

# Metrics (health check)
$healthUrl = "https://$Domain/health_check?metrics=1"
Write-Info "Fetching health check metrics: $healthUrl"
try {
  Invoke-WebRequest -Uri $healthUrl -TimeoutSec 60 -UseBasicParsing -OutFile "$Output\metrics\health_check.json"
  Write-Ok "Fetched metrics"
} catch {
  Write-Warn "Failed to fetch metrics: $($_.Exception.Message)"
  '{}' | Out-File -FilePath "$Output\metrics\health_check.json" -Encoding utf8
}

# Summary
$summary = @()
$summary += "Anomalo Diagnostic Collection Summary"
$summary += "====================================="
$summary += "Collection Date: $(Get-Date)"
$summary += "Deployment Type: kubernetes"
$summary += "Base Domain: $Domain"
$summary += "Namespace: $Namespace"
$summary += "Output Directory: $Output"
$summary += "Files Collected:"
$files = Get-ChildItem -File -Recurse -Path $Output | Sort-Object FullName
foreach ($f in $files) { $summary += $f.FullName }
$summary | Out-File -FilePath "$Output\diagnostic_summary.txt" -Encoding utf8

# Zip
$fullOut = (Get-Item $Output).FullName
$zipPath = Join-Path -Path (Split-Path -Parent $fullOut) -ChildPath ("{0}.zip" -f (Split-Path -Leaf $fullOut))
Write-Info "Compressing diagnostic data to: $zipPath"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path $Output -DestinationPath $zipPath -Force
Write-Ok "Archive created: $zipPath"

Write-Host ""
Write-Host "================================================================"
Write-Host "✓ Diagnostic collection completed successfully!"
Write-Host "✓ Output file: $zipPath"
Write-Host ""
Write-Host "Please send the zip to Anomalo Support:"
Write-Host "  - Support Portal: https://anomalo.zendesk.com"
Write-Host "  - Email: support@anomalo.com"
Write-Host "================================================================"
