import { useRef, useState } from 'react'

import { Send } from './Icons'

interface Props {
  disabled: boolean
  pending: boolean
  onSend: (text: string) => void
}

export default function Composer({ disabled, pending, onSend }: Props) {
  const [text, setText] = useState('')
  const ref = useRef<HTMLTextAreaElement>(null)

  const submit = () => {
    if (!text.trim() || disabled || pending) return
    onSend(text)
    setText('')
    if (ref.current) ref.current.style.height = 'auto'
  }

  return (
    <div className="composer">
      <div className="composer-inner">
        <div className="composer-row">
          <textarea
            ref={ref}
            rows={1}
            value={text}
            disabled={disabled}
            placeholder={disabled ? 'Start a session to ask something' : 'Ask about a holding, a company, or your portfolio'}
            aria-label="Message"
            onChange={(e) => {
              setText(e.target.value)
              // Grow with the content; max-height in CSS caps it and scrolls.
              e.target.style.height = 'auto'
              e.target.style.height = `${e.target.scrollHeight}px`
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                submit()
              }
            }}
          />
          <button
            className="btn btn--primary"
            type="button"
            onClick={submit}
            disabled={disabled || pending || !text.trim()}
          >
            Send <Send />
          </button>
        </div>
        <p className="composer-hint">
          <span><kbd>Enter</kbd> to send, <kbd>Shift</kbd>+<kbd>Enter</kbd> for a new line</span>
          {/* CONVERSATION_MESSAGES_LIMIT in .env, default 15. Worth saying: it
              explains why the agent stops recalling the top of a long thread. */}
          <span>The agent sees the most recent messages in this session, not all of them</span>
        </p>
      </div>
    </div>
  )
}
