module nesap-k8s {
    export-env {
        load-env {
            KUBECONFIG: $"($env.__PREFIX__)/opt/etc/development.yaml"
        }
    }
}

overlay use nesap-k8s
