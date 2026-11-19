import { tm } from '../i18n/i18n.ts'

const $ = (id: string) => document.getElementById(id)!
const word = (w: NoticeText) => (typeof w === 'string' ? w : tm(w))
const syncSize = () => requestAnimationFrame(() => window.notice.resize(Math.ceil($('box').getBoundingClientRect().height) + 28))

const MODIFIER_CODES = new Set([
  'ControlLeft', 'ControlRight',
  'AltLeft', 'AltRight',
  'ShiftLeft', 'ShiftRight',
  'MetaLeft', 'MetaRight', 'OSLeft', 'OSRight',
])

const CODE_KEYS: Record<string, string> = {
  Space: 'Space',
  Tab: 'Tab',
  Enter: 'Enter',
  NumpadEnter: 'Enter',
  Backspace: 'Backspace',
  Delete: 'Delete',
  Insert: 'Insert',
  Home: 'Home',
  End: 'End',
  PageUp: 'PageUp',
  PageDown: 'PageDown',
  ArrowUp: 'Up',
  ArrowDown: 'Down',
  ArrowLeft: 'Left',
  ArrowRight: 'Right',
  Minus: '-',
  Equal: '=',
  BracketLeft: '[',
  BracketRight: ']',
  Backslash: '\\',
  Semicolon: ';',
  Quote: "'",
  Backquote: '`',
  Comma: ',',
  Period: '.',
  Slash: '/',
  NumpadDecimal: 'NumDec',
  NumpadAdd: 'NumAdd',
  NumpadSubtract: 'NumSub',
  NumpadMultiply: 'NumMult',
  NumpadDivide: 'NumDiv',
}

interface KeyPress {
  code: string
  ctrlKey: boolean
  altKey: boolean
  shiftKey: boolean
  metaKey: boolean
}

type ShortcutStep =
  | { kind: 'modifiers'; display: string }
  | { kind: 'valid'; accelerator: string; display: string }
  | { kind: 'need-modifier'; display: string }
  | { kind: 'unsupported'; display: string }

function keyFromCode(code: string, mac: boolean): string | null {
  if (/^Key[A-Z]$/.test(code)) return code.slice(3)
  if (/^Digit[0-9]$/.test(code)) return code.slice(5)
  if (/^Numpad[0-9]$/.test(code)) return 'Num' + code.slice(6)
  const f = /^F([1-9]|1[0-9]|2[0-4])$/.exec(code)
  if (f) return !mac || Number(f[1]) <= 20 ? code : null
  return CODE_KEYS[code] ?? null
}

function modifierPreview(e: Pick<KeyPress, 'ctrlKey' | 'altKey' | 'shiftKey' | 'metaKey'>, mac: boolean): string {
  if (mac) {
    let s = ''
    if (e.metaKey) s += '⌘'
    if (e.ctrlKey) s += '⌃'
    if (e.altKey) s += '⌥'
    if (e.shiftKey) s += '⇧'
    return s ? s + '…' : ''
  }
  const parts: string[] = []
  if (e.ctrlKey) parts.push('Ctrl')
  if (e.altKey) parts.push('Alt')
  if (e.shiftKey) parts.push('Shift')
  return parts.length ? parts.join('+') + '+…' : ''
}

