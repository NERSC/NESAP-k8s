# Creating a Namespave

## Using the Rancher2 Web GUI

1. Login to rancher2.spin.nersc.gov;
2. Click the cluster name (as of May 12, 2024, either "development" or
   "production");
3. Click "Project/Namespaces" on the sidebar, click "Create Namespace" beside
   your chosen project.

## Using the `kubectl` templates

First we need the Rancher project ID corresponding to the NERSC project with
which you would like to associate your namespace. The easiest way to get this is
to already have another namespace (e.g. by following the instructions above),
and running:
```
kubectl get namespace <namespace name> -o json | jq '.metadata.annotations["field.cattle.io/projectId"]'
```
you should see something like: `c-frj56:p-gg9pb` -- split that into two parts:
`<part 1>:<part 2>` and add those to `racher_pid_1` and `rancher_pid_2` below.

1. Make a copy of `settings_example.toml` and call it `settings.toml`;
2. Fill in `settings.toml`, you should have something like:
```toml
[constant]
rancher_pid_1 = "c-frj56"
rancher_pid_2 = "p-gg9pb"

[zip]
name = "my-namespace"
```
(assuming your rancher project ID was `c-frj56:p-gg9pb`). Note: you can generate
the specs for many templates at once by specifying a vector of names, for
example:
```toml
... constant fields

[zip]
name = ["my-namespace-1", "my-namespace-2", "my-namespace-3"]
```
3. Run `../entrypoint.sh namespace/render.sh` (or just `./render.sh` if in
   interactive mode). You should now see a folder called `rendered` containing a
   .yaml spec for each of your namespaces
4. For each .yaml file in `rendered` run:
   `kubectl apply -f <namespace name>.yaml`

### A Note on Using Nushell

[Nushell](https://www.nushell.sh/) provides a powerful way to parse formatted
output. For example, instead of using the `jq` command above, you can get the
rancher project ID using Nushell's native yaml (and json) support:
```
kubectl get namespace <namespace name> -o json | from json | get metadata.annotations.'field.cattle.io/projectId'
```
