/**
 * The owl and the wordmark, referencing the <symbol> definitions in index.html.
 * They recolour with the theme because their fills are --mark-* and --logo-*
 * custom properties, so there is nothing to swap per theme.
 *
 * Neither <svg> carries a viewBox, deliberately: the symbols have their own
 * ("0 0 240 240" and "255 80 222 52"), and setting a second one on the wrapper
 * double-transforms the content and pushes it out of the viewport. Sizing is
 * done in CSS, at the aspect ratio the symbol expects.
 */

export const Owl = ({ className }: { className?: string }) => (
  <svg className={className} aria-hidden="true" focusable="false">
    <use href="#ip-owl" />
  </svg>
)

export const Wordmark = ({ className }: { className?: string }) => (
  <svg className={className} role="img" aria-label="InvestPal" focusable="false">
    <use href="#ip-word" />
  </svg>
)
