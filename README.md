# Anomalo Diagnostics

This repository contains diagnostic tools for Anomalo.

## Kubernetes

If your Anomalo installation is running in Kubernetes, you can use the following commands to diagnose issues with your Customer Success team.

### Usage

```
curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.sh -o generate-diag.sh && chmod +x generate-diag.sh && ./generate-diag.sh
```

Will generate a zip of diagnostic information in the current directory.