import { useTheme } from '../hooks/useTheme'
import { Moon, Sun } from './Icons'

export default function ThemeToggle() {
  const { theme, toggle } = useTheme()
  return (
    <button
      className="icon-btn"
      type="button"
      onClick={toggle}
      aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
      title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
    >
      {/* Both render; CSS shows one, so the icon is right even before hydration. */}
      <Moon className="icon-moon" />
      <Sun className="icon-sun" />
    </button>
  )
}
