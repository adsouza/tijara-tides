# Background music: regional pieces that follow the player's focus

Adds the soundtrack described in [DESIGN.md](../../DESIGN.md#background-music):
regional port and voyage music that follows the player's latest explicit ship
or port selection, with timed transitions, a device-persisted toggle and volume,
and a credit for each piece as it begins. Written 2026-10-12.

## Intent

Music should make a port feel like a place and a voyage feel like a crossing
between two places, without competing with the trading screens. DESIGN.md is
the playback contract; the [shortlist](../../music-shortlist.md) and
[recording audit](../../music-recording-audit.md) record the listening and
licensing work behind the track choices. Success means a player who selects
Tangier hears North African port music, selects a ship sailing from Tangier to
Valencia and hears the voyage shift from North African toward Mediterranean
music as it progresses, and can always see who made the piece and turn it down.

Decisions taken during design:

| Question | Decision |
|---|---|
| Slots with two accepted candidates | Ship both in the pool: 28 tracks |
| Asset storage | Git LFS under `priv/audio/` |
| Controls | Compact speaker control in the header for every visitor |
| Playback engine | Streamed `<audio>` elements routed through Web Audio gain |
| Repeats | Whole-recording repeats, with fresh listening approval; no loop edits |
| Selection entries | Preserve the audit's approved source entry offsets |
| Encoding | Ogg Opus at 64 kbps, about 37 MB in total |
| LFS quota | Measure a real Render deploy's download before relying on it |

Out of scope: loop and repeat edits from the audit (not used with whole
recordings), per-account music settings, sound effects, and an AAC fallback
unless the desktop probe below requires one.

## Roster

Twelve palettes, 14 port tracks and 14 voyage tracks. A pool holds every
accepted candidate for its role.

| Palette | Port pool | Voyage pool |
|---|---|---|
| Chinese coast | Shenyang | Imperial China Cinematic |
| Japanese | Sakuya3 | Ametsuchi |
| Korean | Listening to Our Sounds | Beautiful Korea; Korean traditional-cinematic piece with gayageum |
| Southeast Asian | Hoi An Ancient Charm | Epic Nusantara |
| South Asian | Dhaka | Epic Indian Orchestral Fusion |
| Arabian Gulf | Middle East Ballad | Conquer The Great Sands |
| North African | Arabic Music; Desert2 | Folk_Arabian |
| Mediterranean | Dellasera | Atlas • Greece; Cinematic Latin Music |
| Northern Frangistan | Lord of the Land | Pathfinder |
| North American | Swing Train - Big Band Miller Style; Market on the Sea | The World At Your Door |
| Caribbean | Beachfront Celebration | Setting Sail |
| Brazilian | Sideways Samba | Up In The Air |

Each track uses its free full recording from the audit's original recording
index, not a supplied loop file. Full-recording vocal sign-off and
repeated-play listening remain open in the music documents. Implementation and
disabled deployments can proceed, but production playback requires the
[release listening gate](#release-listening-gate). Any track can be replaced
later by editing the roster and rerunning preparation, which invalidates the
affected approvals.

## Musical context

### Focus

GameLive gains a `music_focus` assign containing `{:port, port_id}` or
`{:ship, ship_id}`. It retains the explicitly chosen identifier independently
of `selected_port`, `selected_ship` and `inspected_ship`. Only successful,
validated explicit player events replace it:

- `"port"`, `"auction-port"` and `"first-ship-port"` set `{:port, id}`.
- `"ship"` sets `{:ship, id}` for an owned ship.
- `"inspect-ship"` sets `{:ship, id}` for the inspected ship, owned or public.

Automatic `selected_port` changes never touch it: the port chosen when a docked
ship is selected, the destination preview, `apply_view` auto-selection and
`reveal_public_ship`. Background refresh preserves both the focus kind and its
identifier. Initialize port focus from the selected port after the first view
has been applied. A focused ship's departure and arrival resolve that retained
ship's current state, rather than another automatically selected ship. If it
no longer exists in the accessible view, fall back once to the current selected
port and retain that port focus until another explicit selection.

### What the client receives

A `#music` element in the game header carries the context as data attributes:

- Port focus: `data-context="port"` and `data-port` from the retained focus
  identifier, never the mutable presentation selection.
- Ship focus on a docked, loading or unloading ship: `data-context="port"`
  and `data-port` from that focused ship's current port.
- Ship focus on a sailing ship: `data-context="voyage"`, `data-ship`,
  `data-origin`, `data-destination` and `data-progress`.

`data-progress` comes from `GameQueries.voyage_progress`, so weather holds slow
it exactly as the voyage display shows. The element also carries the manifest
URL, localized labels and templates, and `data-music="unavailable"` when the
audio files are missing (see [Availability](#availability)). The server has no
knowledge of palettes; the mapping lives in the manifest.

### Identity

The client derives a music identity from the context and the manifest:

- A port context's identity is its port palette.
- A voyage context's identity is its pair of origin and destination palettes.

A change of identity starts the selection transition. An unchanged identity
continues the current piece without fading, restarting or resetting a pending
transition. Consequences:

- Selecting another port in the same palette continues.
- Selecting another sailing ship with the same palette pair continues; later
  piece choices use the newly selected ship's progress.
- Departure and arrival of the selected ship change identity and use the
  selection transition, as DESIGN.md requires.
- A diversion that changes the destination palette changes identity and uses
  the selection transition. A diversion within the same palette does not.

## Playback

### Selection transitions

The transition machine implements DESIGN.md's timing exactly: a three-second
settle, a five-second outgoing fade with gain `cos(pi * p / 2)` from the current
gain, a two-second incoming fade with gain `sin(pi * p / 2)`, the cancel rule
during the settle, one second of silence after a completed fade before a
superseding piece, a three-second silent wait restarted by each change while
silent, and a fresh transition from current gains when a change arrives during
a fade-in. All timers use real elapsed time. These deadlines describe ready
audio; delayed playback follows the explicit fallback below without advancing
a fade over audio that has not started.

### Readiness and transition ownership

`music_transitions.js` owns selection fades, automatic crossfades, silent
waits, disabling, hiding and resuming. Selection transitions take precedence
over automatic crossfades. Turning off, hiding or destroying the hook takes
precedence over every pending start. There is at most one pending incoming
piece. A new context invalidates its predecessor's timers, pending loads and
playback callbacks, while preserving the original outgoing deadline when the
reselection rule requires it. Every asynchronous callback carries a generation
identifier and rechecks the current generation, enabled state and foreground
state before changing playback or credits. An unchanged identity preserves
the generation and pending deadline. Foreground means both visible and
focused; a visibility event alone cannot resume an unfocused window.

On a changed context, choose and preload the pending piece immediately, seek
to its selection entry and wait for the seek to finish. Keep its gain at zero
until its earliest fade-in deadline. Call `play()` at that deadline once the
element is ready; start the two-second gain envelope only after playback has
actually begun and the `play()` promise has fulfilled. Use the current audio
clock for gain scheduling and elapsed timestamps for selection deadlines.

If loading, seeking or permission delays playback past the deadline, the
outgoing piece still finishes its original fade. Stay silent as necessary,
then give the latest eligible incoming piece a full two-second fade from its
actual playback start. Do not shorten the fade or jump to an elapsed envelope
position. A context change while silent restarts the three-second wait even
if the audio is ready. A superseded `play()` fulfillment immediately pauses
and disposes its silent element, without a fade or credit. Loading and seeking
have a ten-second timeout from preparation; starting playback has a separate
ten-second timeout from the `play()` call. Waiting for a settling deadline or
the first autoplay gesture does not count toward a playback timeout. A timeout
counts as a failure and selects a replacement under the same context; it does
not restart the outgoing fade or the elapsed settling delay.

If a selection arrives during an automatic crossfade, cancel its scheduling
and start a selection transition from all currently audible gains. If the
outgoing recording ends before a selection fade finishes, stop that source
and preserve the pending deadline; never restart the old context to fill the
gap. While any selection transition or silent wait owns playback, track-end
events cannot choose or start another piece. The same cancellation rules cover
toggle, visibility and focus events, rejected promises and hook teardown.

### Selection entries and repeats

Silence detection does not identify quiet musical introductions. Selection
starts and fresh pieces on return use these approved source offsets:

| Piece | Source entry, seconds |
|---|---:|
| Setting Sail | 8 |
| Imperial China Cinematic | 16 |
| Epic Indian Orchestral Fusion | 8 |
| Conquer The Great Sands | 30 |
| Cinematic Latin Music | 2 |
| Pathfinder | 1 |

Other pieces start at source zero, subject to boundary silence trimming and
the release listening gate. A port resume retains its paused position. The
manifest translates source offsets into the encoded file's timeline after
trimming; loading and seeking must complete before playback starts.

Routine repeats and automatic choices between pieces begin at the trimmed
recording's start and run to its natural ending. This whole-recording strategy
differs from the approved audit loops and four-second repeat blends. Those
approvals do not validate these new repeats, nor do old prepared-file handoffs
validate the final encodes. Audition the actual prepared entries, repeats and
handoffs before enabling production playback.

### Choosing pieces

- A port context starts a random piece from its palette's port pool.
- A voyage piece is drawn from the destination palette with probability equal
  to the latest progress, and from the origin palette otherwise. A voyage whose
  origin and destination share a palette uses that palette alone.
- The next piece avoids repeating the piece just played when its pool offers
  another; a pool of one restarts the same recording from its beginning.

### Between pieces

Ten seconds before a piece ends, prepare the next candidate using the latest
context and voyage progress at that choice. Two seconds before the end, begin
a two-second crossfade using the same cosine and sine curves, provided the
candidate is ready and no selection transition owns playback. Delayed starts
use the readiness fallback. When less than ten seconds remain after a resume,
prepare immediately; when less than two remain, attempt the handoff as soon
as readiness and higher-priority transitions allow. Silence trimming removes
boundary silence only; musical decays and quiet passages remain and require
listening approval.

### Volume and toggle

A master gain sits above the per-piece fade gains. The volume slider runs from
0 to 100 and sets master gain to `(v / 100)²` with a 50 ms ramp. The
first-launch default is enabled at 30, about -21 dB; the value remains a tuning
decision. Turning music off invalidates every pending start, cancels selection
and automatic crossfades, fades all audible sources out from their current
gains over one second and pauses. Context updates while off update the desired
context only. Turning it on resolves that current context afresh and fades in
over two seconds after readiness and autoplay unlock; an old pending context
cannot resume. It stays paused while the game is away. Both settings persist
in `localStorage`; when storage is unavailable or throws, the defaults apply
for the visit.

### Switching away

When the document becomes hidden or the window loses focus, pending transitions
are cancelled, all audible music fades out over one second and the elements
pause. On return, music resumes only if enabled, fading in over two seconds:

- A port piece whose palette still matches the current identity resumes where
  it paused.
- A voyage picks a fresh piece from the current progress.
- A context that changed while away starts its own music.

### Autoplay

The `AudioContext` is created suspended and resumes on the first pointer or key
event. Nothing plays, and no credit is shown, before then.

### Credits

Each time a piece actually starts fading in after successful playback start,
by selection, crossfade or return, a strip at the top centre of the header
shows "Now playing: {title} by {artists}" for eight seconds, linking to the
recording's source page in a new tab, with `aria-live="polite"`. The wrapper is
a gettext template with named placeholders passed through a data attribute;
titles and artists appear as credited.

The speaker popover links to `/music/credits`, a plain page rendered from the
manifest listing each track's title, credited creators, source, licence and
edits. `docs/music-credits.md` carries the same content for the repository.

### Failures

- If the browser cannot play Ogg Opus or lacks Web Audio, the speaker control is
  hidden and music stays off.
- A piece that fails to load is skipped for the next choice. After three
  consecutive failures, music stops until the next identity change. Seeking and
  playback failures or timeouts count too, including media errors after
  readiness or during streaming, and a playing piece that stalls without
  progress for the ten-second load timeout. Only an actual playback start resets
  the count. Replacements use the latest desired context and voyage progress,
  preserving any selection deadline. If a playing piece fails, a healthy pending
  successor may start as soon as it is ready; otherwise prepare a replacement
  from the recording's beginning. Errors from outgoing or paused pieces dispose
  those sources without replacing the current context, and a failed paused piece
  cannot resume. Superseded requests and intentional pauses do not count.

## Controls

A speaker button in `game-header-actions` toggles music for every visitor,
signed in or not. A small popover holds the volume slider and the credits link.
The controls carry no `name` attribute, since FormFields rejects named controls
outside submit forms; they are identified by `id` and `data-*`. Labels come from
gettext with Arabic translations. The header becomes `inert` while the map is
expanded; the music control is unavailable then, as the rest of the header is.

## Assets

### Preparation

`scripts/prepare-music.py` is run by hand. It reads `scripts/music-roster.json`
(palette, role, slug, title, credited creators, source URL, licence, selection
entry in original source seconds and expected source SHA-256 for each track)
and a `--sources` directory, by default `tmp/music-audit-2026-10-10`. For each
track it:

1. Verifies the source hash.
2. Trims leading and trailing audio below -60 dBFS and records the removed
   duration. Translates the selection entry into the trimmed timeline,
   clamping source zero to encoded zero, and rejects entries beyond the end.
   Quiet musical openings are retained; the entry offset bypasses them only
   for selection starts and fresh pieces on return.
3. Measures integrated loudness with ffmpeg `ebur128` and applies one linear
   gain toward -20 LUFS, reduced where needed to keep true peak at or below
   -1 dBTP. Dynamics are not compressed.
4. Encodes stereo Ogg Opus at 64 kbps to `priv/audio/<slug>.ogg`.

It writes `priv/audio/music.json`: palettes with their ports, port pool and
voyage pool, and for each track its file, output SHA-256, duration, applied
gain, boundary trims, encoded selection entry, credits, source URL, licence and
edit notes. It never writes listening approvals: those live in
`priv/music/approvals.json` (see the [release listening
gate](#release-listening-gate)), which the script reads only to report which
approvals its new outputs would make stale. The script is not a `gen-*`
generator because CI cannot regenerate audio from sources outside the
repository; tests check the committed outputs instead.

`scripts/gen-music-credits.py` generates `docs/music-credits.md` from the
manifest, and `scripts/check-generated.py` verifies it.

### Serving

A dedicated `Plug.Static` mounted at `/audio` serves `priv/audio/`.
Keeping the soundtrack out of `priv/static` stops `phx.digest` from shipping a
fingerprinted second copy of every recording, and `.ogg` is not compressed.
Plug.Static supports byte-range requests and partial responses, so the
`<audio>` element can request data for an entry offset or paused position.
Verify HTTP 206 and `Content-Range` through the deployed serving path, as well
as ordinary full-file playback. A seek is asynchronous even with range support;
it remains subject to the readiness gate.

### Git LFS

`.gitattributes` tracks `priv/audio/*.ogg` with LFS. The repository uses the
tracked `.githooks/` directory as `core.hooksPath`, so the tracked `pre-push`
hook chains to `git lfs pre-push`, and tracked `post-checkout`, `post-commit`
and `post-merge` hooks call their LFS counterparts. Test jobs, the Docker smoke
build and the desktop workflow check out without LFS; only developer clones and
Render deploys fetch audio.

### Availability

Production playback has a server-side enable flag that defaults to false.
Enable it only after the release listening gate passes. Prepared files can be
deployed and measured while this flag remains false. At boot the server also
reads `priv/music/approvals.json` and requires every binding to match the
current manifest; an absent or stale approval keeps music unavailable even when
the flag is true.

At boot the server checks that every manifest file begins with `OggS` rather
than an LFS pointer. If any does not, it logs a warning naming the files and
renders `data-music="unavailable"`, which hides the control. A deploy that
received pointers has no music rather than broken music.

The manifest must also provide the fields used by the client: nonempty palette
identifiers, port lists and track pools, valid track references, titles,
artists, source links and hashes, and numeric entry positions within positive
recording durations. Malformed fields keep music unavailable, including in
development audition mode.

### Release listening gate

Before enabling production playback, record explicit approval for every roster
track's complete source recording: no lyrics, wordless singing, choir or
chanting, and suitable variation for background play. Automated voice
screening and approval of an excerpt are insufficient. Also approve the final
encoded selection entries and the new whole-recording repeats, including
natural decays and the two-second blends. Check every roster port-to-voyage
pairing within each palette, plus representative automatic
origin-to-destination and reverse handoffs using these encodes in the client.
Record the reviewed pairs and passages explicitly; these auditions do not claim
approval of every possible interruption position. Older approved loop previews
remain useful evidence about those edits, but cannot satisfy this gate for
whole recordings.

Approvals live in `priv/music/approvals.json`, a committed file edited only to
record listening decisions. Preparation reads it to report approvals its new
outputs would make stale but never writes it, so re-encoding one track cannot
erase or rewrite another track's sign-off. Each entry records the decision,
date and reviewed passages, and binds to the source SHA-256, output SHA-256,
entry offsets, repeat strategy and fade settings it was made against. A changed
source invalidates its full vocal and suitability sign-off; a changed output or
playback recipe invalidates the affected entry, repeat and handoff approvals.
The music audit summarizes these decisions in prose, but the file is the
record the server and tests read.

The availability check requires all 28 tracks, all within-palette port-to-voyage
pairs and the recorded cross-region handoff checks to be approved; no unreviewed
piece enters a random pool. CI checks the records without requiring the
production enable flag. An approval whose binding no longer matches the current
manifest fails CI, so a stale sign-off is caught in the change that made it
stale. A pending approval, one not yet recorded, passes CI and is listed in the
test output; it keeps music unavailable in production. Every current handoff
record for a required pair is checked, including multiple records for the same
pair. An earlier approval cannot hide a later rejection, pending decision or
stale binding. To keep a replaced record as history, set its decision to
`superseded`; superseded records are ignored, so a pair with only superseded
records is pending.

### Quota

`render.yaml` deploys every push to main whose checks pass, and main received
227 commits in the month before this spec. GitHub's free LFS allowance is 10
GiB of bandwidth a month; with a $0 budget, LFS is blocked for the rest of the
month once it is exceeded. Encoding at 64 kbps keeps the audio near 37 MB. The
first infrastructure step measures what one Render deploy actually downloads
by reading GitHub's LFS bandwidth usage before and after a deploy, and records
the result in `docs/deploying.md`. If deploys fetch the full set each time and
the projected monthly total approaches the allowance, stop and decide on a
budget or deployment change before continuing.

## Architecture

- LiveView owns `music_focus`, a presentation concern like `selected_port`. It
  reads voyage progress through `GameQueries`, never `Domain`.
- No game rule, table or command changes. The world, ChangeSet and
  SettledCheck are untouched.
- Client modules in `assets/js`:
  - `music_policy.js`: pure; identity, continuation and piece choice with an
    injected random source.
  - `music_transitions.js`: pure; the transition state machine, taking events
    with timestamps and returning gain commands.
  - `music_engine.js`: `<audio>` elements, `MediaElementAudioSourceNode`,
    per-piece and master `GainNode`s, and `setValueCurveAtTime` fades.
  - `music.js`: the hook; data attributes, settings, visibility, autoplay
    unlock and the credit strip.
- The desktop client grants remote pages no native APIs; music is plain web
  audio in the webview.

## Testing

### Elixir

- GameLive: each validated explicit event sets the focus kind and identifier;
  each automatic `selected_port` change leaves both unchanged; refresh
  preserves them. Select a port, then preview a destination for a ship at a
  different port and assert the music port stays put. Cover initial focus after
  the first view and fallback when a focused ship disappears. `#music` renders
  the right attributes for a port, a docked, loading or unloading ship, a
  sailing ship, a diverted ship, an arrival and a public ship inspected by a
  visitor.
- `test/docs/music_manifest_test.exs`: every catalogue port appears in exactly
  one palette; the DESIGN.md palette table matches the manifest; every palette
  has at least one port and one voyage track; every credit field is present;
  every file exists and its SHA-256 matches either its content or its LFS
  pointer `oid`.
- Availability: with current approvals and the enable flag, an `OggS` file is
  available; an LFS pointer is not. Missing or stale listening approvals and
  a false enable flag hide the control. A source, encoded hash or playback
  recipe change invalidates the appropriate approval.
- `test/docs/music_approvals_test.exs`: every approval in
  `priv/music/approvals.json` binds to the current manifest, and a stale
  binding fails; pending approvals pass and are listed. Preparation leaves the
  approvals file byte-for-byte unchanged.
- Serving: a byte-range request to an audio fixture returns HTTP 206 with the
  expected `Content-Range` and bytes; a full request returns the complete file.
- `/music/credits` renders every track's credits.
- Gettext extracted, Arabic catalogue complete.

### JavaScript

Node tests in `test/desktop`, following the existing hook tests:

- Transitions, with literal timestamps from DESIGN.md: a stable selection fades
  out from 0 to 5 s and in from 3 to 5 s; a reselection at 2 s is silent at 5 s
  and fades in from 6 to 8 s; a change while silent restarts the three-second
  wait; a change during a fade-in fades out from the current gain; an
  unchanged identity changes nothing, including pending transitions. Selection
  just before track end preserves its deadline and suppresses automatic starts;
  selection during an automatic crossfade fades all audible gains. Toggle off
  during a settle, silent wait, selection fade or automatic crossfade cancels
  every pending start. Context updates while off cannot restart playback.
- Policy: shared port palettes; docked ships map to their port; progress 0
  always chooses the origin and progress 1 the destination; no immediate repeat
  when the pool allows.
- Engine, against a fake `AudioContext`: curve samples equal cosine and sine at
  known points; volume maps to `(v / 100)²`; the between-piece crossfade starts
  two seconds before the end; hiding fades out and pauses; return resumes or
  repicks as specified; three consecutive failures stop music. Deferred load,
  seek and `play()` promises cannot advance an incoming gain or show a credit
  before playback. A delayed start receives a fresh two-second envelope;
  reselection while awaiting it obeys the silent wait. Stale fulfillment after
  reselection, disable, hide or destruction is paused without a credit. Cover
  timeouts and rejected playback promises, preparation ten seconds before
  track end, translated selection entries and repeats starting at encoded zero.
- Hook: first-launch defaults; persisted toggle and volume; throwing storage
  tolerated; credit template filled and hidden after eight seconds.

### Browser

`test/browser/music.mjs`: in the test environment, configuration points the
hook at a fixture manifest and a tone clip of a few kilobytes outside the LFS
pattern, so CI runs without LFS. It covers the gesture unlock, a port click
changing context, the credit strip and its link, and toggle and volume
surviving a reload. Delay an audio response beyond the settling deadline and
check the late fade and credit timing. Disable or change context during that
delay and assert that the stale piece never becomes audible or receives a
credit. The fixture enablement is test-only and cannot bypass the production
release gate.

### Manual probes

- The Render LFS download measurement.
- Ogg Opus playback in the macOS desktop webview. If it fails, stop: an AAC
  fallback changes the asset design.
- A listening check of rapid reselection in a real browser.
- Final encoded entries, whole-recording repeats and cross-region handoffs,
  recorded against their hashes for the release listening gate.
- Byte-range playback and entry seeking through the Render serving path.

Each new guard or test is broken once to confirm a failure, for example by
letting an automatic selection set focus, swapping the fade curves or removing a
port from the manifest.

## Delivery

1. Infrastructure: LFS setup, hooks, `.gitattributes`, roster, preparation,
   manifest, credits generator, static serving, availability check and the
   manifest test. Keep production playback disabled; push and measure a Render
   deploy's LFS download and verify range responses.
2. Server: `music_focus`, the `#music` element and its GameLive tests.
3. Client: policy, transitions, engine and hook with their tests; header
   control, popover and credit strip with gettext.
4. Credits page, browser contract, desktop probe, documentation and full gates.
5. Complete and record the release listening gate, verify availability against
   the approved roster and playback recipe, then enable production playback.

Documentation in the same changes: DESIGN.md gains the identity rules, piece
choice, between-piece crossfade, volume mapping, switching-away details and
credits page from this spec; `scripts/gen-ux-inventory.py` and its tripwire
follow, and the inventory is regenerated. IMPLEMENTATION.md, architecture.md,
deploying.md and the music documents' status sections are updated.

## Tuning left open

- Initial volume (30 on the slider).
- Loudness target (-20 LUFS) and Opus bitrate (64 kbps).
- Credit strip duration (eight seconds).
- Between-piece crossfade length (two seconds).
