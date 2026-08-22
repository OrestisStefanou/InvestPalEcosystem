import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

/**
 * The agent replies in Markdown: headings, bold, bullet and numbered lists,
 * horizontal rules, and GFM tables. remark-gfm is what makes the tables and
 * strikethrough work; without it a pipe table renders as literal pipes.
 *
 * Raw HTML is deliberately NOT enabled. react-markdown ignores embedded HTML
 * unless you add rehype-raw, and that default is the right one here: the text
 * is model-generated, so treating it as markup would mean trusting whatever a
 * model decided to emit. Everything the agent needs is expressible in
 * Markdown.
 */
export default function Markdown({ children }: { children: string }) {
  return (
    <div className="md">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          // Links open away from the app, and rel guards against the opened
          // page reaching back through window.opener.
          a: ({ href, children }) => (
            <a href={href} target="_blank" rel="noopener noreferrer">
              {children}
            </a>
          ),
          // Tables get their own scroll container. A wide table must scroll
          // inside itself rather than pushing the whole transcript sideways.
          table: ({ children }) => (
            <div className="md-table-wrap">
              <table>{children}</table>
            </div>
          ),
        }}
      >
        {children}
      </ReactMarkdown>
    </div>
  )
}
