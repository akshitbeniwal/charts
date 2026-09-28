# XNAT integration (optional)

The chart can wire notebooks up to an **XNAT** imaging server so users upload
data straight from JupyterLab. This is **off by default** (`xnat.enabled=false`)
and is purely the **notebook side** of the integration — the XNAT server itself
stays where it already lives, in **ais-devstack**.

## What the chart ships (notebook side)

When `xnat.enabled=true`, the in-house templates render:

| Object | Toggle | Purpose |
| --- | --- | --- |
| XNAT-upload **extension ConfigMap** | `xnat.uploadExtension.enabled` (default `true`) | Ships the JupyterLab XNAT-upload extension into singleuser pods; an init-container installs its deps; its image comes from `jupyterhub.hub.extraEnv.XNAT_EXT_INSTALLER_IMAGE` (the devstack overlay's hook defaults to `python:3.13-slim@sha256:7c61056e61ac89e852de05f3dc6fa51a6dd2181797bceed46aa725dd7cb2cd3b`; its Python minor must match the neurodesktop image's). |
| Singleuser **NetworkPolicy** | `xnat.enabled` | Allows singleuser pods egress to the XNAT server namespace (`xnat.server.namespace`), targeting `xnat.server.host`. |

```yaml
xnat:
  enabled: true
  server:
    host: xnat-web.ais-xnat.svc.cluster.local   # external/in-cluster XNAT
    namespace: ais-xnat                          # NetworkPolicy egress target
  uploadExtension:
    enabled: true
```

> **Named-server home PVCs are deleted on removal (z2jh ≥ 4.4).** This chart
> ships z2jh 4.4.2 (kubespawner 7.1.0). Since kubespawner 7.1.0 (#873), removing
> a *named* server also deletes its home PVC `claim-<user>--<server>`. The XNAT
> JupyterHub plugin stops servers with `DELETE /users/{user}/servers/{name}` and
> `{"remove": true}`, so each XNAT-launched server's home PVC is now deleted
> when XNAT stops it. Under z2jh 4.3.x those PVCs were orphaned and piled up
> (and are not cleaned up retroactively). To keep the old retain-forever
> behaviour set `jupyterhub.hub.config.KubeSpawner.delete_pvc: false` in your
> overlay; note that this also keeps a user's default-server PVC when the user
> is deleted.

## What stays in ais-devstack (server side)

The chart does **not** deploy any of:

- The **XNAT server** (`xnat-web`, its database, etc.).
- XNAT **server-side plugins / jars** (including the upload-extension's
  server-side counterpart).
- Any XNAT credentials or service accounts (those are secrets — see below and
  [secrets.md](secrets.md)).

Those remain part of the ais-devstack deployment. This chart only connects an
already-running XNAT to the notebooks.

## How to enable

1. Make sure an XNAT server is reachable from the cluster and note its in-cluster
   host + namespace.
2. Set the values:
   ```sh
   helm upgrade --install neurodesk . -n neurodesk \
     --set xnat.enabled=true \
     --set xnat.server.host=xnat-web.ais-xnat.svc.cluster.local \
     --set xnat.server.namespace=ais-xnat \
     -f examples/devstack-values.yaml
   ```
3. Pair it with the **XNAT JupyterHub overlay** so the spawner/auth side is wired
   too — this lives in `examples/devstack`. The overlay carries the
   `jupyterhub.hub.extraConfig` glue that the notebook extension expects.

## Secrets

XNAT integration needs credentials (a service **apiToken**, and on the server
side **CryptKeeper** keys). **Never** put these in `values.yaml`. Provide them
via an `existingSecret` / sealed-secrets / SOPS, and reference them from your
overlay. The full list is in [secrets.md](secrets.md).

## The `examples/devstack` overlay

ais-devstack consumes this chart with `xnat.enabled=true` plus its
`examples/devstack-values.yaml` overlay, which together replace the repo's
hand-rolled XNAT-upload wiring. See
[consuming-from-devstack.md](consuming-from-devstack.md) for the full picture of
what devstack keeps (the XNAT server + jars) versus what this chart now provides
(the notebook-side extension ConfigMap + NetworkPolicy).
