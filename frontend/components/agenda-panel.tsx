"use client"

import { AlertCircle, ListChecks, Loader2, Plus, Sparkles, Trash2 } from "lucide-react"
import { useEffect, useRef, useState, type ReactNode } from "react"
import { toast } from "sonner"

import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { useAgenda, useSaveAgenda } from "@/hooks/use-agenda"
import {
  ApiError,
  MAX_PASTE_LENGTH,
  PARSER_URL,
  ParseError,
  parseAgenda,
} from "@/lib/api"
import { formatLongDate } from "@/lib/datetime"
import type { ActionItem, Agenda, AgendaItem, AiSuggestion } from "@/lib/types"
import { cn } from "@/lib/utils"

// --- form state ---------------------------------------------------------------

type ItemRow = { id: string; topic: string; owner: string; minutes: string }
type ActionRow = { id: string; task: string; owner: string; due: string }

type Draft = {
  items: ItemRow[]
  actions: ActionRow[]
  /** "<row id>.<field>" for every field the model filled and the user has not touched. */
  suggested: Set<string>
  /** What the model suggested; saved next to the final agenda. */
  suggestion: AiSuggestion | null
}

let nextRowId = 0
const rowId = () => `row-${++nextRowId}`

const blankItem = (): ItemRow => ({ id: rowId(), topic: "", owner: "", minutes: "" })
const blankAction = (): ActionRow => ({ id: rowId(), task: "", owner: "", due: "" })

function toItemRow(item: AgendaItem): ItemRow {
  return {
    id: rowId(),
    topic: item.topic ?? "",
    owner: item.owner ?? "",
    minutes: item.minutes?.toString() ?? "",
  }
}

function toActionRow(item: ActionItem): ActionRow {
  return { id: rowId(), task: item.task ?? "", owner: item.owner ?? "", due: item.due ?? "" }
}

/** The form for a saved agenda (or a blank one), typed by hand. */
function draftFromAgenda(agenda: Agenda | null | undefined): Draft {
  return {
    items: agenda?.items.length ? agenda.items.map(toItemRow) : [blankItem()],
    actions: agenda?.action_items.map(toActionRow) ?? [],
    suggested: new Set(),
    // Re-saving an AI-started agenda keeps what the model originally suggested.
    suggestion: agenda?.ai_suggestion ?? null,
  }
}

/** The form pre-filled from the parser. Only fields the model filled are marked. */
function draftFromSuggestion(suggestion: AiSuggestion): Draft {
  const suggested = new Set<string>()
  const mark = (id: string, fields: Record<string, string>) => {
    for (const [field, value] of Object.entries(fields)) {
      if (value !== "") suggested.add(`${id}.${field}`)
    }
  }
  const items = suggestion.agenda.items.map(toItemRow)
  items.forEach(({ id, ...fields }) => mark(id, fields))
  const actions = suggestion.agenda.action_items.map(toActionRow)
  actions.forEach(({ id, ...fields }) => mark(id, fields))
  return {
    items: items.length ? items : [blankItem()],
    actions,
    suggested,
    suggestion,
  }
}

// --- panel --------------------------------------------------------------------

/** A meeting's agenda: the saved one, the Add agenda form, and Paste an agenda. */
export function AgendaPanel({ meetingId }: { meetingId: string }) {
  const { data: agenda, isPending, isError } = useAgenda(meetingId)
  const [draft, setDraft] = useState<Draft | null>(null)

  return (
    <section className="space-y-3">
      <h3 className="flex items-center gap-2 text-sm font-semibold">
        <ListChecks className="size-4" aria-hidden />
        Agenda
      </h3>

      {draft ? (
        <AgendaForm
          meetingId={meetingId}
          draft={draft}
          onChange={setDraft}
          onDone={() => setDraft(null)}
        />
      ) : (
        <>
          {isPending ? (
            <p className="text-muted-foreground text-sm">Loading the agenda…</p>
          ) : isError ? (
            <p className="text-destructive text-sm">Could not load the agenda.</p>
          ) : agenda ? (
            <AgendaView agenda={agenda} />
          ) : (
            <p className="text-muted-foreground text-sm">No agenda yet.</p>
          )}
          <Button
            variant="outline"
            size="sm"
            disabled={isPending}
            onClick={() => setDraft(draftFromAgenda(agenda))}
          >
            {agenda ? "Edit agenda" : "Add agenda"}
          </Button>
          {PARSER_URL ? (
            <PasteAgenda onParsed={(suggestion) => setDraft(draftFromSuggestion(suggestion))} />
          ) : null}
        </>
      )}
    </section>
  )
}

