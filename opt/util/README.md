# Utility Functions To Help Manage `kubectl` and `helm` Installations

For up-to-date information, please refer to the
1. [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
2. [helm](https://helm.sh/docs/intro/install/)
documentation

The [`get_kubectl.sh`](get_kubectl.sh) and [`get_helm.sh`](get_helm.sh) scripts
automate this process. These have to be run [using the `entrypoint.sh`
script](../../README.md#use-the-entrypoint). For example:
```bash
# Enter ineractive mode
./entrypoint.sh bash
# Install kubectl and helm on an AMD64 linux machine
get_kubectl -n linux -a amd64
get_helm -n linux -a amd64
```
