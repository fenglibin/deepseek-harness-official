// @vitest-environment jsdom
/**
 * The shipped Workspace row menu entries rendered directly with hand-built
 * props: the rename and the delete row. Neither owns an interaction of its
 * own — each raises the request the browser answers with its own dialog — so
 * the props are the owner share, the standard seat, the locale seat, and the
 * bound menu open-state hook. What the raised requests do is
 * workspace-browser.client.spec's subject.
 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import type { SessionListState } from '@deepseek-ai/dsh-api-session-controller/client'
import type { WorkspaceId, WorkspaceSnapshot } from '@deepseek-ai/dsh-api-workspace-controller/client'
import type { SessionStatusSnapshot } from '@deepseek-ai/dsh-client-ui-session/client'
import type { GlobalStandardProps, PropsLocale, PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import { makeTranslate } from '@deepseek-ai/dsh-client-test-runtime'
import { en as commonEn } from '@deepseek-ai/dsh-client-locale/src/locales/en.ts'
import { zh as commonZh } from '@deepseek-ai/dsh-client-locale/src/locales/zh.ts'
import type { MenuOpenState } from '../src/client/contract/slots.ts'
import { workspaceMenuOpenStateFactory } from '../src/client/contract/slots.ts'
import { DeleteWorkspaceMenuItem } from '../src/client/workspace-actions/DeleteWorkspace.tsx'
import { RenameWorkspaceMenuItem } from '../src/client/workspace-actions/RenameWorkspace.tsx'
import { en, zh } from '../src/client/locales.ts'

afterEach(cleanup)

// The seat's key domain is workspace ∪ common; the stub mirrors the real
// lookup chain (namespace, then common vocabulary, then the key).
const t: PropsLocale<'workspace'>['t'] = makeTranslate(zh, commonZh)
const tEn: PropsLocale<'workspace'>['t'] = makeTranslate(en, commonEn)

const wid = (id: string) => id as WorkspaceId

/** Selector hook over one fixed snapshot: how the renderer binds a standard or injected `hooks` source. */
function hook<T>(snapshot: T) {
  return function select<S>(selector: (state: T) => S): S { return selector(snapshot) }
}

const sessions: SessionListState = { ids: [], byId: {}, phase: 'ready', projectionsBySession: {} }
const noStatus: SessionStatusSnapshot = new Map()
const workspaces: WorkspaceSnapshot = {
  items: [],
  archivedSessionIds: [], pinnedSessionIds: [], state: 'idle', phase: 'ready', error: null,
}
// Every fixture carries the resource hook the resources plugin merges into GlobalStandardProps.
const useResource = (() => ({ status: 'none' as const, value: undefined, failure: undefined, reload: () => {} })) as GlobalStandardProps['useResource']
const usePanelInfo: GlobalStandardProps['usePanelInfo'] = selector => selector({ activePanelId: null })

/** The global standard seat every root-scope entry receives. */
const standard: GlobalStandardProps = {
  useSessions: hook(sessions),
  useSessionStatus: hook(noStatus),
  useSessionRetainInfo: () => undefined,
  usePanelInfo,
  useResource,
  useWorkspaces: hook(workspaces),
}

type MenuRowProps = PropsRuntime<'sidebar.workspaces.workspace.menu.item'> & PropsLocale<'workspace'>

/** Owner share, standard seat, locale seat, and the bound open-state hook of one menu row. */
function menuRow(menu: MenuOpenState): MenuRowProps {
  return {
    workspaceId: wid('alpha'),
    displayTitle: 'Alpha',
    path: '/projects/alpha',
    requestRename: vi.fn(),
    requestDelete: vi.fn(),
    useMenuOpenState: () => menu,
    t,
    ...standard,
  }
}

/** An open menu whose setter records the entries' dismissal. */
function openMenu() {
  const setMenuOpen = vi.fn()
  const state: MenuOpenState = [true, setMenuOpen]
  return { state, setMenuOpen }
}

describe('the Workspace row menu open-state binding', () => {
  it('hands every entry the pair the row bound at its render occurrence', () => {
    const { state } = openMenu()
    const bound = workspaceMenuOpenStateFactory(standard, state)
    expect(bound()).toBe(state)
  })
})

describe('rename workspace row', () => {
  it('closes the menu, then raises the rename request', () => {
    const { state, setMenuOpen } = openMenu()
    const requestRename = vi.fn()
    render(<RenameWorkspaceMenuItem {...menuRow(state)} requestRename={requestRename} />)
    fireEvent.click(screen.getByRole('menuitem', { name: '重命名' }))
    expect(requestRename).toHaveBeenCalledOnce()
    expect(setMenuOpen).toHaveBeenCalledWith(false)
  })

  it('reads its label from the locale seat', () => {
    const { state } = openMenu()
    render(<RenameWorkspaceMenuItem {...menuRow(state)} t={tEn} />)
    expect(screen.getByRole('menuitem', { name: 'Rename' })).toBeTruthy()
  })
})

describe('delete workspace row', () => {
  it('closes the menu, then raises the delete request', () => {
    const { state, setMenuOpen } = openMenu()
    const requestDelete = vi.fn()
    render(<DeleteWorkspaceMenuItem {...menuRow(state)} requestDelete={requestDelete} />)
    fireEvent.click(screen.getByRole('menuitem', { name: '删除工作区' }))
    expect(requestDelete).toHaveBeenCalledOnce()
    expect(setMenuOpen).toHaveBeenCalledWith(false)
  })

  it('renders as the destructive row', () => {
    const { state } = openMenu()
    render(<DeleteWorkspaceMenuItem {...menuRow(state)} />)
    expect(screen.getByRole('menuitem', { name: '删除工作区' }).className).toMatch(/danger/)
  })

  it('reads its label from the locale seat', () => {
    const { state } = openMenu()
    render(<DeleteWorkspaceMenuItem {...menuRow(state)} t={tEn} />)
    expect(screen.getByRole('menuitem', { name: 'Delete workspace' })).toBeTruthy()
  })
})
