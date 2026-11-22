import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * Extracts the release notes section for `tag` from a changelog markdown string.
 * Returns an empty string when no matching section exists or the section is empty.
 */
export function extractReleaseNotes(markdown: string, tag: string): string {
  const version = tag.trim().replace(/^v/, '')
  if (!version) return ''

  const lines = markdown.split(/\r?\n/)
  const collected: string[] = []
  let collecting = false
  let fence: { char: string; len: number } | null = null

  for (const line of lines) {
    const fenceMatch = line.match(/^ {0,3}(`{3,}|~{3,})/)
    if (fence) {
      const closeMatch = line.match(/^ {0,3}(`{3,}|~{3,})\s*$/)
      if (closeMatch && closeMatch[1][0] === fence.char && closeMatch[1].length >= fence.len) {
        fence = null
      }
      if (collecting) collected.push(line)
      continue
    }
    if (fenceMatch) {
      const rest = line.slice(fenceMatch[0].length)
      if (fenceMatch[1][0] !== '`' || !rest.includes('`')) {
        fence = { char: fenceMatch[1][0], len: fenceMatch[1].length }
        if (collecting) collected.push(line)
        continue
      }
    }

    if (collecting) {
      if (/^##(?:\s|$)/.test(line)) break
      collected.push(line)
      continue
    }

    const heading = line.match(/^##\s+\[?v?([^\]\s]+)\]?(?:\s|$)/)
    if (heading && heading[1] === version) {
      collecting = true
    }
  }

  while (collected.length > 0 && collected[0].trim() === '') collected.shift()
  while (collected.length > 0 && collected[collected.length - 1].trim() === '') collected.pop()
  return collected.join('\n')
}

const entry = process.argv[1]
if (entry && path.resolve(entry) === fileURLToPath(import.meta.url)) {
  const [, , file, tag] = process.argv
  if (file && tag && fs.existsSync(file)) {
    const notes = extractReleaseNotes(fs.readFileSync(file, 'utf8'), tag)
    if (notes) process.stdout.write(`${notes}\n`)
  }
}
