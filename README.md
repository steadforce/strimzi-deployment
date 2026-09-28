# Strimzi Deployment

Umbrella Helm chart that packages and configures the [Strimzi](https://strimzi.io/) Kafka operator.

> [!IMPORTANT]
> Never install the content of this repository on our clusters manually. This is all done by Argo CD.

## Overview

- Deploys the `strimzi-kafka-operator` chart, pinned in `Chart.yaml` and `Chart.lock`, and committed as an archive
  in `charts/`.
- Ships the Strimzi CRDs as templates, annotated for server-side apply, see
  [Argo CD Sync Mitigation](#argo-cd-sync-mitigation).
- Renders a `Namespace` for the release namespace.
- Renders a Chaos Mesh `Schedule` that kills one `strimzi-cluster-operator` pod at minute 57 of every hour, when the
  cluster provides the `chaos-mesh.org/v1alpha1` `Schedule` API.

## Prerequisites

Commands below run in the `SteadOps-Steadies-K8s-Workplace` workbench, which ships `helm`, `yq`, `kubectl`,
`hetzner-k3s`, and `act`. Rendering, testing, and the CRD update also have a containerized alternative that only
needs Docker.

## Repository Layout

| File / Directory | Purpose |
| --- | --- |
| `Chart.yaml` | Declares the `strimzi-kafka-operator` chart dependency of this umbrella chart. |
| `Chart.lock` | Pins the resolved dependency version. |
| `charts/` | The committed `strimzi-kafka-operator` chart archive, so no dependency setup is needed after cloning. |
| `values-subchart-overrides.yaml` | Overrides for the `strimzi-kafka-operator` chart, see [Testing](#testing). |
| `values-local.yaml` | Single replica and zero CPU settings for the local cluster. |
| `templates/` | The namespace, the Chaos Mesh schedule, and the generated `*-crd.yaml` CRDs. |
| `update-crds.sh` | Regenerates the CRD templates from the dependency. |
| `tests/` | Helm unittest suites for the operator deployment and the Chaos Mesh schedule. |
| `renovate.json` | Renovate configuration. |

## Argo CD Sync Mitigation

This works around an [Argo CD issue](https://github.com/argoproj/argo-cd/issues/13320): the dependent chart contains
CRDs bigger than 256KiB. This means that they can't be installed directly from Argo CD. To mitigate this we have to
add the `argocd.argoproj.io/sync-options: ServerSideApply=true` annotation to let Argo CD apply these resources on the
server side.

The addition is done with the script `update-crds.sh`. It renders the chart with `--include-crds`, adds the
annotation to every `CustomResourceDefinition` with `yq`, and writes each CRD to `templates/<name>-crd.yaml`, after
removing the existing CRD templates.

On deployment, the dependent chart CRDs have to be switched off. When using Helm this is the default case, but not
for Argo CD. It has to be ensured that the Helm CRD rendering is turned off in the application:

```yaml
spec:
  source:
    helm:
      skipCrds: true
```

> [!IMPORTANT]
> Update the CRDs every time the dependency is updated. On Renovate branches, the `Helm update CRDs CI` workflow does
> this automatically, see [CI/CD](#cicd).

To update the CRDs by hand, in the workbench, from the repository root:

```sh
 ./update-crds.sh
```

Without the workbench:

```sh
 docker run \
   -e HOME=/tmp \
   --entrypoint ./update-crds.sh \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm
```

## Rendering

All commands run from the repository root. Render the local manifests into the git-ignored `_local/local/`
directory, with the same value files as the local unittest cases.

In the workbench:

```sh
 helm template \
   -a chaos-mesh.org/v1alpha1/Schedule \
   -f values-subchart-overrides.yaml \
   -f values-local.yaml \
   -n strimzi-operator \
   --output-dir _local/local \
   --skip-tests \
   strimzi-operator \
   .
```

Without the workbench:

```sh
 docker run \
   -e HOME=/tmp \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm template \
   -a chaos-mesh.org/v1alpha1/Schedule \
   -f values-subchart-overrides.yaml \
   -f values-local.yaml \
   -n strimzi-operator \
   --output-dir _local/local \
   --skip-tests \
   strimzi-operator \
   .
```

> [!NOTE]
> These commands leave out `--include-crds` on purpose: the CRDs are already part of `templates/`, and Argo CD
> skips the CRDs of the dependency.

## Testing

The `values-subchart-overrides.yaml` file is used to override values in the `strimzi-kafka-operator` chart. We have
to separate the values for the subcharts from the values for the main chart, to be able to unit test for
incompatible changes in values of the subcharts. This is necessary because Helm does not allow switching off the
usage of `values.yaml`. Now it's possible to test if we use the same registry and repository for images as the
subcharts are using.

Run the Helm unittest suites:

```sh
 docker run \
   -e HELM_CACHE_HOME=/tmp/helm/.config \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   helmunittest/helm-unittest \
   .
```

> [!TIP]
> Add `-t JUnit -o test-output.xml` after `helmunittest/helm-unittest` to also write a JUnit report, as the pipeline
> does. Without `-t`, helm-unittest writes the report in XUnit format.

## Install Strimzi in the SteadOps Workplace

Simply enable the Strimzi operator in the Argo CD root application on your locally running Kubernetes cluster by
setting the parameter `enableStrimziOperator` to `true`, and wait a bit until Argo CD has done its job.

## CI/CD

- `helm-unittest.yaml` runs on every push and calls the reusable `helm-unittest.yaml` workflow of
  [`steadforce/steadops-workflows`](https://github.com/steadforce/steadops-workflows), pinned to `v4.2.0`. It
  installs the dependency pinned in `Chart.lock`, runs the helm-unittest suites including subchart tests,
  publishes a JUnit test report, and runs `helm lint`.
- `renovate-update-crds.yaml` runs on pushes to `renovate/*` branches. It runs `update-crds.sh` with a pinned Helm
  version and, when the CRD templates changed, commits and pushes them to the Renovate branch.
- `trufflehog.yaml` calls the reusable `trufflehog-oss.yaml` workflow, pinned to `v4.2.0`, and scans the commits
  of pushes and pull requests to `main`, and runs on demand, for leaked secrets.

### Microsoft Teams Notifications

On branches starting with `renovate/`, the unittest workflow posts its result to Microsoft Teams:

| Result | Repository Secret |
| --- | --- |
| Success | `STEADOPS_HELM_RENOVATION_MS_TEAMS_WEBHOOK` |
| Failure | `STEADOPS_HELM_RENOVATION_ERROR_MS_TEAMS_WEBHOOK`, a separate error channel |

Both secrets are optional and hold a Microsoft Teams Workflows webhook URL. When the error webhook is not set,
failures go to `STEADOPS_HELM_RENOVATION_MS_TEAMS_WEBHOOK` instead. Without either secret, no notification is sent.

### Run the Pipeline Locally

To run the pipeline in the local environment, start up the workbench, cd into the folder containing this
`README.md`, and execute the following command:

```sh
 act
```

On first execution you're asked which flavour of the act image should be used. Using the default `medium` is a
good starting point. Under `act`, the CRD workflow only reports the changes instead of committing them, and the
unittest workflow skips publishing test results and Teams notifications.

## Dependency Updates

Renovate keeps the dependencies up to date, as configured in `renovate.json`:

- Patch updates of all dependencies are automerged with a squash commit. Minor and major updates, including those
  of the `strimzi-kafka-operator` chart, need a manual merge.
- GitHub Actions updates, including `steadforce/steadops-workflows`, are automerged for all update types.
- With the `helmUpdateSubChartArchives` post-update option, a chart update also replaces the archive in `charts/`.

When changing the `strimzi-kafka-operator` version in `Chart.yaml` by hand, update `Chart.lock` and the archive in
`charts/`, [update the CRDs](#argo-cd-sync-mitigation), and commit everything together with `Chart.yaml`. See the
[Helm docs](https://helm.sh/docs/topics/charts/#chart-dependencies) for details.

In the workbench:

```sh
 helm dependency update .
```

Without the workbench:

```sh
 docker run \
   -e HOME=/tmp \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm dependency update .
```
