/**
 * The rename row of a Workspace's "..." menu: one of the two shipped rows
 * that act through the owner's callbacks instead of owning an interaction of
 * their own, because the rename dialog is the browser's local state. The row
 * raises the request and dismisses the menu it sits in.
 */
import { IconEditOutlineRegular, MenuItemButton } from '@deepseek-ai/dsh-client-ui-primitives'
import type { WorkspaceMenuItemProps } from '../contract/slots.ts'

/**
 * Menu row (order 100): raise the browser's rename dialog for the row.
 * @param props - owner share, the menu open state, and the locale seat.
 * @returns the row.
 */
export function RenameWorkspaceMenuItem({ requestRename, useMenuOpenState, t }: WorkspaceMenuItemProps) {
  const [, setMenuOpen] = useMenuOpenState()
  return (
    <MenuItemButton
      icon={<IconEditOutlineRegular />}
      onSelect={() => {
        setMenuOpen(false)
        requestRename()
      }}
    >
      {t('rename')}
    </MenuItemButton>
  )
}
