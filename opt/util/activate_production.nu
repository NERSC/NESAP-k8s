module nesap-k8s {
    export-env {
        load-env {
            KUBECONFIG: $"($env.__PREFIX__)/opt/etc/production.yaml"
        }
    }
}

overlay use nesap-k8s
