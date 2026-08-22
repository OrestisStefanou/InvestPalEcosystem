import type { Message } from '../api/types'
import { absolute } from '../util/format'
import TypewriterText from './TypewriterText'

interface Props {
  message: Message
  /** Non-null only for the reply that has just arrived. */
  reveal: string | null
  onRevealed: () => void
}

export default function MessageBubble({ message, reveal, onRevealed }: Props) {
  const mine = message.role === 'user'
  const revealing = !mine && reveal !== null && reveal === message.content

  return (
    <article className={`msg msg--${mine ? 'user' : 'agent'}`}>
      <p className="msg-who">
        {mine ? 'You' : 'InvestPal'}
        {message.created_at && <span className="vh">, {absolute(message.created_at)}</span>}
      </p>
      <div className="msg-body">
        {revealing ? <TypewriterText text={message.content} onDone={onRevealed} /> : message.content}
      </div>
    </article>
  )
}
