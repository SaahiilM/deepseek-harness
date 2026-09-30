# Agent Note: Use the tokenized Web URL in the native shell

Status: implemented

English | [中文](2026-09-18-native-shell-browser-auth.zh.md)

## Problem

The Web Host requires a launch-token exchange before it serves the application document and API. The native shell waited for the loopback listener, then loaded its bare port URL, so the standalone app displayed the Host's 401 message even though the server had printed an authenticated URL.

## Decision

Owned native-shell servers capture the tokenized URL printed by `dsh web`, wait for that URL after HTTP readiness, and publish it as the running URL. `WKWebView` follows the redirect, stores the authority-bound cookie, and then loads the authenticated application. A bare or missing launch URL is rejected during startup instead of being exposed as a misleading 401 page.

The Web Host's browser-authentication policy remains unchanged. The shell continues to use the server's existing process output and does not add an unauthenticated loopback exception or a second authentication protocol.

## Alternatives considered

**Load the bare loopback URL.** The Web Host correctly rejects it, which is the failure this decision fixes.

**Disable browser authentication for native loopback clients.** This would weaken the shared Web Host policy and create a native-only exception.

**Add a separate token IPC endpoint.** A second credential-delivery channel would duplicate the launch URL already emitted by the Web runner and expand the native protocol.

## Consequences

Standalone and checkout-backed native launches now complete the same browser-authentication exchange as `dsh web`. The shell test suite pins token URL extraction and rejects bare URLs. If a server does not report a tokenized URL, the shell fails loudly with its captured diagnostics.
