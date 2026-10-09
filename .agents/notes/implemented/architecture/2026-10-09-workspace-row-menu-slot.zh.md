# Agent Note: Workspace 行菜单是一个 slot

Status: implemented

[English](2026-10-09-workspace-row-menu-slot.md) | 中文

## Problem

自 Workspace 浏览器把 action 移入 slot 之后，Session 行的 "..." 菜单与悬停按钮一直是 `list` slot，客户端插件可以按 `order` 把自己的 Session action 放在内置 action 旁边。Workspace 行的 "..." 菜单从来没有这道缝：`ProjectRowItem` 把它的两行拼成字面量数组，再用一个私有的 `rename`/`delete` 分支分发被选中的 id。想加一行的唯一办法是替换整个 `sidebar.workspaces` 注册项——那要 fork 约 2200 行浏览器与行代码、遮蔽内置 UI，并且上游对任一文件的每次改动都会让它失效。

## Decision

**Workspace 行的 "..." 菜单是 `sidebar.workspaces.workspace.menu.item` 列表**，由 WorkspaceBrowser 注册项与两个 Session 行列表一同声明，`ProjectRowItem` 通过 `renderSlot` 渲染它，并把菜单的打开状态作为该次出现的 `hookContext`。它是 root 作用域，条目渲染时既不绑定 Session 也不绑定 Workspace。本包以插件注册自己菜单行的同一方式注册 `rename`（100）与 `delete`（200），插件行落在它 `order` 所指的位置。该菜单仍然只为真实 Workspace 行渲染：未分组桶不传 actions，也就没有菜单。

**属主共享带上行的身份，以及浏览器负责应答的两个请求。** 条目拿到 `workspaceId`、`displayTitle` 与 `path`，外加 `requestRename` 与 `requestDelete`。两个内置行通过这两个回调拉起对话框，而不是自己拥有那段交互，因为重命名与删除对话框——它们的草稿、重名检查、进行中状态，以及删除时对 Workspace 投影提交移除的等待——是浏览器的局部状态。自带动作的条目会忽略这两个回调。

**关闭菜单仍然是条目自己的事。** 该列表把行的打开状态对绑定进 `useMenuOpenState` hook，与 Session 行菜单用的是同一个绑定，因此条目在动作之后关闭它所在的菜单，而列表的键盘遍历与焦点返回对任何 `role="menuitem"` 按钮都继续有效。

## Verification

`workspace-actions.client.spec.tsx` 用手写 props 渲染两个内置条目，锁定"先关闭再发起请求"的顺序、破坏性行的样式、两种语言的文案以及打开状态绑定。`rows.client.spec.tsx` 驱动行自己的那次渲染出现，锁定它交给列表的属主共享（`workspaceId`、`displayTitle`、`path`），以及条目通过所绑定 hook 的关闭动作确实关掉了菜单。`apply.client.spec.ts` 锁定声明出来的 spec、两个注册项的 id、order、component 与 locale，以及两者都不声明 inject face。`workspace-browser.client.spec.tsx` 通过浏览器自己的 slot stub 渲染内置条目，因此既有的重命名与删除对话框流程走的是装配后的路径。生成的 Client Slot catalog 带上这个新 key 及其示例与占用方，并由 `verify-client-catalog` 把关。

## Alternatives considered

**把重命名与删除对话框提升到 `shell.overlay`，并给条目一个 inject face，像 Session action 那样。** 否决：这会重写浏览器的对话框状态、重名检查，以及删除对投影提交移除的等待——约 120 行表现层与状态，唯一收益只是让内置行看起来和 Session 行完全一致。没有插件需要复用那些对话框，而属主回调已经把同样的两个请求交给了插件行。

**给插件另一个界面，例如 `shell.overlay` 上的动作或悬停按钮列表。** 否决：诉求就是这一行已经显示的 "..." 菜单；另开界面会把一行的动作劈成两处，而且菜单依然对插件关闭。

**属主共享里不暴露 `path`。** 否决：悬浮卡片已经显示该目录，所以 path 没有披露任何新信息；而最有用的插件行——复制路径、在终端打开、在其中执行命令——都需要绝对主机路径，并且无法从显示标题推导出来。

**让插件替换 `sidebar.workspaces` 注册项。** 否决，这正是改动前的状态：它要 fork 浏览器与行、声明 `replaceRisk: shadows-shipped-ui`，并且上游每次编辑都会让它失效。

## Consequences

- 客户端插件用 `ctx.slots.inject('sidebar.workspaces.workspace.menu.item', ...)` 添加 Workspace 行菜单条目，正如 catalog 里的示例；动态 browser half 渲染一个普通的 `role="menuitem"` 按钮。
- 以另一个 `priority` 复用内置 id（`rename`、`delete`）会遮蔽该行，与 Session 行菜单完全一致：内置行不再由构造方式获得特权。
- 渲染非 `role="menuitem"` 按钮控件的条目会落在菜单键盘遍历之外；Session 行菜单本来也有这条限制。
- Workspace 浏览器继续持有重命名与删除对话框，因此插件行无法复用它们，必须渲染自己的界面。
