import { useEffect, useRef } from 'react'

import type { ApiError } from '../api/client'
import { useChat } from '../hooks/useChat'
import type { Message, SessionSummary } from '../api/types'
import Composer from './Composer'
import EmptyState from './EmptyState'
import ErrorBanner from './ErrorBanner'
import MessageBubble from './MessageBubble'
import SessionList from './SessionList'
import ThinkingIndicator from './ThinkingIndicator'

interface Props {
  sessions: SessionSummary[]
  activeId: string | null
  messages: Message[]
  loadingList: boolean
  loadingHistory: boolean
  listError: ApiError | null
  onSelect: (id: string) => void
  onNew: () => void
  onMessages: (fn: (prev: Message[]) => Message[]) => void
  onDismissListError: () => void
}

export default function ChatView(props: Props) {
  const { sessions, activeId, messages, loadingList, loadingHistory, listError } = props
  const chat = useChat({ sessionId: activeId, onMessages: props.onMessages })
  const endRef = useRef<HTMLDivElement>(null)

  // Keep the newest turn in view. `smooth` is skipped under reduced motion by
  // the browser itself when the OS setting is on.
  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }, [messages.length, chat.pending])

  const error = chat.error ?? listError

  return (
    <div className="chat">
      <SessionList
        sessions={sessions}
        activeId={activeId}
        loading={loadingList}
        onSelect={props.onSelect}
        onNew={props.onNew}
      />

      <div className="conversation">
        <div className="transcript">
          <div className="transcript-inner">
            {error && (
              <ErrorBanner
                error={error}
                onDismiss={() => {
                  chat.setError(null)
                  props.onDismissListError()
                }}
              />
            )}

            {loadingHistory && <p className="loading">Loading conversation</p>}

            {!loadingHistory && !activeId && (
              <EmptyState
                title="No session open"
                action={
                  <button className="btn btn--primary" type="button" onClick={props.onNew}>
                    Start a session
                  </button>
                }
              >
                InvestPal keeps each conversation, and remembers what matters between them.
                Start one and ask about something you hold.
              </EmptyState>
            )}

            {!loadingHistory && activeId && messages.length === 0 && !chat.pending && (
              <EmptyState title="Ask it something">
                Try a holding you already own, or a company you are weighing up. It pulls the
                filings, walks a written valuation procedure, and tells you what it found.
              </EmptyState>
            )}

            {messages.map((m, i) => (
              <MessageBubble
                key={`${m.role}-${i}-${m.created_at ?? ''}`}
                message={m}
                isNew={
                  chat.repliesReceived > 0 &&
                  i === messages.length - 1 &&
                  m.role === 'agent'
                }
              />
            ))}

            {chat.pending && chat.startedAt !== null && (
              <ThinkingIndicator startedAt={chat.startedAt} onCancel={chat.cancel} />
            )}

            <div ref={endRef} />
          </div>
        </div>

        <Composer disabled={!activeId} pending={chat.pending} onSend={chat.send} />
      </div>
    </div>
  )
}