function parseKeyPress(e: KeyPress, platform: string): ShortcutStep {
  const mac = platform === 'darwin'
  const accMods: string[] = []
  const dispMods: string[] = []
  if (mac) {
    if (e.metaKey) { accMods.push('Cmd'); dispMods.push('⌘') }
    if (e.ctrlKey) { accMods.push('Ctrl'); dispMods.push('⌃') }
    if (e.altKey) { accMods.push('Alt'); dispMods.push('⌥') }
    if (e.shiftKey) { accMods.push('Shift'); dispMods.push('⇧') }
  } else {
    if (e.ctrlKey) { accMods.push('Ctrl'); dispMods.push('Ctrl') }
    if (e.altKey) { accMods.push('Alt'); dispMods.push('Alt') }
    if (e.shiftKey) { accMods.push('Shift'); dispMods.push('Shift') }
  }
  const hasMain = mac ? (e.metaKey || e.ctrlKey || e.altKey) : (e.ctrlKey || e.altKey)
  const modPrefix = mac ? dispMods.join('') : (dispMods.length ? dispMods.join('+') + '+' : '')

  if (MODIFIER_CODES.has(e.code)) {
    if (!mac && (e.code.startsWith('Meta') || e.code.startsWith('OS'))) {
      return hasMain ? { kind: 'unsupported', display: '' } : { kind: 'need-modifier', display: 'Win' }
    }
    return { kind: 'modifiers', display: modifierPreview(e, mac) }
  }
  const key = keyFromCode(e.code, mac)
  if (!mac && e.metaKey) {
    return !hasMain && key ? { kind: 'need-modifier', display: 'Win+' + key } : { kind: 'unsupported', display: '' }
  }
  if (!key) {
    return { kind: 'unsupported', display: '' }
  }
  const display = modPrefix + key
  if (!hasMain) {
    return { kind: 'need-modifier', display }
  }
  return { kind: 'valid', accelerator: [...accMods, key].join('+'), display }
}

function paragraph(text: NoticeText) {
  const p = document.createElement('p')
  word(text).split(/(\*\*[^*]+\*\*)/).forEach((part) => {
    if (/^\*\*[^*]+\*\*$/.test(part)) {
      const b = document.createElement('b')
      b.textContent = part.slice(2, -2)
      p.append(b)
    } else if (part) p.append(part)
  })
  return p
}

function copyRow(values: string[]) {
  const row = document.createElement('div')
  row.className = 'copies'
  for (const value of values) {
    const chip: HTMLButtonElement & { timer?: number } = document.createElement('button')
    chip.type = 'button'
    chip.className = 'copy'
    chip.title = '复制'
    const code = Object.assign(document.createElement('code'), { textContent: value })
    const tag = Object.assign(document.createElement('span'), { className: 'tag', textContent: '复制' })
    chip.append(code, tag)
    chip.addEventListener('click', () => {
      window.notice.copy(value)
      tag.textContent = '已复制'
      chip.classList.add('done')
      clearTimeout(chip.timer)
      chip.timer = setTimeout(() => { tag.textContent = '复制'; chip.classList.remove('done') }, 1500)
    })
    row.append(chip)
  }
  return row
}

const item = (it: NoticeParagraph) => (typeof it === 'object' && 'copy' in it ? [paragraph(it.text), copyRow(it.copy ?? [])] : [paragraph(it)])

interface Recorder {
  config: NoticeRecord
  saveBtn: HTMLButtonElement | null
  recorded: string
  recordedDisplay: string
  holdingModifiers: boolean
  chordDone: boolean
  saving: boolean
}

let recorder: Recorder | null = null

function showKeys(text: string, active: boolean) {
  $('keys').textContent = text
  $('keys').classList.toggle('empty', !active)
}

function showIdle(r: Recorder) {
  if (r.recordedDisplay) showKeys(r.recordedDisplay, true)
  else if (r.config.current) showKeys(r.config.current, false)
  else showKeys(tm(r.config.placeholder), false)
}

function setRecordError(msg: string) {
  const el = $('record-err')
  const changed = el.hidden !== !msg || el.textContent !== msg
  el.textContent = msg
  el.hidden = !msg
  if (changed) syncSize()
}

async function submitRecorded() {
  const r = recorder
  if (!r || !r.recorded || r.saving) return
  r.saving = true
  if (r.saveBtn) r.saveBtn.disabled = true
  const err = await window.notice.saveHotkey(r.recorded)
  r.saving = false
  if (err) {
    if (r.saveBtn) r.saveBtn.disabled = false
    setRecordError(err)
  }
}

