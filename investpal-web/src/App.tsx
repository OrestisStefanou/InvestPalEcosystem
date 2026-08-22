import { useState } from 'react'

import { useSessions } from './hooks/useSessions'
import ChatView from './components/ChatView'
import RemindersView from './components/RemindersView'
import WorkflowsView from './components/WorkflowsView'
import ThemeToggle from './components/ThemeToggle'
import { Owl, Wordmark } from './components/Mark'

type Tab = 'chat' | 'workflows' | 'reminders'

const TABS: { id: Tab; label: string }[] = [
  { id: 'chat', label: 'Chat' },
  { id: 'workflows', label: 'Workflows' },
  { id: 'reminders', label: 'Reminders' },
]

export default function App() {
  const [tab, setTab] = useState<Tab>('chat')
  const s = useSessions()

  return (
    <div className="app">
      <header className="nav">
        <div className="nav-brand">
          <Owl className="brand-mark" />
          <Wordmark className="brand-word" />
          <span className="brand-tag">Local</span>
        </div>

        <nav className="tabs" role="tablist" aria-label="Views">
          {TABS.map((t) => (
            <button
              key={t.id}
              className="tab"
              type="button"
              role="tab"
              aria-selected={tab === t.id}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </nav>

        <ThemeToggle />
      </header>

      <main className="main">
        {/* Each view is unmounted when you leave it, so switching tabs aborts
            its in-flight requests. The exception that matters is chat: a reply
            in progress is abandoned, which is why the thinking panel says so. */}
        {tab === 'chat' && (
          <ChatView
            sessions={s.sessions}
            activeId={s.activeId}
            messages={s.messages}
            loadingList={s.loadingList}
            loadingHistory={s.loadingHistory}
            listError={s.error}
            onSelect={s.setActiveId}
            onNew={() => void s.startSession()}
            onMessages={s.setMessages}
            onDismissListError={() => s.setError(null)}
          />
        )}
        {tab === 'workflows' && <WorkflowsView />}
        {tab === 'reminders' && <RemindersView />}
      </main>
    </div>
  )
}
