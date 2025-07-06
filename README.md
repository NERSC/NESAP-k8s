# Some Kubectl and Helm Examples for Superfacility Projects

**Note:** These are beta projects, use at your own discretion

## Related Work

1. [Andrew Naylor's](https://github.com/asnaylor) user-space prometheus-based
   [Workflow Monitoring Toolchain](https://github.com/asnaylor/nersc-metrics-scripts)


## Getting Started

Before installing Helm Charts, you will need:

1. Have a valid install of `kubectl` and `helm` -- we provide [helper
   scripts](opt/util) that will download these to `opt/bin`;
3. [Obtain the `kubeconfig`](#download-KUBECONFIG) from the Spin cluster where
   your project runs (either the "development" or "production" cluster).
Remeber to [use the entrypoint script](#use-the-entrypoint) when running the
scripts in this project.

### Use the Entrypoint

We want to ensure that the scripts have have predictable behavior, regardless of
the execution context (e.g. where scripts are being run from). Bash kinda sucks
at this (especially when handling relative paths) -- an imperfect (but
acceptable) solution is to use a launcher script:
[entrypoint.sh](./entrypoint.sh) which takes the command to run as its
arguments. This can be run either as a standalone script, or in interactive
mode.

`entrypoint.sh` sets two environment variables `__PREFIX__`, and `__DIR__`:
* `__PREFIX__` contains the location of the project root (i.e. where
`entrypoint.sh` is saved)
* `__DIR__` contains the location of he script being run

#### Standalone Mode

Standalone mode is invoked by passing the path to the script you want to run
(relative the `entrypoint.sh`) as its arguments
```
./entrypoint.sh opt/util/get_kubectl.sh -n linux -a amd64 
```

#### Interactive Mode

Interactive mode is invoked whenever the command passed to `entrypoint.sh` is
not a script in this project (i.e.the absolute path does not start with
`$__PREFIX__`). Most often this is used to launch a shell:
```
./entrypoint.sh bash
```
This would drop you into a shell containing `__PREFIX__` (note that `__DIR__`
will have the same value as `__PREFIX__`).

[!NOTE]
> In interactive mode `$__PREFIX__/opt/bin:$__PREFIX__/opt/util` are appended to
> `PATH`

### Download `KUBECONFIG`

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

#### (Optional) Create `KUBECONFIG`secret

Using `kubectl`, create a `kubeconfig` secret in the targeted namespace
(replace `<targeted_namespace>` and `<path to kubeconfig>` accordingly):

```bash
kubectl -n <targeted_namespace> create secret generic kubeconfig --from-file=kubeconfig=<path to kubeconfig>
```

## Create a new namespace in Spin

[This guide](namespace/README.md) describes how to create namespaces on Spin.

