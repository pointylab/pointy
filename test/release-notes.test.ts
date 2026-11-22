import { test } from 'node:test'
import assert from 'node:assert/strict'
import { extractReleaseNotes } from '../tools/release-notes.ts'

test('extractReleaseNotes matches v-prefixed and bare headings and stops at next version', () => {
  const md = [
    '# Changelog',
    '',
    '## v0.6.0',
    '',
    '### New',
    '',
    '- Feature A',
    '',
    '## 0.5.1 (2026-11-12)',
    '',
    '- Fix B',
    '',
    '## v0.5.0',
    '',
    '- Initial',
  ].join('\n')

  assert.equal(extractReleaseNotes(md, 'v0.6.0'), '### New\n\n- Feature A')
  assert.equal(extractReleaseNotes(md, '0.6.0'), '### New\n\n- Feature A')
  assert.equal(extractReleaseNotes(md, 'v0.5.1'), '- Fix B')
  assert.equal(extractReleaseNotes(md, '0.5.0'), '- Initial')
})

test('extractReleaseNotes handles CRLF and ignores headings inside fenced code blocks', () => {
  const md = [
    '# Changelog',
    '',
    '## v0.6.0 (2026-11-21)',
    '',
    'Example:',
    '```markdown',
    '## v0.5.1',
    'not a heading',
    '```',
    '',
    '~~~',
    '## v0.4.0',
    '~~~',
    '',
    '- Real item',
    '',
    '## v0.5.1',
    '',
    '- Older',
  ].join('\r\n')

  assert.equal(
    extractReleaseNotes(md, 'v0.6.0'),
    [
      'Example:',
      '```markdown',
      '## v0.5.1',
      'not a heading',
      '```',
      '',
      '~~~',
      '## v0.4.0',
      '~~~',
      '',
      '- Real item',
    ].join('\n'),
  )
})

test('extractReleaseNotes returns empty string for missing or empty sections', () => {
  const md = [
    '# Changelog',
    '',
    '## v0.6.0',
    '',
    '## v0.5.1',
    '',
    '- Fix',
  ].join('\n')

  assert.equal(extractReleaseNotes(md, 'v0.6.0'), '')
  assert.equal(extractReleaseNotes(md, 'v9.9.9'), '')
  assert.equal(extractReleaseNotes(md, ''), '')
})
