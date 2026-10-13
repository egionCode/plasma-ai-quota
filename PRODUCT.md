# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop (KDE Plasma 6 widget, QML). None of web/ios/android applies.

## Users

The developer who owns the machine, running several AI coding subscriptions at once
(two Claude Team accounts managed by clauth, a ChatGPT Plus account for Codex). Glances
at the widget during the workday to know how much quota each account has left.

## Product Purpose

Show the remaining subscription quota of every AI account installed locally, per usage
window (5 hours, weekly, per-model weekly), and when each window resets. Success: one
glance answers "how much is left and when does it free up" for every account.

## Operating Context

- Lives mostly on the desktop as an always-visible card; the panel view exists but is
  secondary.
- Data comes from local credentials and clauth; it can be live, cached or a fallback,
  and the user must be able to tell which.
- Follows the user's Plasma theme (light or dark, accent color) and system language
  (English source strings, pt_BR translation).

## Capabilities and Constraints

- Sources: clauth (default for Claude), direct Claude Code credentials (fallback), Codex.
- Read-only: never refreshes tokens.
- Every account and window has equal weight; no account is singled out.

## Product Principles

- Native first: look like a well-made part of Plasma, not a foreign app.
- Every number states its freshness when it is not live.
- Equal weight across accounts; color only signals a quota running out.
