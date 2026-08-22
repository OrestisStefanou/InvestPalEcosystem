import type { Message } from '../api/types'
import { absolute } from '../util/format'
import Markdown from './Markdown'

interface Props {
  message: Message
  /** True for the reply that has just arrived, which fades in rather than popping. */
  isNew: boolean
}

export default function MessageBubble({ message, isNew }: Props) {
  const mine = message.role === 'user'

  return (
    <article className={`msg msg--${mine ? 'user' : 'agent'}${isNew ? ' msg--new' : ''}`}>
      <p className="msg-who">
        {mine ? 'You' : 'InvestPal'}
        {message.created_at && <span className="vh">, {absolute(message.created_at)}</span>}
      </p>
      {/* Only the agent's side is Markdown. What you typed is shown exactly as
          you typed it: rendering your own input as markup would mangle a
          message that happens to contain an asterisk or a hash. */}
      {mine ? (
        <div className="msg-body msg-body--plain">{message.content}</div>
      ) : (
        <div className="msg-body">
          <Markdown>{message.content}</Markdown>
        </div>
      )}
    </article>
  )
}
