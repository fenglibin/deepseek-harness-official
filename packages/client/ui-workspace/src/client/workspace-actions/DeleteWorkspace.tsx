/**
 * The delete row of a Workspace's "..." menu: the destructive shipped row. It
 * raises the browser's delete confirmation through the owner's callback and
 * dismisses the menu it sits in, leaving the confirmation and the Host call
 * to the browser.
 */
import { IconTrashOutlineRegular, MenuItemButton } from '@deepseek-ai/dsh-client-ui-primitives'
import type { WorkspaceMenuItemProps } from '../contract/slots.ts'

/**
 * Menu row (order 200): raise the browser's delete confirmation for the row.
 * @param props - owner share, the menu open state, and the locale seat.
 * @returns the row.
 */
export function DeleteWorkspaceMenuItem({ requestDelete, useMenuOpenState, t }: WorkspaceMenuItemProps) {
  const [, setMenuOpen] = useMenuOpenState()
  return (
    <MenuItemButton
      danger
      icon={<IconTrashOutlineRegular />}
      onSelect={() => {
        setMenuOpen(false)
        requestDelete()
      }}
    >
      {t('delete.workspace')}
    </MenuItemButton>
  )
}
