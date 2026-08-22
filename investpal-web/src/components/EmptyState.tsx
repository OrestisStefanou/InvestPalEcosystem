import type { ReactNode } from 'react'

import { Owl } from './Mark'

interface Props {
  title: string
  children: ReactNode
  action?: ReactNode
}

export default function EmptyState({ title, children, action }: Props) {
  return (
    <div className="empty">
      <Owl className="empty-mark" />
      <h3>{title}</h3>
      <p>{children}</p>
      {action && <div className="btn-row" style={{ justifyContent: 'center', marginTop: '1.4rem' }}>{action}</div>}
    </div>
  )
}
