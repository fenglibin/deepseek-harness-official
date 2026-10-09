# Agent Note: The Workspace row menu is a slot

Status: implemented

English | [中文](2026-10-09-workspace-row-menu-slot.zh.md)

## Problem

A Session row's "..." menu and its hover buttons have been `list` slots since the Workspace browser moved its actions into them, so a client plugin places its own Session action by `order` beside the shipped ones. A Workspace row's "..." menu never had that seam: `ProjectRowItem` built its two rows as a literal array and dispatched the selected id through a private `rename`/`delete` switch. The only way to add a row was to replace the whole `sidebar.workspaces` entry, which forks roughly 2,200 lines of browser and row code, shadows shipped UI, and breaks on every upstream change to either file.

## Decision

**The Workspace row's "..." menu is the `sidebar.workspaces.workspace.menu.item` list**, declared by the WorkspaceBrowser registration beside the two Session row lists and rendered by `ProjectRowItem` through `renderSlot` with the menu's open state as the occurrence's `hookContext`. It is root-scoped, so an entry binds neither a Session nor a Workspace to render. This package registers `rename` (100) and `delete` (200) into it the way a plugin registers its own row, and a plugin row takes whatever position its `order` gives it. The menu still renders only for a real Workspace row: the ungrouped bucket passes no actions and gets no menu.

**The owner share carries the row identity and the two requests the browser answers.** An entry receives `workspaceId`, `displayTitle`, and `path`, plus `requestRename` and `requestDelete`. The two shipped rows raise their dialogs through those callbacks instead of owning the interaction, because the rename and delete dialogs — their drafts, the duplicate-title check, the in-flight state, and the delete's wait for the Workspace projection to commit the removal — are the browser's local state. An entry that brings its own action ignores both callbacks.

**Dismissing the menu stays the entry's job.** The list binds the row's open-state pair into a `useMenuOpenState` hook, the same binding the Session row menu uses, so an entry closes the menu it sits in after acting and the list's keyboard walk and focus return keep working over any `role="menuitem"` button.

## Verification

`workspace-actions.client.spec.tsx` renders both shipped entries with hand-built props and pins the dismiss-then-request order, the destructive row's styling, both locale seats, and the open-state binding. `rows.client.spec.tsx` drives the row's own render occurrence and pins the owner share it hands the list (`workspaceId`, `displayTitle`, `path`) and that an entry's dismissal through the bound hook closes the menu. `apply.client.spec.ts` pins the declared spec, the two registrations' id, order, component, and locale, and that neither declares an inject face. `workspace-browser.client.spec.tsx` renders the shipped entries through the browser's own slot stub, so the existing rename and delete dialog flows exercise the assembled path. The generated Client Slot catalog carries the new key with its example and occupants, and `verify-client-catalog` gates it.

## Alternatives considered

**Lift the rename and delete dialogs to `shell.overlay` and give the entries an inject face, as the Session actions do.** Rejected because it rewrites the browser's dialog state, its duplicate-title check, and the delete's projection-commit wait — roughly 120 lines of presentation and state whose only benefit is making the shipped rows look exactly like Session rows. No plugin needs to reuse those dialogs, and the owner callbacks hand a plugin row the same two requests.

**Give plugins a separate surface, such as a `shell.overlay` action or a hover-button list.** Rejected because the request was for the "..." menu the row already shows; a second surface splits one row's actions across two affordances and still leaves the menu closed to plugins.

**Expose no `path` in the owner share.** Rejected because the hover card already shows the directory, so the path discloses nothing new, while the most useful plugin rows — copy the path, open it in a terminal, run a command in it — need the absolute host path and cannot derive it from a display title.

**Let a plugin replace the `sidebar.workspaces` entry.** Rejected as the status quo ante: it forks the browser and rows, declares `replaceRisk: shadows-shipped-ui`, and breaks on every upstream edit.

## Consequences

- A client plugin adds a Workspace row menu entry with `ctx.slots.inject('sidebar.workspaces.workspace.menu.item', ...)`, as the catalog's example shows; a dynamic browser half renders a plain `role="menuitem"` button.
- Reusing a shipped id (`rename`, `delete`) at another `priority` shadows that row, exactly as it does in the Session row menu: the shipped rows are no longer privileged by construction.
- An entry that renders a control other than a `role="menuitem"` button falls outside the menu's keyboard walk; the same caveat already applies to the Session row menu.
- The Workspace browser keeps ownership of the rename and delete dialogs, so a plugin row cannot reuse them and must render its own surface.
