import { useCallback, useEffect, useState } from 'react'

type Theme = 'light' | 'dark'

/** Same storage key as the public site, so a theme set there carries over. */
const KEY = 'ip-theme'

function current(): Theme {
  const attr = document.documentElement.getAttribute('data-theme')
  if (attr === 'light' || attr === 'dark') return attr
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export function useTheme() {
  const [theme, setTheme] = useState<Theme>(current)

  const toggle = useCallback(() => {
    const next: Theme = current() === 'dark' ? 'light' : 'dark'
    document.documentElement.setAttribute('data-theme', next)
    try {
      localStorage.setItem(KEY, next)
    } catch {
      // Private windows and blocked site data throw. The theme still applies
      // for this page view; it just will not be remembered.
    }
    setTheme(next)
  }, [])

  // Follow the system while the user has made no explicit choice.
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const onChange = () => {
      if (!document.documentElement.hasAttribute('data-theme')) setTheme(current())
    }
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])

  return { theme, toggle }
}
