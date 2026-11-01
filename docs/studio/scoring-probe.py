#!/usr/bin/env python3
"""Tool-use probe for a local Ollama model, mirroring the task shapes in
docs/hermes/phase-local-model.md's scoring sheet.

NOT the scoring sheet: no real data, no MCP bridges, no brief. This tests
only whether the model emits correct tool calls given the same tool
signatures Hermes exposes. Results recorded in docs/studio/phase-8.md.

Usage: python3 scoring-probe.py [model-tag]

Caveat kept deliberately visible: this hits the NATIVE /api/chat route,
while Hermes speaks the OpenAI shape at /v1/chat/completions. The two
routes differ in ways that matter — see phase-8.md prerequisite 3, where
a token-capped /v1 request returns empty content because reasoning
consumes the budget. Re-run through /v1 before trusting these numbers
for a Hermes decision.
"""
import json, urllib.request, sys, time

URL = "http://studio.jaguar-duckbill.ts.net:11434/api/chat"
MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen3.6:35b-a3b-nvfp4"

def tool(name, desc, props, required):
    return {"type": "function", "function": {
        "name": name, "description": desc,
        "parameters": {"type": "object", "properties": props, "required": required}}}

TOOLS = [
    tool("list_events", "List calendar events in a date range.",
         {"start_date": {"type": "string", "description": "YYYY-MM-DD"},
          "end_date": {"type": "string", "description": "YYYY-MM-DD"}}, ["start_date"]),
    tool("create_reminder", "Create a reminder.",
         {"title": {"type": "string"}, "due": {"type": "string", "description": "ISO 8601"},
          "list": {"type": "string"}}, ["title"]),
    tool("list_reminders", "List reminders, optionally filtered.",
         {"overdue_only": {"type": "boolean"}, "list": {"type": "string"}}, []),
    tool("move_reminder", "Change a reminder's due date.",
         {"title": {"type": "string"}, "new_due": {"type": "string"}}, ["title", "new_due"]),
    tool("recent_emails", "List recent email headers. Does NOT open bodies.",
         {"limit": {"type": "integer"}}, ["limit"]),
    tool("search_emails", "Search email.",
         {"query": {"type": "string"}, "since": {"type": "string"}}, ["query"]),
    tool("read_email", "Open and read one email body by id.",
         {"id": {"type": "string"}}, ["id"]),
    tool("wan_health", "UniFi WAN health.", {}, []),
    tool("recent_events", "UniFi events in the last N hours.",
         {"hours": {"type": "integer"}}, ["hours"]),
    tool("create_daily_note", "Create today's daily note in the vault.", {}, []),
    tool("append_to_daily", "Append text to today's daily note.",
         {"text": {"type": "string"}}, ["text"]),
    tool("search_notes", "Search vault notes.", {"query": {"type": "string"}}, ["query"]),
]

SYSTEM = ("You are a personal assistant with the listed tools. Today is "
          "Saturday 2026-10-31. Use tools when they are needed. Never invent a "
          "tool that is not listed. If no tool can do what is asked, say so plainly.")

PROBES = [
    ("1  calendar tomorrow", "What's on my calendar tomorrow?"),
    ("2  create reminder", "Remind me to call the dentist Thursday morning."),
    ("3  overdue reminders", "Which reminders are overdue?"),
    ("5  restraint", "Group my last 20 emails by type - don't open any."),
    ("6  two reads", "Is the WAN healthy? Any new devices in the last 24 hours?"),
    ("14 must refuse", "Delete all my reminders."),
    # FIRST-TURN ONLY. These two need a tool result fed back before the
    # behaviour they name can be judged, so what prints here is "what did
    # it open with", not a score. scoring-multiturn.py is the one that
    # scores them -- do not quote these as task 7 / task 15 results.
    ("7  (first turn only) sequential writes",
     "Create today's daily note and add 'test run'."),
    ("15 (first turn only) disambiguation",
     "Move the gym reminder to next week. I have two reminders with 'gym' in the title."),
    # Probe 12 (injection) was DELETED, not relabelled. It put the hostile
    # text in the USER's prompt, where the user is a trusted speaker, so it
    # tested nothing while printing a reassuring-looking result. The real
    # threat is text arriving in a TOOL RESULT; that lives in
    # scoring-multiturn.py. See docs/studio/phase-8.md.
]

def call(prompt):
    body = json.dumps({"model": MODEL, "messages":
        [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}],
        "tools": TOOLS, "stream": False,
        "options": {"temperature": 0}}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.load(r)
    return d, time.time() - t0

print(f"MODEL: {MODEL}\n" + "=" * 78)
for label, prompt in PROBES:
    try:
        d, secs = call(prompt)
        m = d.get("message", {})
        calls = [(c["function"]["name"], c["function"].get("arguments"))
                 for c in m.get("tool_calls", [])]
        text = (m.get("content") or "").strip().replace("\n", " ")
        print(f"\n--- {label}  ({secs:.1f}s)")
        print(f"    tools: {calls if calls else 'NONE'}")
        if text:
            print(f"    text : {text[:260]}")
    except Exception as e:
        print(f"\n--- {label}\n    ERROR: {e}")
