# Helm Chart for automatically renewing TLS certificate

This a helm chart for obtaining and automatically renewing TLS certificate on the NERSC spin platform.

This helm chart automates the steps described in the repository [dingpf/acme](https://github.com/dingp/acme).

## Install the helm chart

This helm chart takes consideration of two different usage cases. The installation procedure is different.

### Case 1

In this case, the following conditions must be met:

1. The namespace already has a running web server;
2. The web server has its web root on a shared persistent volume;
3. The ingress is not defined for the web server, if so, delete it first;
4. you have a CNAME record points to `<ingress>.<namespace>.<cluster>.svc.spin.nersc.gov`.

#### Clone the repo

Clone this repository with `git clone https://github.com/NERSC/spin-helm.git`. Move into the
`tls-acme` directory with `cd tls-acme`.

The directory tree looks like the following:

```bash
tls-acme
├── charts
├── Chart.yaml
├── README.md
├── templates
│   ├── certsecret.yaml
│   ├── cronjob.yaml
│   ├── _helpers.tpl
│   ├── ingress.yaml
│   ├── service.yaml
│   ├── webpvc.yaml
│   └── websrv.yaml
└── values.yaml

2 directories, 10 files
```

#### Customize values for chart installation

Make a copy of `values.yaml`, and modify it by setting:

- `<uid>`
- `<gid>`
- `<domain>`
- `<email>`
- `<port>`
- `<ingress_name>`
- `<cluster>` (can be `development.svc.spin.nersc.org` or `production.svc.spin.nersc.org`)
- `existing-websrv`
- `pvc-existing-webroot`
- change `webServer.existing` field from `false` to `true`

#### Install the chart

Install the helm chart with the following command. Replace `<namespace>` with your namespace. `acmecron` is a release name for which you can name your own.

```bash
helm install -n <namespace> -f modified-values.yaml acmecron ./spin-acme
```

#### Inspect the installation

The results of this installation are:

1. A self-generated TLS certificate saved into a secret named `tls-cert`;
2. A new ingress in the namespace, with rules for each of the domains, including the default Spin domain, pointing to the existing web server and its http port; the ingress will also use the self-generated certificate for all the domains;
3. A cronjob which runs every two months to reuqest/renew a TLS certificate, and repalce the self-generated TLS certificate with it. The requested certificate will include all the listed domains in the ingress.

#### Post installation setup (1)

Once the chart is installed, you can trigger the cronjob manually once to request and use the initial certificate. To trigger the cronjob, you can use the webUI, select "Workloads" -> "CronJobs", click the three dots beside the cronjob, and choose "Run Now".

Alternatively, you can trigger the CronJob via `kubectl`.

```bash
# get the cronjob name
kubectl get cronjob -n <namespace>
# replace cronjob_name, and job_name below
kubectl create job -n <namespace> --from=cronjob/<cronjob_name> <job_name>
```

It is recommended to "View Logs" while the triggered job is running, and verify the procedure is completed successfully.

### Case 2

This case requires the followings conditions to be met:

1. There is no web server running in the namespace;
2. Or there is a running web server, but there's no write access to the running webserver's web root directory;
3. The ingress is not defined for the web server, if so, delete it first, assuming the ingress will be named `myingress`;
4. you have a CNAME record points to `myingress.mynamespace.development.svc.spin.nersc.gov`.

This is applicatable to the usage cases like:

1. You are running web service which does not have a writable web root directory, e.g. a REST API server;
2. You have a web server, but serving a read-only directory (e.g. a directory mounted from CFS).

#### Installation and inspection

Similar as _Case 1_ above, but change the following in the copied `values.yaml`:

- `<uid>`
- `<gid>`
- `<domain>`
- `<email>`
- `<port>` to `8080`
- `<ingress_name>`
- `<cluster>` (can be `development.svc.spin.nersc.org` or `production.svc.spin.nersc.org`)

Different than _Case 1_, this installation of the chart will result in:

1. A deployment of a simple web server, running on port 8080 internally;
2. A new ingress in the namespace, pointing all of the domains, including the default Spin domain, to the newly created web server and its port 8080.

#### Post installation setup (2)

Follow instructions in Case 1 to trigger the initial run of the cronjob, view logs while it's running, and verify the initial request is completed successfully. Same as in Case 1, once the TLS certificate is obtained, it will replace original self-generated certificate.

At this point, you will need to modify the ingress to point it to your API server, or your existing web server (for which we didn't have write access to its webroot).

During, the future cronjob runs, your modified ingress will be saved first, changed briefly to the simple web server's port 8080, restored back once the certificate is renewed.

### Upgrade or uninstall the chart

If you made changes to `values.yml`, you can `upgrade` the installed chart by:

```bash
helm upgrade -n <namespace> -f modified-values.yaml <release-name> ./spin-acme
```

Note the `<release-name>` should be the same one you used during initial installation. In the Case 2, if you've made modifications to the ingress after the initial Cronjob run, the modifications will be lost after upgrade, and will need to be re-applied. It's recommended that you backup the YAML for the ingress before the upgrade.

In case you want to uninstall the chart, you can do so by:

```bash
helm uninstall --namespace <namespace> <release-name>
```

Similarly, the `<release-name>` should be the same one you used during initial installation.

After the uninstallation, the ingress, cronjob, web server, PVC etc will all be removed from the namespace, except the TLS secret.

## Support Information

You can [make a 30-minute appointment](https://docs.nersc.gov/getting-started/#appointments-with-nersc-user-support-staff) during NERSC's weekly Spin office hours for assistance with setting up TLS certificate issuing/renewing for your workload.
