# strimzi-deployment
Repository containing manifests for strimzi installation. Never install the content of
this repo on our clusters manually. This is all done by argo-cd.

## Dependencies

This chart pulls in `strimzi-operator` as a dependency. The version
used is specified in `Chart.yaml` in the `dependencies` section.
If you change the version in there, you need to then run

    $ helm dependency update

in order to have the chart downloaded to the `charts` directory
and then also commit that new version alongside with the altered
`Chart.yaml` file.

See the [Helm docs](https://helm.sh/docs/topics/charts/#chart-dependencies)
for details.

## Argo-cd sync-wave mitigation for [issue](https://github.com/argoproj/argo-cd/issues/13320)
The dependent chart contains crds bigger than 256KiB. This means that they
can't be installed directly from argo-cd. To mitigate this we have to add
the `argocd.argoproj.io/sync-options: ServerSideApply=true` annotation
to let argo-cd apply these resources on the server side.

The addition is done with the little script `update-crds.sh`. This script reads
in the crds from dependent charts and adds the needed annotation with `yq` and
places the crds into the `templates` directory.

On deployment, the dependent chart crds have to be switched off. When using helm
this is the default case, but not for argo-cd. It has to be ensured that the helm
crd rendering is turned off in the application.

```yaml
spec:
  source:
    helm:
      skipCrds: true
```
**ATTENTION** update the crds everytime when the dependency is updated.

# Testing

## values-subchart-overrides.yaml

The `values-subchart-overrides.yaml` file is used to override values in the postgres-operator chart.
We have to separate the values for the subcharts from the values for the main chart, to be able to
unit test for incompatible changes in values of the subcharts. This is necessary because helm does not allow
switching off the usage of values.yaml. Now it's possible to test if we use the same registry and repository
for images as the subcharts are using.

## run helm unittests

```shell
 docker run --pull=always -ti --rm -v "$(pwd):/apps" -u $(id -u) helmunittest/helm-unittest .
```

Or with output in JUnit format:

```shell
 docker run --pull=always -ti --rm -v "$(pwd):/apps" -u $(id -u) helmunittest/helm-unittest -o test-output.xml .
```

## Render resource local

```
  helm template \
  --output-dir _local/local \
  --release-name strimzi-operator \
  --skip-tests \
  -a batch/v1/CronJob \
  -a chaos-mesh.org/v1alpha1/Schedule \
  -f values-local.yaml \
  -n strimzi-operator \
  .
```

# Install strimzi in Steadops Workplace

Simply enable the strimzi operator in argo-cd root-application on your local
running k8s cluster by setting the parameter `enableStrimziOperator` to `true` and wait
a bit until argo-cd has done his job.

## Run act pipeline locally

To run the pipeline in local environment, start up the workbench, cd into the folder containing this
`README.md` and execute the following command:

```shell
  act
```

On first execution you're asked which flavour of the act image should be used. Using the default `medium`
is a good starting point.
