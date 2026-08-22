import { useEffect, useRef, useState } from 'react'

interface Props {
  text: string
  onDone: () => void
}

/**
 * Reveals an already-received reply. This is presentation, not progress: by the
 * time it runs the whole answer is in hand, and the honest waiting signal was
 * the elapsed timer in ThinkingIndicator.
 *
 * Rate is derived so the reveal finishes in about a second whatever the length,
 * because a long research answer character-by-character at a fixed rate is just
 * a delay. Click, keypress, or reduced motion completes it at once.
 */
const TARGET_MS = 900
const FRAME_MS = 16

export default function TypewriterText({ text, onDone }: Props) {
  const [shown, setShown] = useState(0)
  // Guards a duplicate onDone only. Never read during render: a ref read in
  // render does not re-render, so the output would go stale.
  const firedRef = useRef(false)

  useEffect(() => {
    const finish = () => {
      setShown(text.length)
      if (!firedRef.current) {
        firedRef.current = true
        onDone()
      }
    }

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      finish()
      return
    }

    const perFrame = Math.max(1, Math.ceil(text.length / (TARGET_MS / FRAME_MS)))
    let n = 0
    const id = window.setInterval(() => {
      n += perFrame
      if (n >= text.length) {
        window.clearInterval(id)
        finish()
      } else {
        setShown(n)
      }
    }, FRAME_MS)

    const skip = () => {
      window.clearInterval(id)
      finish()
    }
    window.addEventListener('keydown', skip)
    window.addEventListener('pointerdown', skip)

    return () => {
      window.clearInterval(id)
      window.removeEventListener('keydown', skip)
      window.removeEventListener('pointerdown', skip)
    }
  }, [text, onDone])

  // Derived purely from state, so it can never disagree with what React rendered.
  return <>{text.slice(0, shown)}</>
}
