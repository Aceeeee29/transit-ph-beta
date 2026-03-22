import { type ReactNode, useEffect } from 'react'

export function GlobalButtonConfirmation({ children }: { children: ReactNode }) {
  useEffect(() => {
    const handleClick = (event: MouseEvent) => {
      if (event.defaultPrevented) return

      const target = event.target as Element | null
      if (!target) return

      const button = target.closest('button') as HTMLButtonElement | null
      if (!button) return
      if (button.disabled) return

      if (button.dataset.confirmSkip === 'true') return

      if (button.dataset.confirmed === 'true') {
        delete button.dataset.confirmed
        return
      }

      const message = button.dataset.confirmMessage?.trim() || 'Are you sure you want to continue?'
      const shouldContinue = window.confirm(message)

      if (!shouldContinue) {
        event.preventDefault()
        event.stopPropagation()
        return
      }

      event.preventDefault()
      event.stopPropagation()
      button.dataset.confirmed = 'true'
      button.click()
    }

    document.addEventListener('click', handleClick, true)
    return () => document.removeEventListener('click', handleClick, true)
  }, [])

  return <>{children}</>
}
