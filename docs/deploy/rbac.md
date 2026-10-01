# Role Based Access Control (RBAC)

## Overview

This page describes the RBAC resources of an ingress-nginx-neo installation in a cluster with RBAC enabled. The
names below are those created by the Helm chart and the static manifests with the release name and namespace
`ingress-nginx-neo`.

Role Based Access Control is comprised of four layers:

1. `ClusterRole` - permissions assigned to a role that apply to an entire cluster
2. `ClusterRoleBinding` - binding a ClusterRole to a specific account
3. `Role` - permissions assigned to a role that apply to a specific namespace
4. `RoleBinding` - binding a Role to a specific account

In order for RBAC to be applied to the controller, the controller should be assigned to a `ServiceAccount`. That
`ServiceAccount` should be bound to the `Role`s and `ClusterRole`s defined for the controller.

## Service Accounts

One ServiceAccount is created for the controller, `ingress-nginx-neo`.

## Permissions Granted

There are two sets of permissions: cluster-wide permissions defined by the `ClusterRole` named
`ingress-nginx-neo`, and namespace specific permissions defined by the `Role` named `ingress-nginx-neo`.

### Cluster Permissions

These permissions are granted in order for the controller to be able to function as an ingress across the
cluster. These permissions are granted to the `ClusterRole` named `ingress-nginx-neo`:

* `configmaps`, `endpoints`, `nodes`, `pods`, `secrets`, `namespaces`: list, watch
* `nodes`: get
* `services`, `ingresses`, `ingressclasses`, `endpointslices`: get, list, watch
* `events`: create, patch
* `ingresses/status`: update
* `leases`: list, watch

### Namespace Permissions

These permissions are granted specific to the `ingress-nginx-neo` namespace. These permissions are granted to the
`Role` named `ingress-nginx-neo`:

* `namespaces`: get
* `configmaps`, `pods`, `secrets`, `endpoints`, `services`, `ingresses`, `ingressclasses`, `endpointslices`:
  get, list, watch
* `ingresses/status`: update
* `events`: create, patch

Furthermore, to support leader election, the controller needs access to a `leases` object with the resourceName
`ingress-nginx-neo-leader`:

> Note that resourceNames can NOT be used to limit requests using the “create”
> verb because authorizers only have access to information that can be obtained
> from the request URL, method, and headers (resource names in a “create” request
> are part of the request body).

* `leases`: get, update (for resourceName `ingress-nginx-neo-leader`)
* `leases`: create

This resourceName is the `--election-id` passed to the controller. The chart sets it to `<fullname>-leader`
(`ingress-nginx-neo-leader` for the default release name) and lets you override it with the value
`controller.electionID`. Without the flag, the controller binary uses `ingress-controller-leader`.

Please adapt the Role accordingly if you change the election ID.

### Bindings

The ServiceAccount `ingress-nginx-neo` is bound to the Role `ingress-nginx-neo` and the ClusterRole
`ingress-nginx-neo`.

The `serviceAccountName` of the controller pods must match the ServiceAccount. The namespace references in the
Deployment (or DaemonSet) metadata, the container arguments and `POD_NAMESPACE` must point to the
`ingress-nginx-neo` namespace.
