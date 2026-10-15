import { signOut } from "aws-amplify/auth"

import { getAccessToken } from "@/lib/auth"
import { toIsoDate } from "@/lib/datetime"
import type {
  Agenda,
  AgendaSaveInput,
  AiSuggestion,
  ApiErrorBody,
  ApiErrorDetail,
  Meeting,
  MeetingCreateInput,
  MeetingList,
  UserProfile,
} from "@/lib/types"

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000"

export class ApiError extends Error {
  readonly code: string
  readonly details: ApiErrorDetail[]
  readonly status: number

  constructor(status: number, code: string, message: string, details: ApiErrorDetail[]) {
    super(message)
    this.name = "ApiError"
    this.status = status
    this.code = code
    this.details = details
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await getAccessToken()
  let response: Response
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init?.headers,
      },
      cache: "no-store",
    })
  } catch {
    throw new ApiError(0, "network_error", "Could not reach the meetings API.", [])
  }

  // The session is gone or was revoked: sign out, and the auth guard sends the
  // user back to the login page.
  if (response.status === 401) {
    void signOut()
  }

  if (response.status === 204) {
    return undefined as T
  }

  const text = await response.text()
  const payload = text ? JSON.parse(text) : null

  if (!response.ok) {
    const body = payload as ApiErrorBody | null
    throw new ApiError(
      response.status,
      body?.error?.code ?? "internal_error",
      body?.error?.message ?? `Request failed with status ${response.status}.`,
      body?.error?.details ?? [],
    )
  }

  return payload as T
}

export function listMeetings(params: { date?: string; q?: string } = {}) {
  const search = new URLSearchParams()
  if (params.date) search.set("date", params.date)
  if (params.q) search.set("q", params.q)
  const query = search.toString()
  return request<MeetingList>(`/api/v1/meetings${query ? `?${query}` : ""}`)
}

export function getMeeting(id: string) {
  return request<Meeting>(`/api/v1/meetings/${id}`)
}

export function createMeeting(payload: MeetingCreateInput) {
  return request<Meeting>("/api/v1/meetings", {
    method: "POST",
    body: JSON.stringify(payload),
  })
}

export function updateMeeting(id: string, payload: MeetingCreateInput) {
  return request<Meeting>(`/api/v1/meetings/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  })
}

export function deleteMeeting(id: string) {
  return request<void>(`/api/v1/meetings/${id}`, { method: "DELETE" })
}

export function getMe() {
  return request<UserProfile>("/api/v1/me")
}

/** Stores the profile from the ID token in the users table; call after signing in. */
export function syncMe(idToken: string) {
  return request<UserProfile>("/api/v1/me/sync", {
    method: "POST",
    body: JSON.stringify({ id_token: idToken }),
  })
}

export function getAgenda(meetingId: string) {
  return request<Agenda | null>(`/api/v1/meetings/${meetingId}/agenda`)
}

/** The only way an agenda is written: the main API, with its usual validation. */
export function saveAgenda(meetingId: string, payload: AgendaSaveInput) {
  return request<Agenda>(`/api/v1/meetings/${meetingId}/agenda`, {
    method: "POST",
    body: JSON.stringify(payload),
  })
}

// --- Paste an agenda: the agenda-parser function URL (read-only) -------------

/** Empty when the parser is not deployed; the screen then hides Paste an agenda. */
export const PARSER_URL = process.env.NEXT_PUBLIC_PARSER_URL ?? ""
export const MAX_PASTE_LENGTH = 10_000

export type ParseErrorKind =
  | "too_long"
  | "no_agenda"
  | "busy"
  | "network"
  | "unauthorized"
  | "unavailable"

const PARSE_ERROR_MESSAGES: Record<ParseErrorKind, string> = {
  too_long: `The text is too long. Paste at most ${MAX_PASTE_LENGTH.toLocaleString("en")} characters.`,
  no_agenda: "Could not find an agenda in this text. Try other text, or type the agenda by hand.",
  busy: "The AI service is busy right now. Try again in a minute, or type the agenda by hand.",
  network: "Could not reach the agenda parser. Check your connection, or type the agenda by hand.",
  unauthorized: "Your session has expired. Sign in again to parse an agenda.",
  unavailable: "The AI service is not available right now. Type the agenda by hand.",
}

export class ParseError extends Error {
  readonly kind: ParseErrorKind

  constructor(kind: ParseErrorKind) {
    super(PARSE_ERROR_MESSAGES[kind])
    this.name = "ParseError"
    this.kind = kind
  }
}

/**
 * Sends pasted text to the parser and returns its suggestion. Today's date and
 * the time zone are the user's, so "Monday" means the user's Monday. Aborting
 * `signal` rejects with the browser's AbortError.
 */
export async function parseAgenda(text: string, signal: AbortSignal): Promise<AiSuggestion> {
  if (text.length > MAX_PASTE_LENGTH) throw new ParseError("too_long")
  const token = await getAccessToken()
  let response: Response
  try {
    response = await fetch(PARSER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({
        text,
        today: toIsoDate(new Date()),
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
      signal,
      cache: "no-store",
    })
  } catch (error) {
    if (signal.aborted) throw error
    throw new ParseError("network")
  }

  if (response.ok) return (await response.json()) as AiSuggestion
  switch (response.status) {
    case 401:
      throw new ParseError("unauthorized")
    case 413:
      throw new ParseError("too_long")
    case 422:
      throw new ParseError("no_agenda")
    case 429:
      throw new ParseError("busy")
    default:
      throw new ParseError("unavailable")
  }
}
