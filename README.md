# Some Kubectl and Helm Examples for Superfacility Projects

**Note:** These are beta projects, use at your own discretion

## Related Work

1. [Andrew Naylor's](https://github.com/asnaylor) user-space prometheus-based
   [Workflow Monitoring Toolchain](https://github.com/asnaylor/nersc-metrics-scripts)

## Before you start

Before installing Helm Charts, you will need:

1. an existing or a new namespace of a Spin project;
2. install `kubectl` and `helm`;
3. obtain the `kubeconfig` from the Spin cluster where your project runs
   (either the "development" or "production" cluster).

## Create a new namespace in Spin

[This guide](namespace/README.md) describes how to create namespaces on Spin.

## Install `kubectl`

For up-to-date information, please refer to the [official
documentation](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/).

1. Obtain `kubectl` via `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl`;
2. Set the downloaded `kubectl` to be executable (`chmod +x kubectl`);
3. move `kubectl` to its desired destination (e.g. `mv kubectl
   $HOME/bin/kubectl`);
4. parent directory of `kubectl` should be include in your `PATH` environment
   variable, add it if needed (e.g. `export PATH=$HOME/bin:$PATH`)

## Install `helm`

For up-to-date information, please refer to the [official
documentation](https://helm.sh/docs/intro/install/).

1. Download your [desired version](https://github.com/helm/helm/releases)
2. Unpack it (e.g. `tar -zxvf helm-v3.0.0-linux-amd64.tar.gz`)
3. Find the helm binary in the unpacked directory, and move it to its desired
   destination (e.g. `mv linux-amd64/helm $HOME/bin/helm`);
4. parent directory of `helm` should be include in your `PATH` environment
   variable, add it if needed (e.g. `export PATH=$HOME/bin:$PATH`)

## Download `KUBECONFIG`

KUBECONFIG is a YAML file containing the deteails of the k8s cluster, such as
its address, and your own authentication credentials. It can be downloaded from
the Spin.

1. Login to rancher2.spin.nersc.gov;
2. click the cluster name (as of May 12, 2024, either "development" or
   "production");
3. hover the mouse pointer over the "page" icon on the top right of the page,
   it should say "Download KubeConfig", click it to download.
4. create `$HOME/.kube` directory if not existing, and save the downloaded file
   to `$HOME/.kube/config`; alternatively, you can set the `KUBECONFIG`
environment variable to the path to the downloaded YAML file.

## Create `KUBECONFIG`secret

Using `kubectl`, create a `kubeconfig` secret in the targeted namespace
(replace `<targeted_namespace>` and `<path to kubeconfig>` accordingly):

```bash
kubectl -n <targeted_namespace> create secret generic kubeconfig --from-file=kubeconfig=<path to kubeconfig>
```


