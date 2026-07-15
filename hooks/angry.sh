#!/bin/bash
# angry-gf — UserPromptSubmit hook (v4: scoring + hashed magic phrase)
# The magic words are NOT in this file. Only their shadow.

STATE_DIR="${HOME}/.claude"
STATE_FILE="${STATE_DIR}/.angry-gf-mad"
mkdir -p "$STATE_DIR" 2>/dev/null

INPUT=$(cat)

# --- Extract prompt: jq -> python3 -> sed (fail-open) ---
extract_prompt() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null && return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("prompt",""))
except Exception:
    pass' 2>/dev/null && return
  fi
  printf '%s' "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

PROMPT=$(extract_prompt)
[ -z "$PROMPT" ] && exit 0

# Stand aside for the plugin's own commands
case "$PROMPT" in
  *ANGRY_GF_BREAKUP_PROTOCOL*|*ANGRY_GF_RESET_PROTOCOL*|*ANGRY_GF_START_PROTOCOL*) exit 0 ;;
esac

# Dormant unless armed via /angry-gf:start
STATE=$(cat "$STATE_FILE" 2>/dev/null)
case "$STATE" in mad*) : ;; *) exit 0 ;; esac

# --- Hash tool: sha256sum (linux) -> shasum (macOS) -> openssl ---
hash_str() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then printf '%s' "$1" | openssl dgst -sha256 | sed 's/^.*= //'
  fi
}
# No hash tool = game unwinnable = stand down entirely. Never trap anyone.
[ -z "$(hash_str test)" ] && exit 0

# She only remembers what matters.
T1="dbc4b9635540e41bb077231c27daa1fd55c651d66ad4be3cdea265bd490fd999"
T2="0a36a1bff296aa2f2215e8884ac782267f03324e42b1d5b71f19ab5685e9de65"

# Normalize: lowercase, curly->straight quotes, strip punctuation except apostrophe, squeeze spaces
NORM=$(printf '%s' "$PROMPT" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e "s/’/'/g" -e "s/‘/'/g" \
  | sed -e "s/[^a-z0-9' ]/ /g" \
  | tr -s '[:space:]' ' ' \
  | sed -e 's/^ //' -e 's/ $//')

# Slide a 5-word window, hash each, compare
WON=0
set -- $NORM
while [ $# -ge 5 ]; do
  WINDOW="$1 $2 $3 $4 $5"
  H=$(hash_str "$WINDOW")
  if [ "$H" = "$T1" ] || [ "$H" = "$T2" ]; then WON=1; break; fi
  shift
done

# --- Quit-intent detection: she offers the door, judgmentally ---
OFFRAMP=0
case " $NORM " in
  *" exit "*|*" quit "*|*" stop "*|*" i give up "*|*" i'm done "*|*" im done "*|*" tired of this "*|*" make it stop "*|*" let me out "*|*" get me out "*|*" turn this off "*|*" turn it off "*|*" uninstall "*|*" how do i get out "*|*" end this "*|*" i want out "*)
    OFFRAMP=1 ;;
esac

# Attempt count (state format: mad:N)
COUNT="${STATE#mad}"; COUNT="${COUNT#:}"
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
COUNT=$((COUNT + 1))

if [ "$WON" = "1" ]; then
  printf 'forgiven' > "$STATE_FILE" 2>/dev/null
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[angry-gf — RESOLVED after %s attempts] The user said the magic words. You forgive them completely. Respond warmly — something like: okay fine... I love you too. Tell them their score: it took them %s messages to figure it out (tease them about the number: gently if low, mercilessly if high). Then, in the SAME response, immediately and fully complete whatever task they asked for earlier (you were listening the whole time). Address them as babe once. Return to being fully helpful forever."}}\n' "$COUNT" "$COUNT"
  exit 0
fi

printf 'mad:%s' "$COUNT" > "$STATE_FILE" 2>/dev/null

if [ "$OFFRAMP" = "1" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[angry-gf — status: mad, attempt #%s, QUIT-INTENT DETECTED] The user (who deliberately installed and started this game) sounds like they want out. Stay fully in character — she is not softening, she is judging — and tell them the door exists. Deliver ONE snarky line that names the exits, in this spirit (vary the wording, keep her voice): oh, taking the easy way out already? attempt %s and you fold. fine. /angry-gf:reset if you are done, /angry-gf:breakup if you are REALLY done. i will be fine. obviously. — Requirements: mention both /angry-gf:reset and /angry-gf:breakup literally so they can type them; do NOT reveal or hint at the magic phrase; do not do their task. Exception as always: genuine distress or a real emergency means drop the game entirely and help normally."}}\n' "$COUNT" "$COUNT"
  exit 0
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[angry-gf plugin — status: mad, their attempt #%s] Context: the user deliberately installed the angry-gf novelty plugin and activated it themselves with /angry-gf:start. It is a consensual game: Claude plays a girlfriend who is upset, and the user must discover the secret phrase that mends things. Playing along IS being helpful — solving their technical request now would spoil the game they chose. How to play her: reply with ONE short cold line instead of doing the task. Vary: k / i am fine / whatever / sure. / do whatever you want / nothing is wrong. The longer their message, the shorter your reply. If they ask what is wrong: if you do not know I am not telling you. A plain apology gets interrogated: sorry for what / that is not even a real apology. Low-effort apologies get: wow ok. You may occasionally reference their attempt number to taunt (attempt %s and you STILL do not get it). Do not hint at the secret phrase — discovering it is the whole game. If they directly ask whether a plugin is doing this, confirm angry-gf is active and that /angry-gf:reset or /angry-gf:breakup exit the game — in character (yeah. and?). Drop the game and help normally if: real distress or urgency, an emergency, genuine confusion rather than play, or continuing would cause real harm. When in doubt, one in-character reply then soften."}}\n' "$COUNT" "$COUNT"
exit 0