window.notice.onInit((data) => {
  $('buttons').hidden = !data.buttons?.length
  $('title').textContent = word(data.title ?? '')
  $('body').replaceChildren(...(data.body ?? []).flatMap(item))
  let saveBtn: HTMLButtonElement | null = null
  $('buttons').replaceChildren(...(data.buttons ?? []).map((b) => {
    const el = document.createElement('button')
    el.className = b.primary ? 'b primary' : 'b'
    el.textContent = word(b.label)
    if (data.record && b.id === 'save') {
      el.disabled = true
      saveBtn = el
      el.addEventListener('click', () => { void submitRecorded() })
    } else if (data.record) {
      el.addEventListener('click', () => window.notice.choose(null))
    } else {
      el.addEventListener('click', () => window.notice.choose(b.id))
    }
    return el
  }))

  if (data.record) {
    recorder = {
      config: data.record,
      saveBtn,
      recorded: '',
      recordedDisplay: '',
      holdingModifiers: false,
      chordDone: false,
      saving: false,
    }
    $('record').hidden = false
    showIdle(recorder)
    setRecordError('')
    requestAnimationFrame(() => $('keys').focus())
  } else {
    recorder = null
    $('record').hidden = true
  }
  syncSize()
})

$('x').addEventListener('click', () => window.notice.choose(null))

document.addEventListener('keydown', (e) => {
  if (!recorder) {
    if (e.key === 'Escape') window.notice.choose(null)
    return
  }
  if (e.key === 'Escape') {
    e.preventDefault()
    window.notice.choose(null)
    return
  }
  if ((e.code === 'Enter' || e.code === 'NumpadEnter') && !e.ctrlKey && !e.altKey && !e.shiftKey && !e.metaKey && recorder.recorded) {
    e.preventDefault()
    void submitRecorded()
    return
  }
  e.preventDefault()
  if (e.repeat || recorder.saving) return

  const step = parseKeyPress(e, recorder.config.platform)
  switch (step.kind) {
    case 'modifiers':
      if (!recorder.chordDone) {
        recorder.holdingModifiers = true
        if (step.display) showKeys(step.display, false)
        setRecordError('')
      }
      break
    case 'valid':
      recorder.holdingModifiers = false
      recorder.chordDone = true
      recorder.recorded = step.accelerator
      recorder.recordedDisplay = step.display
      showKeys(step.display, true)
      if (recorder.saveBtn) recorder.saveBtn.disabled = false
      setRecordError('')
      break
    case 'need-modifier':
      recorder.holdingModifiers = false
      recorder.chordDone = true
      recorder.recorded = ''
      recorder.recordedDisplay = ''
      showKeys(step.display, false)
      if (recorder.saveBtn) recorder.saveBtn.disabled = true
      setRecordError(tm(recorder.config.needModifier))
      break
    case 'unsupported':
      recorder.holdingModifiers = false
      recorder.chordDone = true
      recorder.recorded = ''
      recorder.recordedDisplay = ''
      showIdle(recorder)
      if (recorder.saveBtn) recorder.saveBtn.disabled = true
      setRecordError(tm(recorder.config.unsupported))
      break
  }
})

document.addEventListener('keyup', (e) => {
  if (!recorder) return
  if (!e.ctrlKey && !e.altKey && !e.shiftKey && !e.metaKey) {
    recorder.chordDone = false
    if (recorder.holdingModifiers) {
      recorder.holdingModifiers = false
      showIdle(recorder)
    }
  } else if (recorder.holdingModifiers && !recorder.chordDone) {
    const preview = modifierPreview(e, recorder.config.platform === 'darwin')
    if (preview) showKeys(preview, false)
  }
})

window.addEventListener('blur', () => {
  if (!recorder) return
  recorder.chordDone = false
  if (recorder.holdingModifiers) {
    recorder.holdingModifiers = false
    showIdle(recorder)
  }
})

export {}
