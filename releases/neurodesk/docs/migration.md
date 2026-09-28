# Migration

This page is the consolidated **omit/keep** reference for moving both
deployments onto the `neurodesk` chart, plus a safe rollout plan. For the
how-to detail, see [consuming-from-neurocloud.md](consuming-from-neurocloud.md)
and [consuming-from-devstack.md](consuming-from-devstack.md). Upgrading an
existing release from chart 0.1.x is covered in [0.1.x -> 0.2.0](#01x---020).

## The big picture

Both repos previously built the **same** JupyterHub + CVMFS + security stack by
hand — neurocloud as several ArgoCD apps, devstack as numbered scripts. This
chart factors that shared stack out once. After migration each repo:

- **omits** the pieces now provided by the chart, and
- **keeps** its infrastructure, secrets pipeline, and deployment-specific apps.

On an **existing** neurocloud cluster the chart first runs alongside the apps
that own SPO and CVMFS and reuses them; nothing is omitted until an ownership
transfer has been rehearsed (see below).

## neurocloud — two cases

neurocloud's `mounts` and `security` Argo CD apps own more than the notebook
layer: `mounts` owns the cluster-scoped CSIDriver `cvmfs.csi.cern.ch` and
StorageClass `cvmfs`; `security` owns the upstream SPO v1.0.0 install **and**
`charts/security` (neurocloud's AppArmor profile, the `neurocloud-spo-apparmor`
RBAC grant the operator needs, cryptnono and the DNS filter). So what the chart
replaces depends on the cluster:

| | (a) Fresh cluster (no `mounts`/`security` apps) | (b) Existing neurocloud cluster (adopt) |
| --- | --- | --- |
| Chart values | bundled defaults: `security.installOperator=true`, `cvmfs.enabled=true` | [`examples/neurocloud-values.yaml`](../examples/neurocloud-values.yaml): `security.installOperator=false`, `cvmfs.external=true`, profile name `neurodesk-notebook` |
| JupyterHub | the chart | the chart, in its **own** namespace / release / host, next to `charts/jupyter` |
| SPO operator, RBAC, CRDs | the chart | **kept** in the `security` app |
| CVMFS CSI driver + `cvmfs` StorageClass | the chart | **kept** in the `mounts` app |
| cryptnono, DNS filter | not in the chart | **kept** in the `security` app |

Both keep: ArgoCD (the app-of-apps engine); Longhorn → z2jh
`jupyterhub.hub.db.pvc.storageClassName` /
`jupyterhub.singleuser.storage.dynamic.storageClass` (hub DB + home PVCs) and
`global.storageClassName` for this chart's in-house PVCs; kube-prometheus-stack
→ `infra.monitoring.*`; `config/` + SOPS (secrets via `existingSecret`).

In (b) **no old app is removed**: pruning `security` or `mounts` would delete
the operator, RBAC and storage driver the chart reuses. Consolidating onto the
chart alone is a separate, **unrehearsed** ownership transfer — see step 6 of
the rollout plan. Details and the Argo CD `Application` are in
[consuming-from-neurocloud.md](consuming-from-neurocloud.md).

## ais-devstack — omit / keep

| Omit (now provided by the chart) | Keep (consumed by name or stays in repo) |
| --- | --- |
| JupyterHub install scripts (numbered steps `5` / `6` / `8` / `9`) | XNAT **server** + its plugins/jars |
| `cvmfs_mount` step | Longhorn (StorageClass) |
| squid script (→ `global.cvmfs.squidEnabled`) | **nfs-server** |
| security step (→ `security.*` + SPO) | Cleanup / teardown scripts |
| XNAT-upload notebook wiring (→ `xnat.enabled`) | The FUSE node-label step (still required) |

The omitted steps become **one** `helm install -f examples/devstack-values.yaml`
with `xnat.enabled=true`.

## What stays out of the chart entirely

Regardless of repo, these are **never** in the chart (infrastructure or
repo-specific policy):

- Longhorn, ArgoCD, the full Prometheus stack, nfs-server (infrastructure —
  consumed by name).
- cert-manager, unless you opt in with `cert-manager.enabled=true` on a cluster
  that has none (the bundled SPO needs it; both deployments already run it).
- The XNAT **server** and its server-side jars (stay in ais-devstack).
- cryptnono and the DNS filter (part of neurocloud's `security` app).
- Any secret material (lives in each repo's secrets pipeline).

## Rollout plan (per repo)

Do each repo on a branch, install alongside what runs today, and verify. For
neurocloud that means case (b) above; the final consolidation is a separate
plan (step 6).

1. **Branch.** Create a migration branch in the repo (neurocloud or devstack).
2. **Pin prerequisites.** Confirm the infra the chart needs is present:
   - a StorageClass — set hub DB / home PVCs on the z2jh keys
     `jupyterhub.hub.db.pvc.storageClassName` /
     `jupyterhub.singleuser.storage.dynamic.storageClass` (not
     `global.storageClassName`, which only covers this chart's own in-house PVCs),
     or rely on a cluster default,
   - the FUSE node label (`kubectl label node --all smarter-device-manager=enabled --overwrite`),
   - SPO handling — leave `security.installOperator=true` unless an SPO already
     runs (neurocloud: it does, in the `security` app). An existing SPO must be
     ≥ 1.0.0 to be reused (`installOperator=false`, with a profile name of its
     own); an older one (0.x, such as the neurodesk fork or devstack's
     `0.10.1-dev`) blocks the install — see [0.1.x -> 0.2.0](#01x---020),
   - CVMFS handling — leave `cvmfs.enabled=true` unless a CVMFS driver already
     runs (neurocloud: it does, in the `mounts` app); then use
     `cvmfs.external=true` and reuse it,
   - cert-manager, when `installOperator=true` (already running, or
     `cert-manager.enabled=true`),
   - Prometheus CRDs if you'll set `infra.monitoring.serviceMonitors=true`.
3. **Author the overlay.** Move auth/ingress/secrets and any deviations into the
   repo's overlay (`overlays/neurocloud-values.yaml` /
   `examples/devstack-values.yaml`). Keep secrets in SOPS/sealed-secrets, not in
   values. Remember the **subchart-boundary sync**: if you change
   `cvmfs.enabled` or `security.appArmor.profileName`, also edit the z2jh
   `jupyterhub.singleuser` block (see [architecture.md](architecture.md),
   [security.md](security.md), [cvmfs.md](cvmfs.md)).
4. **Install.**
   - neurocloud: add the ArgoCD `Application` for case (b) (pinned chart
     version, its own namespace and ingress host) and let it sync. The existing
     `charts/jupyter`, `mounts` and `security` apps keep running unchanged.
   - devstack: run the one `helm upgrade --install` in place of the numbered
     scripts, on a cluster where those scripts have not installed CVMFS or the
     old SPO (a cluster that already has the old SPO is refused — see
     [0.1.x -> 0.2.0](#01x---020)).
5. **Verify.**
   - `kubectl -n neurodesk get pods` — Hub and proxy healthy; plus cvmfs-csi,
     smarter-device-manager and (in `security-profiles-operator`) SPO when the
     chart installs them.
   - A test singleuser pod spawns, mounts `/cvmfs`, and the AppArmor profile is
     attached.
   - `cvmfs_mount_healthy` metric is present (if probe + monitoring on).
   - XNAT upload works from a notebook (if `xnat.enabled`).
6. **Consolidate (plan — not rehearsed).**
   - devstack: remove the numbered JH scripts + cvmfs_mount + squid + security
     + XNAT-upload wiring from the repo, so new devstack clusters use the chart.
   - neurocloud: retiring `charts/jupyter`, `mounts` and `security` requires an
     explicit **ownership transfer** of the SPO controller, its RBAC, the CRDs,
     the CVMFS storage-driver resources and the hub state to the chart
     **before** any old app is pruned. That procedure has not been rehearsed
     and is not published; until it is, stay on case (b) and do not delete or
     prune the old apps. cryptnono and the DNS filter live in the `security`
     app and need a home of their own before that app could ever go.
7. **Pin and merge.** Pin the chart version, update the repo's docs/runbook, and
   merge the branch.

Roll back by reverting the branch. In neurocloud case (b) nothing else changed,
so removing the new `Application` leaves the old apps as they were. Never run
two JupyterHub releases in the same namespace: z2jh's in-namespace names are
fixed.

## 0.1.x -> 0.2.0

Chart 0.2.0 replaces the bundled Security Profiles Operator. Read this before
running `helm upgrade` on a 0.1.x release.

### Breaking changes

1. **SPO: the neurodesk fork (`0.10.1-dev`) is gone.** The chart bundles
   upstream kubernetes-sigs SPO **1.0.0**, vendored with local patches
   (`vendor/security-profiles-operator/PROVENANCE.txt`). It is still bundled
   and on by default.
   - The operator now **always runs in namespace `security-profiles-operator`**
     (upstream 1.0.0 hard-codes it); in 0.1.x it ran in the release namespace.
     The release creates that namespace and keeps it on uninstall.
   - The profiles now use API `security-profiles-operator.x-k8s.io/v1` (the
     fork served `v1alpha1` AppArmorProfile and `v1beta1` SeccompProfile). They
     were already cluster-scoped under the fork; 0.2.0 only stops emitting a
     namespace on them. Their names are cluster-unique.
2. **cert-manager is required** when `security.installOperator=true`: already
   running in the cluster, or installed by the release with the new optional
   `cert-manager.enabled=true` (default `false`). 0.1.x docs said cert-manager
   was not needed; that is no longer true.
3. **External SPO (`installOperator=false`) must be ≥ 1.0.0.** SPO 0.x,
   including the neurodesk fork and AIS devstack's `0.10.1-dev`, is not
   compatible.
4. **The AppArmor profile is structured-only.** The fork's
   `spec.abstract.extra` raw rules do not exist upstream; the crypto-miner exec
   denylist that used them is dropped (see
   [security.md](security.md#what-the-apparmor-profile-allows) for what the
   profile allows and the suggested runtime-detection replacement).
5. **Notebook users: debuggers and tracers are blocked.** The 0.2.0 AppArmor
   profile does not allow ptrace between notebook processes; the fork profile
   did (`ptrace peer=notebook,`, another raw rule). `gdb` cannot run programs
   (`ptrace: Permission denied`), `PTRACE_TRACEME` / `PTRACE_ATTACH` fail with
   `EACCES`, and `strace`, `ltrace` or `py-spy` would fail the same way. SPO's
   structured API has no ptrace field; neurocloud runs this same profile. See
   [security.md](security.md#what-the-apparmor-profile-allows).
6. **Seccomp attach path** is `operator/<profileName>.json`. The 0.1.x docs
   gave `operator/<namespace>/<profileName>.json`, which does not fit a
   cluster-scoped profile; if you added a `seccompProfile` block to your
   overlay, check its path.
7. **Profiles always render when enabled.** `security.assumeCrdsPresent` now
   only skips the API discovery check for offline renders, and
   `validation.apparmorNoCrdProvider` has no effect.
8. **New render guards** (`templates/validate.yaml`): legacy-SPO detection,
   external-SPO API check, cert-manager check (`validation.certManagerMissing`),
   and values carried over from 0.1.x by `helm upgrade --reuse-values` (see
   below). An offline `helm template` with default values now fails until you
   assert cert-manager (`--api-versions cert-manager.io/v1/Certificate`) or set
   `cert-manager.enabled=true`.
9. **`xnat.uploadExtension.installerImage` was removed** and now fails the
   render. It never reached a manifest; set
   `jupyterhub.hub.extraEnv.XNAT_EXT_INSTALLER_IMAGE` instead.
10. **Bug fix — hub DB PVC StorageClass.** In 0.1.x the default
    `jupyterhub.hub.db.pvc.storageClassName: ""` rendered as an explicit empty
    class ("no StorageClass"), so on clusters relying on a default
    StorageClass the `hub-db-dir` PVC never bound and the Hub stayed
    `Pending`. 0.2.0 leaves the key unset (=> cluster default); fresh installs
    are unaffected. **A release upgraded in place** whose `hub-db-dir` PVC was
    created with that `""` must keep
    `jupyterhub.hub.db.pvc.storageClassName: ""` in its overlay for the
    upgrade: otherwise Helm's three-way merge tries to remove the field, and
    Kubernetes rejects changing a PVC's `storageClassName`. The alternative is
    to back up the hub state and recreate the PVC.
11. **`helm uninstall` runs a pre-delete cleanup hook** (`uninstallCleanup`,
    default on). It removes the profiles, the CVMFS probe and PVCs and the
    operator's runtime objects while their controllers still run, so the
    uninstall no longer hangs or strands them. It **refuses while any user
    server exists in the release namespace**: stop every server first, or the
    uninstall stops (before deleting anything) with the release in status
    `uninstalling`; either stop the servers and re-run the uninstall, or keep
    the release with `helm rollback <release> <revision marked uninstalling>`.
    **Pipelines that apply `helm template` output with `kubectl` must now add
    `--no-hooks`**, or the cleanup Job runs at install time. See
    [install.md](install.md#teardown--uninstall).
12. **z2jh 4.4.2** (was `~4.3.0`): removing a *named* server now also deletes
    its home PVC — see [xnat.md](xnat.md). The singleuser image moved to
    `ghcr.io/neurodesk/neurodesktop` (digest-pinned), and the Hub defaults
    changed (`consecutiveFailureLimit: 0`, `KubeSpawner.http_timeout: 120`,
    `singleuser.startTimeout: 600`). See [values.md](values.md).

### Which releases can upgrade in place

| 0.1.x release used | Upgrade |
| --- | --- |
| External SPO **≥ 1.0.0** (`installOperator=false`) | **In place.** Check the seccomp path (6 above), that the profile names are unique on the cluster, and keep `hub.db.pvc.storageClassName: ""` if the hub PVC was created with it (10 above). |
| External SPO **0.x** (`installOperator=false`) | Upgrade that SPO to ≥ 1.0.0 **first**; the chart refuses to render until the cluster serves the SPO `v1` API. Then upgrade the chart in place, as in the row above. |
| The **bundled** fork (`installOperator=true`, the 0.1.x default) | **Not in place.** See below. |

**Upgrade with your own values files, never `--reuse-values`.** Run
`helm upgrade … -f my-values.yaml` (or `--reset-then-reuse-values`). Across
0.1.x -> 0.2.0, `--reuse-values` renders the new templates with the old
release's values: the old notebook image, the old SPO fork image, the removed
`installerImage` key. The chart refuses that case with a message.

### A fresh 0.2.0 install on a cluster that ran 0.1.x

Uninstalling a 0.1.x release that bundled the fork leaves the fork's CRDs
behind (Helm never deletes `crds/`). They serve only the legacy API, so a
**fresh** 0.2.0 install on that cluster is refused (guard 5a). If **no other
SPO user** remains on the cluster, remove them with the CRD step of the full
SPO teardown in [install.md](install.md#3-what-remains-after-a-clean-uninstall-by-design):
deleting the CRDs deletes every profile of those kinds cluster-wide. If
anything else still uses SPO, do not delete them.

### Releases that bundled the fork: planned maintenance

A 0.1.x release that bundled the fork **cannot be upgraded in place**. Helm
never upgrades `crds/`, so the old CRDs would stay, the `v1` profile would not
apply, and the operator would move to another namespace. Guard 5a detects the
legacy API and stops `helm upgrade` **before Helm changes anything**, so an
attempted upgrade leaves the running release untouched.

Moving such a release to 0.2.0 is **planned maintenance**. The procedure is
**pending a dedicated rehearsal** and is not published yet. **Do not
improvise it**: stay on 0.1.x until the rehearsed procedure is available.