function AgendaView({ agenda }: { agenda: Agenda }) {
  return (
    <div className="space-y-3 text-sm">
      <ol className="list-decimal space-y-1 pl-5">
        {agenda.items.map((item, index) => (
          <li key={index}>
            <span className="font-medium">{item.topic}</span>
            {item.owner || item.minutes ? (
              <span className="text-muted-foreground">
                {" — "}
                {[item.owner, item.minutes ? `${item.minutes} min` : null]
                  .filter(Boolean)
                  .join(" · ")}
              </span>
            ) : null}
          </li>
        ))}
      </ol>
      {agenda.action_items.length > 0 ? (
        <div className="space-y-1">
          <p className="text-muted-foreground text-xs font-semibold uppercase">Action items</p>
          <ul className="list-disc space-y-1 pl-5">
            {agenda.action_items.map((item, index) => (
              <li key={index}>
                {item.task}
                {item.owner || item.due ? (
                  <span className="text-muted-foreground">
                    {" — "}
                    {[item.owner, item.due ? `by ${formatLongDate(item.due)}` : null]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  )
}

// --- paste --------------------------------------------------------------------

function PasteAgenda({ onParsed }: { onParsed: (suggestion: AiSuggestion) => void }) {
  const [text, setText] = useState("")
  const [parsing, setParsing] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const controller = useRef<AbortController | null>(null)

  // Leaving the screen stops waiting for an answer nobody will see.
  useEffect(() => () => controller.current?.abort(), [])

  const tooLong = text.length > MAX_PASTE_LENGTH

  async function parse() {
    const current = new AbortController()
    controller.current = current
    setError(null)
    setParsing(true)
    try {
      onParsed(await parseAgenda(text, current.signal))
    } catch (caught) {
      if (current.signal.aborted) return // Cancel: back to the text, no error.
      setError(caught instanceof ParseError ? caught.message : new ParseError("unavailable").message)
    } finally {
      if (controller.current === current) controller.current = null
      setParsing(false)
    }
  }

  return (
    <div className="space-y-2 rounded-2xl border p-3">
      <Label htmlFor="paste-agenda">
        <Sparkles className="size-4" aria-hidden />
        Paste an agenda
      </Label>
      <Textarea
        id="paste-agenda"
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder="Paste an email, a chat message or a few lines of notes."
        disabled={parsing}
        aria-invalid={tooLong}
        className="max-h-48"
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span
          className={cn(
            "text-xs tabular-nums",
            tooLong ? "text-destructive" : "text-muted-foreground",
          )}
        >
          {text.length.toLocaleString("en")} / {MAX_PASTE_LENGTH.toLocaleString("en")}
        </span>
        {parsing ? (
          <div className="flex items-center gap-2">
            <span role="status" className="text-muted-foreground flex items-center gap-1.5 text-sm">
              <Loader2 className="size-4 animate-spin" aria-hidden />
              Reading the agenda, this takes a few seconds…
            </span>
            <Button variant="outline" size="sm" onClick={() => controller.current?.abort()}>
              Cancel
            </Button>
          </div>
        ) : (
          <Button size="sm" onClick={parse} disabled={!text.trim() || tooLong}>
            Parse
          </Button>
        )}
      </div>
      {tooLong ? <p className="text-destructive text-sm">{new ParseError("too_long").message}</p> : null}
      {error ? (
        <Alert variant="destructive">
          <AlertCircle aria-hidden />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      ) : null}
    </div>
  )
}

// --- the agenda form ------------------------------------------------------------

function Field({
  id,
  label,
  suggested,
  className,
  children,
}: {
  id: string
  label: string
  suggested: boolean
  className?: string
  children: ReactNode
}) {
  return (
    <div className={cn("grid min-w-0 gap-1", className)}>
      <div className="flex h-5 items-center gap-1.5">
        <Label htmlFor={id} className="text-muted-foreground text-xs">
          {label}
        </Label>
        {suggested ? (
          <Badge variant="secondary" className="h-4 px-1.5 text-[10px]">
            <Sparkles aria-hidden />
            suggested
          </Badge>
        ) : null}
      </div>
      {children}
    </div>
  )
}

const suggestedInput = "border-primary/50 bg-primary/5"

function AgendaForm({
  meetingId,
  draft,
  onChange,
  onDone,
}: {
  meetingId: string
  draft: Draft
  onChange: (draft: Draft) => void
  onDone: () => void
}) {
  const save = useSaveAgenda(meetingId)
  const [error, setError] = useState<string | null>(null)
  const isSuggested = (id: string, field: string) => draft.suggested.has(`${id}.${field}`)

  /** Editing a field is touching it: its "suggested" mark goes. */
  function touched(id: string, field: string) {
    const suggested = new Set(draft.suggested)
    suggested.delete(`${id}.${field}`)
    return suggested
  }

  function setItem(id: string, field: keyof Omit<ItemRow, "id">, value: string) {
    onChange({
      ...draft,
      items: draft.items.map((row) => (row.id === id ? { ...row, [field]: value } : row)),
      suggested: touched(id, field),
    })
  }

  function setAction(id: string, field: keyof Omit<ActionRow, "id">, value: string) {
    onChange({
      ...draft,
      actions: draft.actions.map((row) => (row.id === id ? { ...row, [field]: value } : row)),
      suggested: touched(id, field),
    })
  }

  async function onSave() {
    setError(null)
    const items = draft.items.filter((row) => row.topic.trim() || row.owner.trim() || row.minutes)
    const actions = draft.actions.filter((row) => row.task.trim() || row.owner.trim() || row.due)
    if (items.length === 0) return setError("Add at least one agenda item.")
    if (items.some((row) => !row.topic.trim())) return setError("Every agenda item needs a topic.")
    if (items.some((row) => row.minutes && !/^\d+$/.test(row.minutes))) {
      return setError("Minutes must be a whole number.")
    }
    if (actions.some((row) => !row.task.trim())) return setError("Every action item needs a task.")

    try {
      await save.mutateAsync({
        items: items.map((row) => ({
          topic: row.topic.trim(),
          owner: row.owner.trim() || null,
          minutes: row.minutes ? Number(row.minutes) : null,
        })),
        action_items: actions.map((row) => ({
          task: row.task.trim(),
          owner: row.owner.trim() || null,
          due: row.due || null,
        })),
        ai_suggestion: draft.suggestion,
      })
      toast.success("Agenda saved")
      onDone()
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Could not save the agenda.")
    }
  }

  return (
    <div className="space-y-3">
      {draft.suggestion ? (
        <p className="text-muted-foreground text-xs">
          {draft.suggestion.agenda.items.length === 0
            ? "The model found no agenda items in this text. Type them by hand."
            : "Check the suggested fields, correct anything that is wrong, then save."}
        </p>
      ) : null}

      <ol className="space-y-2">
        {draft.items.map((row, index) => (
          <li key={row.id} className="space-y-2 rounded-2xl border p-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold">Item {index + 1}</span>
              <Button
                variant="ghost"
                size="icon-xs"
                aria-label={`Remove item ${index + 1}`}
                disabled={draft.items.length === 1}
                onClick={() =>
                  onChange({ ...draft, items: draft.items.filter((item) => item.id !== row.id) })
                }
              >
                <Trash2 aria-hidden />
              </Button>
            </div>
            <Field id={`${row.id}-topic`} label="Topic" suggested={isSuggested(row.id, "topic")}>
              <Input
                id={`${row.id}-topic`}
                value={row.topic}
                maxLength={200}
                onChange={(event) => setItem(row.id, "topic", event.target.value)}
                className={cn(isSuggested(row.id, "topic") && suggestedInput)}
              />
            </Field>
            <div className="grid grid-cols-[1fr_8rem] gap-2">
              <Field id={`${row.id}-owner`} label="Owner" suggested={isSuggested(row.id, "owner")}>
                <Input
                  id={`${row.id}-owner`}
                  value={row.owner}
                  maxLength={200}
                  onChange={(event) => setItem(row.id, "owner", event.target.value)}
                  className={cn(isSuggested(row.id, "owner") && suggestedInput)}
                />
              </Field>
              <Field
                id={`${row.id}-minutes`}
                label="Minutes"
                suggested={isSuggested(row.id, "minutes")}
              >
                <Input
                  id={`${row.id}-minutes`}
                  type="number"
                  inputMode="numeric"
                  min={1}
                  max={480}
                  value={row.minutes}
                  onChange={(event) => setItem(row.id, "minutes", event.target.value)}
                  className={cn(isSuggested(row.id, "minutes") && suggestedInput)}
                />
              </Field>
            </div>
          </li>
        ))}
      </ol>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => onChange({ ...draft, items: [...draft.items, blankItem()] })}
      >
        <Plus aria-hidden />
        Add item
      </Button>

      <div className="space-y-2">
        <p className="text-muted-foreground text-xs font-semibold uppercase">Action items</p>
        {draft.actions.map((row, index) => (
          <div key={row.id} className="space-y-2 rounded-2xl border p-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold">Action {index + 1}</span>
              <Button
                variant="ghost"
                size="icon-xs"
                aria-label={`Remove action ${index + 1}`}
                onClick={() =>
                  onChange({
                    ...draft,
                    actions: draft.actions.filter((action) => action.id !== row.id),
                  })
                }
              >
                <Trash2 aria-hidden />
              </Button>
            </div>
            <Field id={`${row.id}-task`} label="Task" suggested={isSuggested(row.id, "task")}>
              <Input
                id={`${row.id}-task`}
                value={row.task}
                maxLength={500}
                onChange={(event) => setAction(row.id, "task", event.target.value)}
                className={cn(isSuggested(row.id, "task") && suggestedInput)}
              />
            </Field>
            <div className="grid grid-cols-[1fr_10rem] gap-2">
              <Field id={`${row.id}-owner`} label="Owner" suggested={isSuggested(row.id, "owner")}>
                <Input
                  id={`${row.id}-owner`}
                  value={row.owner}
                  maxLength={200}
                  onChange={(event) => setAction(row.id, "owner", event.target.value)}
                  className={cn(isSuggested(row.id, "owner") && suggestedInput)}
                />
              </Field>
              <Field id={`${row.id}-due`} label="Due" suggested={isSuggested(row.id, "due")}>
                <Input
                  id={`${row.id}-due`}
                  type="date"
                  value={row.due}
                  onChange={(event) => setAction(row.id, "due", event.target.value)}
                  className={cn(isSuggested(row.id, "due") && suggestedInput)}
                />
              </Field>
            </div>
          </div>
        ))}
        <Button
          variant="ghost"
          size="sm"
          onClick={() => onChange({ ...draft, actions: [...draft.actions, blankAction()] })}
        >
          <Plus aria-hidden />
          Add action item
        </Button>
      </div>

      {error ? (
        <Alert variant="destructive">
          <AlertCircle aria-hidden />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      ) : null}

      <div className="flex justify-end gap-2">
        <Button variant="outline" onClick={onDone} disabled={save.isPending}>
          Cancel
        </Button>
        <Button onClick={onSave} disabled={save.isPending}>
          {save.isPending ? <Loader2 className="animate-spin" aria-hidden /> : null}
          Save agenda
        </Button>
      </div>
    </div>
  )
}
