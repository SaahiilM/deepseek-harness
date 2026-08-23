# Agent Note: `--directory-picker` pins the directory-picker interaction from the launch flags

Status: implemented

English | [中文](2026-08-23-directory-picker-pin-flag.zh.md)

> Scope: the `dsh --profile web` flag family and the `dsh-host-directory-picker-auto` composition config. The capability seam, both backends, and the `-auto` resolution function are unchanged; this records the landing of the pin channel the [adaptive-default note](2026-07-29-directory-picker-adaptive-default.md) reserved for "a deployment needs to force a backend without editing its yml".

## Problem

`-auto` resolves the interaction from boot facts (loopback bind, no SSH, an attended display) — correct for deployments whose operator sits at the host. A new deployment shape appeared: one server serving both the local browser and remote phones through a pairing gate. The boot facts cannot see client surfaces, so `native` resolved and mounted — and on a remote surface, "create workspace" drove `host.pickDirectory`, opening the OS dialog on the unattended host screen while the remote operator faced a permanently busy flow. [Per-connection adaptivity](../architecture/2026-07-28-directory-picker-capability-seam.md) remains explicitly deferred; the deployment needed to force a backend now, without editing its yml.

## Decision

One sentence: **the web startup family gains `--directory-picker <auto|native|browse>`; the value reaches the chooser row's `pin` config through the `webStartup.directoryPicker` service, and a pinned chooser skips fact sampling and mounts that backend + surface pair directly.**

Concretely:

- `directory-picker-auto` gains an optional schemastery-validated `Config.pin`; unpinned behavior is bit-identical.
- The bundle's chooser row feeds the pin with `inject: [webStartup]` plus lazy `!!js ctx.webStartup.directoryPicker` — the same channel as every other flag-driven row; row-level inject merges with the plugin's declared inject (`Inject.resolve` fills a name map), it does not replace.
- `auto` is absorbed to an absent value in the provider, so the service carries the field only when explicitly pinned.

## Alternatives considered

- Composing a `-browse` row directly in this deployment's overlay: works, but bakes the choice into static composition; the flag lets one tree answer different deployments per launch, and it is exactly the reintroduction shape the adaptive-default note reserved.
- Resurrecting the wire capability advertisement so each client branches locally (per-connection adaptivity): still requires dual-flow mounting and a redesign of the `single` hole semantics; the pin already serves this deployment.

## Consequences

- The desktop shell starts its owned servers with `--directory-picker browse`: workspace creation runs the in-app host-filesystem browser on every surface; OS-dialog deployments keep relying on auto or composing `-native` directly.
- Resolution still happens exactly once per boot; the seam's capability-stability contract stands.
