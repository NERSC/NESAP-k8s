# NERSC Metrics Scripts

This README links to the [NERSC Metrics Scripts](https://github.com/asnaylor/nersc-metrics-scripts) repository, which provides tools to monitor Slurm job metrics—enabling better resource utilization, performance troubleshooting, and system efficiency at NERSC.

## Key Features

- **Prometheus & Grafana Deployment:** Scripts to start Prometheus and Grafana for metrics collection and visualization.
- **Collectors:** Start node-exporter and DCGM collectors on target nodes to gather system and GPU metrics.
- **Prometheus Targets Generator:** Python script to generate Prometheus scrape target configurations dynamically.
- **Grafana Dashboard:** Pre-built dashboard template for visualizing Slurm job and system metrics.

For detailed instructions and usage, visit the [NERSC Metrics Scripts repository](https://github.com/asnaylor/nersc-metrics-scripts).

---

This page is a placeholder for a future Kubernetes integration, where these monitoring tools will be containerized and managed using Helm charts.