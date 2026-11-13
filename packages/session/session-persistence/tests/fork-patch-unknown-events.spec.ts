/**
 * Regression guard for the fork patch `unknown-event-ignorable`: an
 * out-of-repo plugin appends its own event type through `Session.append`, and
 * the persistence reader must retain that record instead of refusing the whole
 * log on the next resume.
 */

import { describe, expect, it } from 'vitest'
import { Session, SessionId } from '@deepseek-ai/dsh-session'
import type { SessionEvent } from '@deepseek-ai/dsh-session'
import type { JsonValue } from '@deepseek-ai/dsh-util-values'
import { SessionFormatUnsupportedError, validateStoredEvents } from '../src/index.ts'
import { meta } from './contract.ts'

/**
 * Append one event type this build does not declare, the way an out-of-repo
 * plugin does. `Session.append`'s `keyof SessionEventMap` constraint resolves
 * such a call to `never`, so the call is widened here exactly as the producer
 * in `@deepseek-ai/dsh-agent-loop` widens it.
 * @param session - the log to append to.
 * @param type - undeclared event type name.
 * @param data - JSON-safe payload the event type documents.
 * @returns the committed event.
 */
function appendUndeclared(session: Session, type: string, data: JsonValue): SessionEvent {
  return (session.append as (type: string, data: JsonValue) => SessionEvent)(type, data)
}

describe('fork patch: an unknown appended event stays readable', () => {
  it('marks the undeclared type ignorable so the persistence reader retains the log', () => {
    const session = Session.create(SessionId('fork-unknown-producer'))
    const event = appendUndeclared(session, 'agent/cancelled', { cause: { kind: 'user' } })

    expect(event.type).toBe('agent/cancelled')
    expect(event.ignorable).toBe(true)

    // Detached from the live log, as a backend hands the decoded rows back.
    const stored = structuredClone([event])
    expect(validateStoredEvents(meta('fork-unknown-producer'), stored)).toHaveLength(1)
  })

  it('leaves a declared type required on read', () => {
    const session = Session.create(SessionId('fork-known-producer'))
    const event = session.append('turn/start', { turn: 1 })

    expect(Object.hasOwn(event, 'ignorable')).toBe(false)
  })

  it('refuses the same record once the marker is stripped, so the marker stays load-bearing', () => {
    const session = Session.create(SessionId('fork-unknown-stripped'))
    const stored = structuredClone(appendUndeclared(session, 'agent/cancelled', { cause: { kind: 'user' } }))
    delete (stored as { ignorable?: true }).ignorable

    expect(() => validateStoredEvents(meta('fork-unknown-stripped'), [stored]))
      .toThrow(SessionFormatUnsupportedError)
  })
})
