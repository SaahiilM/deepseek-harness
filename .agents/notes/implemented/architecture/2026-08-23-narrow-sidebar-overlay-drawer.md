# Agent Note: Narrow-viewport sidebar as an overlay drawer

Status: implemented

English | [中文](2026-08-23-narrow-sidebar-overlay-drawer.zh.md)

> Scope: `ui-layout` only — how the AppFrame renders the auto-collapsed sidebar when it is re-expanded below the breakpoint (`SIDEBAR_AUTO_COLLAPSE`, 1024px), and what dismisses it. The concession chain, wide-layout drag handles, and store preference semantics are unchanged.

## Problem

The narrow re-expand previously kept the sidebar in its grid track: expanding over a phone-width viewport (375–430px) squeezed the conversation column to a sliver, which made the web UI unusable as a touch-first surface. Touch input also inherited desktop-only affordances: pointer-drag resize strips sat across touch scroll paths, and nothing dismissed the expanded panel once a thread was opened.

## Decision

One sentence: **below the breakpoint, an expanded sidebar is an overlay drawer — the solver still resolves the full sidebar width, but the frame zeroes the sidebar grid track, pins the column absolutely over the full-width center behind the overlay layer, and renders a scrim whose tap closes it.**

Concretely:

- The layout store gains one action, `closeNarrowSidebar` (drop `narrowExpanded` only; no-op while wide). Toggle parity, width preferences, and the `setNarrow` override reset are untouched.
- AppFrame derives `drawerOpen = narrow && !sidebarCollapsed`. In drawer mode the inline grid template uses a zero first track and the sidebar column gets `data-drawer-open` plus an explicit pixel width; CSS positions it absolutely with a border and shadow. Owner params for the `'sidebar'` slot are unchanged (`collapsed: false`, full width), so sidebar registrants cannot tell drawer mode from wide mode.
- Selecting a *different* Session while the drawer is open closes it before paint (same guard-ref pattern as details auto-close). Opening the drawer with a thread already current does not auto-close it.
- Drag handles render on wide viewports only.

## Alternatives considered

- Keeping the squeeze model and shrinking `SIDEBAR_DEFAULT`: a 280px column next to a 390px conversation is still unreadable, and the drawer need changes nothing about wide layouts.
- A separate mobile plugin registering a different root composition: two shells to keep in sync for one responsive concern, against the slot system's single-composition model.

## Consequences

- Touch users get the standard pattern: list → tap thread → full-screen conversation; rail stays one tap away.
- Desktop rendering is bit-identical: every new attribute, element, and CSS rule keys off state unreachable above the breakpoint.
