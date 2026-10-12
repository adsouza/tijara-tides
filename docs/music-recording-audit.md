# Music recording audit

Local-file index updated on 11 October 2026 after the authorized generated-audio
cleanup; see [local evidence and previews](#local-evidence-and-previews). The
shipped soundtrack is prepared by `scripts/prepare-music.py` from
`scripts/music-roster.json`, and release listening approvals are recorded in
`priv/music/approvals.json`, which binds each decision to the exact files it
was made against.

Checked on 10 October 2026. The initial audit covers 32 recordings from the
accepted port and voyage leads and retained alternatives in the
[shortlist](music-shortlist.md). It does not choose the final 24-track roster.
Supplemental auditions for Listening to Our Sounds, Dhaka, Beachfront
Celebration and Sideways Samba are recorded separately below. Other
exploratory reserves are outside this pass. The player requested reconsidering
Dark Red Wine after its loop audition, then accepted Beachfront Celebration as
the port replacement after its full-recording audition. Setting Sail remains
the voyage preference. Epic Cinematic Salsa remains an alternative; Atlas •
Panama is excluded after the player confirmed vocals in its review clip. The
player also requested reconsidering Tropical Contact after its loop audition,
then accepted Sideways Samba as the port replacement after its full-recording
audition. Up In The Air remains the voyage candidate.

Source grants fit commercial game use and edits with the conditions below.
Exact files were obtained, hashed and decoded; 38 files were screened, counting
the supplied loop variants, Folk_Arabian intro and Korean MP3/WAV pair. This is
an automated audio audit, not a completed listening sign-off. No track is marked
as proven free of lyrics, wordless vocals, choir or chants.

## Findings that affect preparation

- Thirty of the 32 recordings produced no voice flag at the screening threshold.
  The player heard entirely instrumental music in Conquer The Great Sands's
  flagged passage and vocals in Atlas • Panama's passage. Retain the former
  and exclude the latter. An absent flag does not prove absent vocals.
- The four PeriTune pieces include dedicated loop packages. The player approved
  Sakuya3's original raw Ogg join after replay, selecting it for use. Its
  accepted revision remains an alternative. Ametsuchi's, Desert2's and
  Folk_Arabian's raw Ogg joins are also approved and selected. Folk_Arabian's
  separate intro-to-loop entry is approved: play its intro once, then its loop.
- Both Jonathan Shaw legacy tracks contain highly correlated repeated sections.
  Both raw joins are approved and selected. Loop points are recorded below.
  Conquer The Great Sands's Ogg also supplies numeric loop points; the player
  rejected its raw tagged transition and approved the revised 96-second
  active-passage repeat. Repeat edits and listening decisions for the other
  retained recordings are recorded below.
- Full recordings range from -24.07 to -6.46 LUFS: a 17.61 dB spread. Gain
  matching is necessary before comparing or crossfading them. Some lossy files
  have reconstructed true peaks above 0 dBTP; this is a preparation concern,
  not by itself proof of audible clipping in the source.
- Beautiful Korea's original WAV is 105.738 seconds and its matching MP3 is
  105.796 seconds. The listing's 2:39 duration does not describe these files.
  The downloaded MP3 and player MP3 have identical hashes. Both decode without
  reported errors; the duration mismatch alone does not establish truncation.
- Five Pixabay leads display Content ID registration. Their certificate links
  are recorded below, but the PDFs could not be exported in this session.

## Exact recording results

Durations below are measured from decoded PCM, avoiding estimated MP3 container
durations. All inspected files decode without FFmpeg error output. All are
stereo. Eight recordings are at 48,000 Hz: Gugak #72, Indian, Epic Indian
Orchestral Fusion, Epic Nusantara, Arabic Music, Atlas • Greece, Atlas • Panama
and the Korean gayageum alternative. The others are at 44,100 Hz. The table
uses the free full recording; the additional supplied loop files are separate.

| Recording and creator | Assignment | Duration | LUFS | Source grant | Voice screen |
|---|---|---:|---:|---|---|
| [Shenyang][shenyang] — Kevin MacLeod | Chinese coast port | 2:31.458 | -13.22 | CC4 | No flag; listening pending |
| [Imperial China Cinematic][imperial-china] — Shane Ivers | Chinese coast voyage | 3:21.665 | -10.12 | CC4 | No flag; listening pending |
| [Sakuya3][sakuya3] — PeriTune / Sei Mutsuki | Japanese port | 3:20.910 | -9.18 | CC4 | No flag; listening pending |
| [Ametsuchi][ametsuchi] — PeriTune / Sei Mutsuki | Japanese voyage | 2:30.070 | -8.90 | CC4 | No flag; listening pending |
| [국악 배경음악 #72 (Gugak Background Music #72)][gugak72] — 공유마당 (GongU Madang) | Korean port | 1:00.504 | -15.07 | CC4 | No flag; listening pending |
| [Beautiful Korea(뷰티플 코리아)][beautiful-korea] — 윤영현 | Korean voyage | 1:45.738 | -6.46 | CC4 | No flag; listening pending |
| [Korean traditional-cinematic piece with gayageum][korean-gayageum] — RibhavAgrawal | Korean voyage alternative | 2:04.752 | -15.00 | PB | No flag; listening pending |
| [Hoi An Ancient Charm][hoi-an] — VPRODMUSIC_Asia_BGM | Southeast Asian port | 2:28.846 | -14.08 | PB | No flag; listening pending |
| [Epic Nusantara - Free Gamelan Music from Indonesian][epic-nusantara] — fiikuri | Southeast Asian voyage | 2:37.776 | -10.97 | PB | No flag; listening pending |
| [Indian][sub-clair-indian] — Sub_Clair | South Asian port | 2:01.248 | -9.48 | PB | No flag; listening pending |
| [Epic Indian Orchestral Fusion][epic-indian-fusion] — Alejandro Piñero Amerio (vjgalaxy) | South Asian voyage | 3:37.800 | -11.77 | PB | No flag; listening pending |
| [Middle East Ballad][middle-east-ballad] — Abydos_Music | Arabian Gulf port | 2:38.877 | -10.45 | PB | No flag; listening pending |
| [Conquer The Great Sands][conquer-sands] — Darren Curtis | Arabian Gulf voyage | 2:31.000 | -13.20 | DC | Flagged passage reviewed: instrumental; full listen pending |
| [Arabic Music][kiravale-arabic] — kiravale | North African port | 2:04.824 | -10.18 | PB | No flag; listening pending |
| [Desert2][peritune-desert2] — PeriTune / Sei Mutsuki | North African port | 4:04.160 | -8.36 | CC4 | No flag; listening pending |
| [Folk_Arabian][folk-arabian] — PeriTune / Sei Mutsuki | North African voyage | 1:51.534 | -9.21 | CC4 | No flag; listening pending |
| [Dellasera][dellasera] — Shane Ivers | Mediterranean port | 4:04.584 | -13.82 | CC4 | No flag; listening pending |
| [Atlas • Greece][atlas-greece] — Vadim_Makes_Sound | Mediterranean voyage | 1:49.920 | -14.56 | PB | No flag; listening pending |
| [Cinematic Latin Music][cinematic-latin] — Sonican | Mediterranean voyage | 2:10.247 | -8.36 | PB | No flag; listening pending |
| [Lord of the Land][lord] — Kevin MacLeod | Northern Frangistan port | 3:06.488 | -24.07 | CC4 | No flag; listening pending |
| [Townsong][townsong] — Alexander Nakarada | Northern Frangistan port | 3:05.442 | -9.94 | CC4 | No flag; listening pending |
| [Home Was You][home] — Scott Buckley | Northern Frangistan port alternative | 4:29.400 | -14.41 | CC4 | No flag; listening pending |
| [Pathfinder][pathfinder] — Scott Buckley | Northern Frangistan voyage | 3:24.322 | -14.00 | CC4 | No flag; listening pending |
| [Swing Train - Big Band Miller Style][swing-train] — JuliusH | North American port | 1:57.211 | -16.87 | PB | No flag; listening pending |
| [Market on the Sea][market-sea] — Jonathan Shaw (InspectorJ) | North American port | 2:26.155 | -15.95 | CC3 | No flag; listening pending |
| [The World At Your Door][jshaw-world] — Jonathan Shaw (InspectorJ) | North American voyage | 2:41.698 | -12.59 | CC3 | No flag; listening pending |
| [Dark Red Wine][shaw-reggae] — Jason Shaw | Caribbean port | 3:22.736 | -15.69 | CC4 | No flag; listening pending |
| [Setting Sail][setting-sail] — Alexander Nakarada | Caribbean voyage | 2:07.768 | -10.87 | CC4 | No flag; listening pending |
| [Atlas • Panama][atlas-panama] — Vadim_Makes_Sound | Excluded Caribbean alternative | 3:12.552 | -14.50 | PB | Player confirmed vocals; excluded |
| [Epic Cinematic Salsa][epic-salsa] — Sonican | Caribbean alternative | 4:16.653 | -11.62 | PB | No flag; listening pending |
| [Tropical Contact][shaw-lofi] — Jason Shaw | Brazilian port | 3:25.061 | -11.83 | CC4 | No flag; listening pending |
| [Up In The Air][brazil-up-in-air] — DonnySombrero | Brazilian voyage | 3:12.914 | -11.96 | PB | No flag; listening pending |

## License conditions and credits

**CC4** means [CC BY 4.0][cc4]; **CC3** means [CC BY 3.0 Unported][cc3].
Both permit commercial redistribution and adaptation with the required credit
and license notice. Include the title, creator, source and license URL, retain
supplied notices, and describe trimming, gain adjustment, loop editing and
fades. Do not apply asset terms or effective DRM that restrict the licensed
freedoms. These permissions concern the music assets; they do not require the
game's code to use a Creative Commons license.

The exact MacLeod track pages generate CC BY 4.0 notices. His older copyright
explanation links a 3.0 license; use the track-specific 4.0 grant for these
downloads. [Audionautix][audionautix-faq] identifies Jason Shaw's catalog as
available for commercial creations with credit; the track catalog footers link
CC BY 4.0.

The [PeriTune terms][peritune-terms] explicitly retain CC BY 4.0 for releases
through February 2026. These four pieces were released in 2016–2018. Keep that
older grant with the files; do not substitute the newer custom terms or a paid
WAV purchase. Credit PeriTune / Sei Mutsuki (むつき醒).

The [Silverman][imperial-china] and [CreatorChords][townsong] track pages attach
CC BY 4.0 to their free MP3s. Credit Shane Ivers / silvermansound.com or
Alexander Nakarada / creatorchords.com, respectively. CreatorChords' [FAQ][nakarada-faq]
allows editing and explains attribution-based YouTube claims.

[Buckley's instructions][buckley-use] permit free commercial use and adaptation
of the library MP3s with credit. Use the selected full mixes. Give Scott Buckley,
CC BY 4.0 and scottbuckley.com.au in the game credits; official game videos also
need credit in their YouTube descriptions to avoid attribution-based claims.

Jonathan Shaw's own [Market][market-sea] and [World][jshaw-world] OpenGameArt
uploads offer CC BY 3.0 for the selected legacy recordings. Both ZIPs also
contain the same custom EULA, dated 2 May 2019. It grants worldwide,
non-transferable, royalty-free use and public distribution in commercial and
noncommercial projects with credit: title, Jonathan Shaw and jshaw.co.uk.
It does not explicitly address adaptation; rely on the separate CC BY 3.0
offer for editing and preserve both notices. Its linked current EULA URL
returned HTTP 404 during this check. Keep these legacy downloads distinct from
paid Reborn recordings and other formats.

Each ZIP contains an MP3 and license PDF. World also contains a two-page README
describing at least one seamless repeat followed by natural trailing reverb.
Neither package supplies numeric loop points. The PDF hashes are recorded below.

**DC** is Curtis's custom Materials Release, not a Creative Commons license.
The official [free catalog][conquer-sands] links the inspected ZIP. Its release
names Conquer the Great Sands and visibly bears Darren Curtis's signature. It
permits perpetual worldwide project use, editing, looping and synchronization,
with compensation consisting of credit to Darren Curtis. It excludes standalone
resource resale and false authorship. Producer/project/date fields are blank in
the supplied template; they were not filled or signed here. Preserve the PDF
and its source alongside the audio. The [FAQ][curtis-faq] confirms free commercial
game use with credit and the exclusion of music outside that free catalog.

**PB** is the [Pixabay Content License][pixabay-terms], not CC BY or public domain.
The inspected recording pages display that license. It permits commercial use
and modification when incorporated into the game; do not redistribute a
standalone soundtrack or stock-music resource. Attribution is optional under
these terms, but our design credits every track and its credited creator.
The platform does not warrant clearance of third-party samples or other rights.
This audit verifies the offered grant and file identity, not an independent
chain of title for every composition, performance, sample or AI service.

The main player sections explicitly label Epic Indian Orchestral Fusion, Arabic
Music, Atlas • Greece and Atlas • Panama as AI generated. No AI label was
observed on the other inspected main player sections; that is not proof of
human-only production. AI-generated recordings remain eligible under the
player's accepted policy.

The following main player sections display Content ID registration. The visible
download dialogs offer these certificates. Browser exports timed out and direct
requests returned HTTP 403, so no certificate PDF is represented as saved.
Retain the actual certificates before depending on them in a video claim.

| Recording | Certificate offered |
|---|---|
| [Hoi An Ancient Charm][hoi-an] | [Download certificate](https://pixabay.com/music/147064/license/) |
| [Indian][sub-clair-indian] | [Download certificate](https://pixabay.com/music/610511/license/) |
| [Arabic Music][kiravale-arabic] | [Download certificate](https://pixabay.com/music/593673/license/) |
| [Cinematic Latin Music][cinematic-latin] | [Download certificate](https://pixabay.com/music/523433/license/) |
| [Up In The Air][brazil-up-in-air] | [Download certificate](https://pixabay.com/music/499093/license/) |

## Vocal screening and listening checks

A local [YAMNet ONNX conversion][yamnet] classified complete decoded recordings
in 30-second chunks at 16 kHz mono. The screen covers speech, singing, synthetic
singing, choir, chant, mantra, humming and other human vocalization classes.
Frames cover 0.96 seconds with a 0.48-second hop. Any selected class score of
0.30 or higher creates a review flag. The threshold is a review heuristic, not
a validated pass/fail test for this soundtrack.

Controls classified digital silence as Silence (1.00), a 1 kHz tone as Beep
(0.90), and a locally generated spoken sentence as Speech (0.994 mean score).
These check that inference and label mapping work; they do not establish the
screen's recall for quiet wordless vocals under an orchestra. Scores are model
outputs, not calibrated probabilities that a person is present.

| Recording | Flagged source interval | Strongest label/score |
|---|---|---|
| [Conquer The Great Sands][conquer-sands] | 142.08–143.04 s | Chant, 0.452 |
| [Atlas • Panama][atlas-panama] | 175.92–177.36 s | Singing, 0.552 |

Focused clips include three seconds of context before and after each flagged
passage. They are in the local preview index. On 10 October 2026 the player
described the Conquer The Great Sands clip as entirely instrumental and
confirmed vocals in the Atlas • Panama clip. Atlas • Panama is therefore
excluded under the instrumental-only requirement. Conquer The Great Sands
remains selected; the player's result resolves its flagged passage rather than
certifying the complete recording.

Every selected final asset still needs a complete listen for sung words,
wordless voices, chants and choir. This session has no audio-listening tool;
the perceptual results above are the player's reports, not conclusions drawn
from tags, waveforms or classifier scores.

## Loops

These supplied PeriTune Ogg files contain no numeric loop tags. Their decoded
sample counts define the candidate full loop. Folk_Arabian's intro is an
additional 46,585 samples (1.056349 s), played once before its loop.

| Piece | Loop duration | Decoded samples at 44,100 Hz | Seam decision |
|---|---:|---:|---|
| PerituneMaterial_Sakuya3_loop.ogg | 98.823537 s | 4,358,118 | Raw join approved and selected |
| PerituneMaterial_Ametsuchi_loop.ogg | 112.500000 s | 4,961,250 | Raw join approved and selected |
| PerituneMaterial_Desert2_loop.ogg | 120.320000 s | 5,306,112 | Raw join approved and selected |
| PerituneMaterial_Folk_Arabian_loop.ogg | 54.084512 s | 2,385,127 | Raw join approved and selected |

The raw end-to-start sample jump is largest for Sakuya3: about 3.94 times the
99th percentile of adjacent sample changes within that loop. This is a click
risk marker, not a perceptual verdict. Raw seam previews and versions with
five-millisecond fades at both boundaries are available for all six candidate
loops. The fades keep loop length unchanged and bring the seam endpoints to
zero. Listen for a click, a tiny dip, rhythm disruption or a mismatched reverb
tail before choosing the final edit. The intro clip is not itself a repeat.

On 10 October 2026 the player heard the original raw Sakuya3 join again, said
it sounded fine and approved its use. Repeat the complete supplied Ogg buffer
of 4,358,118 samples without boundary fades. This supersedes the earlier
uncertain listening verdict. The revised join below was also accepted and
remains an alternative; the five-millisecond fade version was not independently
approved on replay. Complete-recording and repeated-play listening remain open.

The player also approved Ametsuchi's raw seam preview on 10 October 2026 and
selected the supplied Ogg loop for use. Repeat all 4,961,250 decoded samples
without boundary fades. This decision concerns the demonstrated seam; full
vocal absence and repeated background play remain separate listening checks.

The player approved Desert2's raw seam preview on 10 October 2026 and selected
the supplied Ogg loop for use. Repeat all 5,306,112 decoded samples without
boundary fades. Full vocal and repeated-play listening remain outstanding.

The player approved Folk_Arabian's raw seam preview on 10 October 2026 and
selected its supplied Ogg loop. Repeat all 2,385,127 decoded samples without
boundary fades. Its separate 46,585-sample intro plays once before the loop.
The player also approved that entry on 10 October 2026 in the preview where
the loop begins at 1.056349 seconds. The preview uses the same -14.07 dB
audition gain for both files and has no boundary fades. Full vocal and
repeated-play listening remain outstanding.

### Revised Sakuya3 alternative

The full MP3 contains repeated music at a lag of 4,358,118 samples (98.823537 s
at 44,100 Hz). Eight one-second comparisons at 5, 10, 20, 30, 50, 70, 85 and
95 seconds have correlations from 0.9988 to 0.9998. This supports repeating the
same musical passage while moving the join away from the supplied Ogg's file
boundary.

The revision plays the first 295,470 samples (6.7 s) once, then repeats samples
295,470 through 4,653,588 (end exclusive) of the decoded full MP3. Its last
4,410 samples (100 ms) blend into the matching passage immediately before the
loop start. Complementary raised-cosine weights sum to one, avoiding a boost
from adding two nearly identical passages. This edit preserves the 98.823537 s
period and does not insert a settling delay between repeats.

The source passages around the new join correlate at 0.99998. Before audition
gain, the adjacent sample step at the new boundary is 0.00536, matching a normal
step in the original passage; the original Ogg boundary step was 0.47461.
These measurements support the candidate but do not replace listening. The
revised 16-second preview joins at eight seconds. An uninterrupted source
excerpt provides a matching reference. Both use the same -13.82 dB audition
gain. After hearing the revised clip on its own, the player said it sounded
fine. This approves the revised seam preview, while complete-recording and
repeated-play listening remain outstanding.

Revision metadata, original hash, candidate intro/loop files and preview hashes
are preserved in `tmp/music-audit-2026-10-10/sakuya3-loop-revision.json`.

Revised join preview SHA-256:
`48f3e07a3aaee49812c6f7f2d30426ab241406ba07295da223f09e4b3b084aa8`.

Uninterrupted reference preview SHA-256:
`d4781d28754a8ed7bfe7ad68bf73daea4dc00d200b108c92a545fc5337fa3efb`.

### Jonathan Shaw loops

PCM matching found repeated sections in Jonathan Shaw's legacy MP3s. Candidate
points below use an already decoded buffer; they must not be copied blindly
into a different encode or a compressed-file seek API. Play the initial ten
seconds once, then repeat the candidate section.

| Recording | Start sample | End sample (exclusive) | Period | Repeated one-second PCM correlations | Seam decision |
|---|---:|---:|---:|---|---|
| Market on the Sea - MP3.mp3 | 441,000 | 3,527,846 | 69.996508 s | 0.9947, 0.9967, 0.9988, 0.9972 | Raw join approved and selected |
| The World At Your Door MP3.mp3 | 441,000 | 3,734,392 | 74.680091 s | 0.9948, 0.9956, 0.9938, 0.9969 | Raw join approved and selected |

The comparisons sample repeated passages at 5, 10, 20 and 30 seconds and agree
strongly. The measurements establish repeat periods; listening decisions are
recorded separately. Jonathan Shaw's source pages and World's bundled README
also explicitly describe repeated sections followed by natural reverb tails.

On 10 October 2026 the player approved Market on the Sea's raw seam preview
and selected that loop. Play the first 441,000 decoded samples once, then
repeat the 3,086,846-sample section above without boundary fades. The initial
entry follows the original recording contiguously. Full vocal and
repeated-play listening remain outstanding.

The player also approved The World At Your Door's raw seam preview on
10 October 2026 and selected that loop. Play the first 441,000 decoded samples
once, then repeat the 3,293,392-sample section above without boundary fades.
Its initial entry is also contiguous with the source. Full vocal and
repeated-play listening remain outstanding.

### Other recordings

#### Shenyang approved repeat

The strongest five-second repeat-template match in this pass yielded a lag of
59.076916 seconds, with one-second correlations ranging from 0.645 to 0.879
across six checked passages. This does not establish a matching section for a
raw loop. A same-track crossfade candidate instead overlaps the complete
recording's last four seconds with its first four seconds, preserving its
ending and opening without trimming the reverb tail.

The 16-second audition starts eight seconds before the source ends. Incoming
music begins at clip time four seconds; the sine/cosine crossfade finishes at
eight seconds. Routine repeats have no selection settling delay. This approach
would start each repeat 147.457959 seconds after the previous start, using
6,502,896 samples at 44,100 Hz. The preview uses constant -9.78 dB audition
gain. The player found the blend between four and eight seconds fine, but a
brief interlude immediately before four seconds made the entry slightly
jarring. That original repeat is therefore not approved.

The source hash, exact outgoing start sample, curve, timing, gain and preview
hash are preserved in
`tmp/music-audit-2026-10-10/shenyang-mp3-repeat-crossfade.json`.

The revised candidate advances the blend by 162,831 samples (3.692313 s),
equivalent to eight beats at the source's tagged 130 BPM. It starts the
incoming recording at source time 143.765646 s and finishes fading the old
recording at 147.765646 s, making the new opening enter before the reported
interlude. The source's final ending is faded out early. The four-second
sine/cosine blend, constant audition gain and absence of a settling delay
are retained; the repeat interval becomes 6,340,065 samples (143.765646 s).

The revised 16-second clip demonstrates the blend from clip time four to
eight seconds. On 10 October 2026 the player approved and selected this
version. Its source points, timing and preview hash are recorded in
`tmp/music-audit-2026-10-10/shenyang-repeat-earlier-crossfade.json`.
Full vocal and repeated-play listening remain outstanding.

Selected preview SHA-256:
`c1df922a998f3ef751c04d365d94b241670724ca5f6e15bd6f974513827bd3a9`.

#### Imperial China Cinematic approved interior loop

The five-second repeat-template search in this pass produced a strongest
correlation of 0.0494. It did not establish a matching section for a raw loop.
The complete recording has 8,893,440 decoded samples at 44,100 Hz
(201.665306 s), including about 4.765 seconds below -50 dBFS at its ending.

The candidate finishes fading the outgoing music 211,680 samples (4.8 s)
before the file ends, avoiding that quiet tail. This advance is eight beats
at the source's tagged 100 BPM. Incoming music starts from the recording's
beginning at source elapsed sample 8,505,360 (192.865306 s); the outgoing
music reaches silence at sample 8,681,760 (196.865306 s). The repeat interval
is 8,505,360 samples. The four-second blend uses sine/cosine gains and has
no selection settling delay.

The 16-second preview starts at source sample 8,328,960 (188.865306 s) and
demonstrates the blend from clip time four to eight seconds. It uses constant
-12.88 dB audition gain and has a measured sample peak of -16.80 dBFS.
The player found this acceptable only because both sides sounded silent. It
is not selected as a continuous musical repeat. Half-second source windows
during the outgoing blend measure around -39 to -42 dBFS RMS before audition
gain, while the opening is also subdued. Trimming only the ending below
-50 dBFS therefore did not avoid the perceived pause. Source identity, exact
points and preview metadata are preserved in
`tmp/music-audit-2026-10-10/imperial-china-mp3-repeat-crossfade.json`.

Candidate preview SHA-256:
`a4e2444db54270966f460f96c77c5d70e39ed78dfd4406b5d8bce3ca12fb3277`.

The revised candidate plays the first 2,205,000 samples (50 s) once, then
repeats source samples 2,205,000 through 6,967,800 (end exclusive), a
4,762,800-sample period (108 s). The last 176,400 samples (four seconds) of
the loop blend source seconds 154–158 into source seconds 46–50. Their mono
PCM correlation is 0.8804: they share musical material but are not identical
audio. Complementary raised-cosine gains sum to one to avoid boosting these
correlated passages. This internal loop edit preserves the 108-second period
and has no settling delay. Selection transitions retain their selected
sine/cosine curves.

The revised 16-second preview blends from clip time four to eight seconds,
then continues from source second 50 at eight seconds. The prefix enters the
loop contiguously. Its constant audition gain remains -12.88 dB and its sample
peak is -12.50 dBFS. On 10 October 2026 the player approved and selected this
loop. Full vocal and repeated-play listening remain outstanding. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/imperial-china-loop-revision.json`.

Approved revised preview SHA-256:
`0a26ea5e14ab7a6bb101f87a47c2fce2b608af4794509787cb4bfba03674ee00`.

#### Gugak Background Music #72 repeat candidate

No raw loop has been verified for this short Korean port recording. The
candidate overlaps its ending with its opening using a four-second
sine/cosine blend. Incoming music starts at source elapsed sample 2,664,192
(55.504 s at the source's 48,000 Hz rate); the outgoing recording finishes
fading at sample 2,856,192 (59.504 s). This finishes one second before the file
ends, omitting its quiet tail. The repeat interval is 2,664,192 samples
(55.504 s), with no selection settling delay.

The 16-second preview starts at source sample 2,472,192 (51.504 s), with the
blend from clip time four to eight seconds. Constant audition gain is
-7.93 dB and the measured sample peak is -8.00 dBFS. This is a musical
listening candidate, not an established seamless loop. Its exact source
identity, points and preview metadata are preserved in
`tmp/music-audit-2026-10-10/gugak72-mp3-repeat-crossfade.json`.

Candidate preview SHA-256:
`f3d4a93f39631374511384cac546104c4fac44b66568deb220745b7a11fe383d`.

On 10 October 2026 the player reported silence before clip time four seconds
and found the repeat somewhat repetitive. This repeat is not approved. The
Korean port replacement search is reopened; #72's earlier acceptance of the
piece does not constitute approval for this edit.

#### Listening to Our Sounds replacement candidate and repeat

[우리네 소리를 듣다 (Listening to Our Sounds)](https://gongu.copyright.or.kr/gongu/wrt/wrt/view.do?menuNo=200020&wrtSn=13048780)
by 임다솔 (Im Dasol) is a new audition lead, outside the original 32-recording
batch. On 10 October 2026 its live grant linked directly to CC BY 4.0. The page
lists Korean traditional-instrument, keyboard and percussion tags, with slow
and sad mood tags. The title's English rendering here is a working translation.
The player accepted its musical fit and found the prepared repeat passable;
explicit vocal absence and repeated-play suitability still need listening.

The catalog lists 2:25. Its browser player shows 1:53, and the decoded source
contains 5,008,896 samples at 44,100 Hz (113.580408 s), in stereo. FFprobe
estimates 3:48.24 from bitrate and warns that this estimate may be inaccurate;
it is not the decoded duration. This file therefore requires decoded-buffer
timing.

The complete audition applies one constant gain based on the same -23 LUFS
target and -2 dBTP source ceiling as the other previews. It has no loop edit.
Source identity, source/player discrepancies, objective voice screening and
preview metadata are preserved separately in
`tmp/music-audit-2026-10-10/im-dasol-our-sounds-analysis.json`. The original
32-recording batch statistics above remain unchanged.

The audition uses -6.05 dB gain, with a measured sample peak of -6.14 dBFS.
The same objective voice screen yields no flag at its 0.30 threshold; its
highest voice-class score is Singing at 0.1151. That does not establish the
absence of vocals. Source file:
`tmp/music-audit-2026-10-10/im-dasol-our-sounds-mp3.mp3`.

Source SHA-256:
`b911952759ef2e1257e622d165a2efe2993c64a5e17a33e506469f2d5ade07ff`.

Complete audition SHA-256:
`bce05b17a6db37589c3c159a24097568da3b0723e7253286ed9e3a94da203ab1`.

On 10 October 2026 the player accepted this as the Korean port replacement
candidate after hearing the complete audition. This establishes preference
over #72; explicit vocal absence remains open. The repeat decision is recorded
below.

The repeat candidate plays source samples zero through 308,700 (seven seconds)
once, then repeats samples 308,700 through 4,321,800 (end exclusive), a
4,013,100-sample section (91 seconds at 44,100 Hz). Its last 176,400 samples
(four seconds) blend source seconds 94–98 into source seconds 3–7 with
sine/cosine gains. The prefix enters the section contiguously. Each repeat
therefore bypasses the opening lead-in and fades before the long quiet ending.
No identical repeated PCM section has been established. Routine repeats have
no selection settling delay.

The 16-second preview begins at source second 90, blends from clip time four
to eight seconds, then continues at source second seven. Its constant audition
gain is -6.05 dB and its measured sample peak is -9.65 dBFS. Source points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/im-dasol-our-sounds-loop.json`.

On 10 October 2026 the player found the repeat passable but less smooth than
the earlier examples. This edit is accepted and selected for now with that
qualification, rather than recorded as a clean seam. Explicit vocal absence
and repeated-play listening remain outstanding.

Accepted repeat preview SHA-256:
`fce4dfca2767ac44f9c27a777b2e65acaee35eb8175341049ba5af890d633f0f`.

#### Beautiful Korea approved repeat

The exact WAV has 4,663,032 decoded samples at 44,100 Hz (105.737687 s), with
about eight seconds below -50 dBFS at the ending. No matching section for a raw
loop has been established. The candidate instead overlaps active outgoing
music with the opening: incoming playback begins at source elapsed sample
3,969,000 (90 s), and the outgoing recording finishes fading at sample
4,145,400 (94 s), before the quiet ending. This advances the blend by 517,632
samples (11.737687 s) relative to an end-aligned fade. The repeat interval is
3,969,000 samples (90 s). The four-second blend uses sine/cosine gains with
no selection settling delay.

The 16-second preview begins at source sample 3,792,600 (86 s) and blends
from clip time four to eight seconds. Constant audition gain is -16.54 dB,
with a measured sample peak of -15.09 dBFS. On 10 October 2026 the player
approved and selected this repeat. Full vocal sign-off and repeated-play
listening remain outstanding. Exact source identity, points and preview
metadata are preserved in
`tmp/music-audit-2026-10-10/beautiful-korea-original-repeat-crossfade.json`.

Approved repeat preview SHA-256:
`9d66bee0d4bd91ad3ffeeae45c7378b772aaf77af03c8dd3d34be0e55ab1a586`.

#### Korean traditional-cinematic piece with gayageum approved revised loop

RibhavAgrawal's accepted Korean voyage alternative has 5,988,096 decoded
samples at 48,000 Hz (124.752 s). No matching section for a raw loop has been
established. Its candidate begins incoming playback at source elapsed sample
5,688,000 (118.5 s) and finishes fading the outgoing music at sample
5,880,000 (122.5 s), before the closing decay. This advances the blend by
108,096 samples (2.252 s) relative to an end-aligned fade. The repeat interval
is 5,688,000 samples (118.5 s). The four-second blend uses sine/cosine gains
with no selection settling delay.

The 16-second preview starts at source sample 5,496,000 (114.5 s) and blends
from clip time four to eight seconds. Constant audition gain is -8.00 dB and
the measured sample peak is -9.40 dBFS. This initial candidate was not approved.
Exact source identity, points and preview metadata are preserved in
`tmp/music-audit-2026-10-10/korean-gayageum-mp3-repeat-crossfade.json`.

Candidate repeat preview SHA-256:
`de723828ea1e74630fc7d995d8baac0f6cfb2516ecd4d62a35bdfe3db33b5dd6`.

The player found the part around four seconds fine but reported fading to
silence around eight seconds. This original repeat is not approved. In the
preview, the quarter-second window beginning at eight seconds measures
-38.4 dBFS RMS, compared with -23.7 dBFS at 8.5 seconds. That marked dip is in
the incoming opening phrase after the outgoing music has faded away.

The revision plays source samples zero through 1,344,000 (28 s) once, then
repeats samples 1,344,000 through 5,880,000 (end exclusive), a 4,536,000-sample
section (94.5 s at 48,000 Hz). Its last 192,000 samples (four seconds) blend
source seconds 118.5–122.5 into source seconds 24–28 using sine/cosine gains.
The outgoing passage and fade duration are retained, while the incoming music
now comes from a fuller section. The initial prefix enters the loop
contiguously. Routine repeats have no selection settling delay.

The revised 16-second preview blends from clip time four to eight seconds,
then continues at source second 28. Its constant audition gain remains
-8.00 dB and its measured sample peak is -9.53 dBFS. The player approved this
revision: "Yes, use this version." It is the selected repeat for this Korean
voyage alternative. Explicit vocal sign-off and repeated-play listening remain
open. Exact points, prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/korean-gayageum-loop-revision.json`.

Approved revised preview SHA-256:
`c6c319f379750a51303fe39cf16c0b780e0c42ff6eda9fc961d5689ce74fa8b2`.

#### Hoi An Ancient Charm approved repeat

The exact Southeast Asian port recording has 6,564,096 decoded samples at
44,100 Hz (148.845714 s). Its opening has 2.4 seconds below -50 dBFS, and its
ending has 1.346 seconds below that threshold. No raw loop has been verified.
The candidate plays source samples zero through 1,940,400 (44 s) once, then
repeats samples 1,940,400 through 6,174,000 (end exclusive), a 4,233,600-sample
section (96 s). The initial prefix enters the loop contiguously.

The final 176,400 samples (four seconds) blend source seconds 136–140 into
source seconds 40–44 using sine/cosine gains. This avoids the closing break
and decay, while returning to an active earlier passage. Routine repeats have
no selection settling delay. The original opening is retained only in the
initial prefix.

The 16-second preview blends from clip time four to eight seconds, then
continues at source second 44. Its constant audition gain is -8.92 dB and its
measured sample peak is -9.90 dBFS. The player approved this loop: "Yes, use
this loop." It is selected for Southeast Asian ports. Explicit vocal sign-off
and repeated-play listening remain open. Exact points, prepared intro/loop
files and hashes are preserved in
`tmp/music-audit-2026-10-10/hoi-an-loop.json`.

Approved preview SHA-256:
`73e44c088f5d748348532a576ca313a9b2162a8737b4a4feab01eb19ce040638`.

#### Epic Nusantara approved repeat

The exact Southeast Asian voyage recording has 7,573,248 decoded samples at
48,000 Hz (157.776 s). No raw loop has been verified. The candidate plays the
first 1,344,000 samples (28 s) once, then repeats source samples 1,344,000
through 7,268,571 (end exclusive), a 5,924,571-sample section (123.4285625 s).
The initial prefix enters the loop contiguously.

Its final 192,000 samples (four seconds) blend source seconds
147.4285625–151.4285625 into source seconds 24–28, ahead of the closing decay.
Normalized mono waveform correlation between these passages is approximately
0.552; this identifies a similar passage, not an exact raw repeat. The blend
uses sine/cosine gains with no selection settling delay.

The 16-second preview blends from clip time four to eight seconds, then
continues at source second 28. Its constant audition gain is -12.03 dB and
its measured sample peak is -10.76 dBFS. The unattenuated blended float loop
peaks at +1.27 dBFS; the constant audition gain preserves headroom. Apply that
gain before converting the prepared float files to an integer audio format
or playing them. The player approved this loop: "Yes, use this loop." It is
selected for Southeast Asian voyages. Explicit vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in
`tmp/music-audit-2026-10-10/epic-nusantara-loop.json`.

Approved preview SHA-256:
`c99449de7cdd52ad70abebbef9b1ca317cf82f201180e44fc748f0a2d9f53671`.

#### Indian by Sub_Clair initial repeat not approved

The exact South Asian port recording has 5,819,904 decoded samples at
48,000 Hz (121.248 s). No raw loop has been verified. The candidate plays
the first 768,000 samples (16 s) once, then repeats source samples 768,000
through 5,068,799 (end exclusive), a 4,300,799-sample section (89.599979 s).
The initial prefix enters the loop contiguously.

Its final 192,000 samples (four seconds) blend source seconds
101.599979–105.599979 into source seconds 12–16. This returns the start of the
closing passage to an active earlier section and omits the long closing
decay. Normalized mono waveform correlation between these passages is
approximately 0.298; no exact raw repeat is claimed. The blend uses
sine/cosine gains with no selection settling delay.

The 16-second preview blends from clip time four to eight seconds, then
continues at source second 16. Its constant audition gain is -13.52 dB and
its measured sample peak is -11.96 dBFS. The unattenuated blended float loop
peaks at +1.56 dBFS; apply the constant audition gain before integer audio
conversion or playback to preserve headroom. The player reported that the
transition needs work; this initial candidate is not approved. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/sub-clair-indian-loop.json`.

Candidate preview SHA-256:
`4bb1a6047faa4ef38425822030c8813b875d2f2c034a5d6acf3723a3a6829dad`.

#### Indian by Sub_Clair revised seam approved; variation under review

The revision plays source samples zero through 1,420,800 (29.6 s) once, then
repeats samples 1,420,800 through 4,492,800 (end exclusive), a
3,072,000-sample section (64 s at 48,000 Hz). Its final 192,000 samples
(four seconds) blend source seconds 89.6–93.6 into source seconds 25.6–29.6.
The initial prefix enters the loop contiguously. These fuller passages omit
the closing arrangement change from the repeat.

Normalized mono waveform correlation is approximately 0.625, compared with
0.298 for the initial candidate. The passages' stereo RMS levels differ by
about 0.8 dB, compared with about 1.5 dB for the initial candidate. These
measurements support the revised passage choice; alone, they do not establish a
clean musical seam or an exact raw loop.

The four-second blend uses complementary raised-cosine gains whose sum is
one, to avoid a boost from overlapping correlated music. Routine repeats
have no selection settling delay. This edit does not change the selected
sine/cosine curves for port/ship selection transitions.

The 16-second preview blends from clip time four to eight seconds, then
continues at source second 29.6. Constant audition gain remains -13.52 dB;
the measured sample peak is -13.17 dBFS. The unattenuated float loop retains
the source's +0.51 dBFS sample peak; apply the constant gain before integer
audio conversion or playback. The player called the transition "flawless"
but expressed concern that the loop is somewhat repetitive. The seam is
approved; overall repeat suitability remains under review. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/sub-clair-indian-loop-revision.json`.

Seam-approved revised preview SHA-256:
`9485a0c3d742a3d8cd52c409b59e9280b4147cc0a5a2257c3300e572b8c976e5`.

The seam preview contains only 16 seconds, covering similar passages on both
sides of the join. A separate 128-second audition plays the complete prepared
64-second loop twice, without the initial prefix, to assess variation. Its
first blend runs from clip seconds 60–64; the second pass starts at 64 s.
It retains the constant -13.52 dB gain and measures -13.01 dBFS sample peak.
After hearing the full-repeat audition, the player questioned the song choice
and requested the earlier alternatives. Overall repeat suitability is not
approved; the South Asian port choice is reopened, retaining the revised seam
approval. Explicit vocal sign-off remains open. Exact audition metadata is
preserved in
`tmp/music-audit-2026-10-10/sub-clair-indian-full-audition.json`.

Full-repeat audition SHA-256:
`9871d1c39bc211dd4e64f8a79b30bdeb5dd4e82763abdad881e0846e70b84399`.

#### Dhaka South Asian port alternative audition

The player chose to revisit [Dhaka by Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400003)
after questioning Indian's repeated-play suitability. On 10 October 2026,
the official page identifies sarod, dilruba and drone, describes a melodic
northern Indian influence, and supplies a CC BY 4.0 attribution notice.
The page gives ISRC USUAN1400003 and a duration of 4:08. After hearing the
full audition, the player accepted it as the South Asian port replacement
candidate: "Yes, consider Dhaka instead." Repeat checks remain open.

The exact MP3 was obtained through that page's Download control. Its tags
identify Dhaka and Kevin MacLeod. It decodes without reported errors to
10,947,456 stereo samples at 44,100 Hz (248.241633 s). It measures
-19.07 LUFS and -4.18 dBTP. The full audition applies one constant -3.93 dB
gain and measures -8.17 dBFS sample peak. The full audition has no loop edit.

The same objective voice screen produces no flag at its 0.30 threshold;
its highest voice-class score is Singing at 0.2743. This does not establish
vocal absence. Explicit vocal sign-off and repeat suitability remain open.
Source and full-audition metadata are preserved separately in
`tmp/music-audit-2026-10-10/dhaka-analysis.json`; the initial batch statistics
remain unchanged. Source file: `tmp/music-audit-2026-10-10/dhaka-mp3.mp3`.

Source SHA-256:
`2196a22f4a96de9c03e3d6c1589ac5b3234641caa7f1afd2299b0e418ab53ab0`.

Complete audition SHA-256:
`1998687b7728b9b9dcc37ca58a2d5793a83f69f3dd0ae3a61e2c32ff98fe2dda`.

#### Dhaka initial drone-passage repeat not approved

The candidate plays the first 352,800 samples (eight seconds) once, then
repeats source samples 352,800 through 10,456,609 (end exclusive), a
10,103,809-sample section (229.111315 s at 44,100 Hz). The initial prefix
enters the loop contiguously. This retains most of the full arrangement
while omitting the final decay from each repeat.

The final 176,400 samples (four seconds) blend source seconds
233.111315–237.111315 into source seconds 4–8. These quieter passages have
normalized mono waveform correlation of approximately 0.952 and stereo RMS
levels that differ by less than 0.01 dB. This supports a matched passage
choice; no exact raw loop has been established.

The blend uses complementary raised-cosine gains whose sum is one to avoid
boosting the correlated overlap. Routine repeats have no selection settling
delay. This edit preserves the selected sine/cosine curves for port/ship
selection transitions.

The 16-second preview blends from clip time four to eight seconds, then
continues at source second eight. Constant audition gain is -3.93 dB and the
measured sample peak is -8.81 dBFS. The player found the beginning and blend too
drone-heavy, while liking the later parts of the song. This repeat is not
approved. Exact points, prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/dhaka-loop.json`.

Candidate preview SHA-256:
`ad9771473743e0a678ff571030de0c4f6addfffb2481694bf085dafbbba46a66`.

#### Dhaka first melodic repeat not approved

The revision omits the original first 12 seconds and the quieter ending.
Its initial passage plays source samples 529,200 through 1,234,800 (seconds
12–28) once, a 705,600-sample passage (16 s). A 20 ms raised-cosine entry
fade affects its first 882 samples to avoid a hard cut at startup. The
initial passage enters the loop contiguously at source second 28.

The repeated section runs from source sample 1,234,800 through 9,878,400
(end exclusive), a length of 8,643,600 samples (196 s at 44,100 Hz). Its
final 176,400 samples (four seconds) blend source seconds 220–224 into
source seconds 24–28 using sine/cosine gains. This places active musical
passages on both sides of the join while retaining a 3:16 repeat. No exact
raw loop has been established. Routine repeats have no settling delay.

The 16-second preview starts at source second 216, blends from clip seconds
four to eight, then continues at source second 28. Constant audition gain
remains -3.93 dB; the measured sample peak is -10.36 dBFS. The player reported
that the transition still needs work; this repeat is not approved. The trimmed
initial entry remains unreviewed. Exact points, prepared intro/loop files and
hashes are preserved in
`tmp/music-audit-2026-10-10/dhaka-loop-revision.json`.

Revised candidate preview SHA-256:
`9e981faec056409f85cd4fafad7c93c179d6a070fb2d19dfbf7fb600d02a1d26`.

#### Dhaka phrase-based repeat revision

The next revision chooses passages using time-varying pitch spectra, after
subtracting the opening drone's reference spectrum. Four-second spectral
windows at source seconds 57 and 206.75 have cosine similarity of 0.809,
compared with 0.300 for the rejected melodic pair. Their stereo RMS levels
differ by approximately 0.37 dB. These are heuristic passage-selection
measurements, not waveform identity or proof of a clean musical seam.
Search details are preserved in
`tmp/music-audit-2026-10-10/dhaka-phrase-search.json`.

Initial playback still starts at source second 12. The initial passage runs
through source sample 2,690,100 (second 61), a 2,160,900-sample passage
(49 s), with the same 882-sample (20 ms) entry fade. It enters the repeated
section contiguously. The loop runs from source samples 2,690,100 through
9,294,075 (end exclusive), a 6,603,975-sample section (149.75 s at 44,100 Hz).

The last 176,400 samples (four seconds) blend source seconds 206.75–210.75
into source seconds 57–61 using sine/cosine gains, with no settling delay.
The 16-second preview starts at source second 202.75, blends from clip time
four to eight seconds, then continues at source second 61. Constant audition
gain remains -3.93 dB; the measured sample peak is -9.39 dBFS.

The player found this revision smooth and approved it for use. It is the
selected Dhaka repeat; both earlier candidates remain unapproved. Initial-entry
listening, explicit vocal sign-off and repeated-play listening remain open.
Exact points, prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/dhaka-loop-phrase-revision.json`.

Approved preview SHA-256:
`3f38c7fb6ae60444e0f70bbc21552c6c6148623af0b19a0435d940d6f3bd4994`.

#### Epic Indian Orchestral Fusion approved repeat

For the South Asian voyage candidate, initial playback retains source samples
0 through 2,940,000 (end exclusive), the first 61.25 seconds at 48,000 Hz.
The repeated section runs from sample 2,940,000 through 9,132,000, a
6,192,000-sample section (129 s). This retains the central arrangement and
returns before the softer closing section.

The last 192,000 samples (four seconds) blend source seconds 186.25–190.25
into source seconds 57.25–61.25 using sine/cosine gains, with no settling
delay. The initial prefix enters the loop contiguously. Four-second
time-varying pitch-spectrum windows have cosine similarity of 0.766; their
stereo RMS levels differ by approximately 1.51 dB. These are heuristic
passage-selection measurements, not proof of a clean musical seam. Search
details are preserved in
`tmp/music-audit-2026-10-10/epic-indian-fusion-phrase-search.json`.

The 16-second preview starts at source second 182.25, blends from clip time
four to eight seconds, then continues at source second 61.25. Constant
audition gain is -11.23 dB; the measured sample peak is -12.99 dBFS.
The player approved this repeat for use. Explicit vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in
`tmp/music-audit-2026-10-10/epic-indian-fusion-loop.json`.

Approved preview SHA-256:
`af75b53dac60010dde5ef3712a7514345de55260957c36357ad094ef1c528690`.

#### Middle East Ballad approved repeat

For the Gulf port candidate, initial playback retains source samples 0
through 1,675,800 (end exclusive), the first 38 seconds at 44,100 Hz. The
repeated section runs from sample 1,675,800 through 6,756,120, a
5,080,320-sample section (115.2 s). This returns before the closing fade,
retaining most of the arrangement.

The last 176,400 samples (four seconds) blend source seconds 149.2–153.2
into source seconds 34–38. The mono waveform correlation is 0.725 and
stereo RMS levels differ by approximately 0.43 dB. Complementary
raised-cosine gains sum to one, avoiding a boost between correlated passages.
There is no settling delay for this repeat; the selection transition's
sine/cosine curves remain unchanged. The initial prefix enters the loop
contiguously. Matching measurements are preserved in
`tmp/music-audit-2026-10-10/middle-east-ballad-repeat-search.json`.

The 16-second preview starts at source second 145.2, blends from clip time
four to eight seconds, then continues at source second 38. Constant audition
gain is -12.55 dB; the measured sample peak is -12.49 dBFS. The prepared
unattenuated float loop preserves the source's +0.22 dBFS sample peak:
apply attenuation before integer conversion or playback. The preview is
attenuated before conversion and has no clipped samples.

The player approved this repeat for use. Explicit vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in
`tmp/music-audit-2026-10-10/middle-east-ballad-loop.json`.

Approved preview SHA-256:
`9c9094e431f2c3e7467afc6d4206916265b316f4aea19e578937ea94fccdfe3e`.

#### Conquer The Great Sands tagged repeat candidate

The exact Ogg recording contains `LOOPSTART=14655` and
`LOOPLENGTH=6451870`. These values were re-read from the source with FFprobe
and agree with the original analysis. At 44,100 Hz they define source samples
14,655 through 6,466,525 (end exclusive): a 6,451,870-sample repeat
(146.300907 s), from source seconds 0.332313 through 146.633220.

The first 14,655 samples (0.332313 s) play once, then enter the tagged loop
contiguously. This candidate repeats the tagged section without boundary
fades, a crossfade or a settling delay. It preserves the ending's decay and
returns to the opening passage. The tagged tail's last approximately 0.058
seconds have no sample reaching -50 dBFS; this measurement alone does not
decide whether its musical pause feels natural. The raw seam's maximum
channel jump is approximately 0.000420 before attenuation.

The eight-second preview contains the last four seconds of the tagged loop,
followed by its first four seconds, with the raw join at clip time four
seconds. Constant audition gain is -9.80 dB; the measured sample peak is
-16.64 dBFS, with no clipped samples. The player found the transition needs
work; this raw tagged repeat is not approved. The player's earlier
instrumental judgment concerns the flagged excerpt; full-recording vocal
sign-off and repeated-play listening remain open.

Exact points, prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/conquer-sands-loop.json`.

Candidate preview SHA-256:
`bd6c18d67e3e1b9216717762cfc5f53c47b8e377977020965399f346a4aa9cf9`.

#### Conquer The Great Sands active-passage revision

The revised candidate retains the first 1,675,800 samples (38 s at
44,100 Hz) once, then enters the repeated section contiguously. The loop
runs from source sample 1,675,800 through 5,909,400 (end exclusive), a
4,233,600-sample section (96 s). It retains the central arrangement,
including its quieter middle section, and returns before the ending's decay.

The last 176,400 samples (four seconds) blend source seconds 130–134 into
source seconds 34–38. Native-rate mono waveform correlation is 0.743;
stereo RMS levels differ by approximately 0.68 dB. Complementary
raised-cosine gains sum to one to avoid a boost between correlated passages.
The blend returns to the fuller main arrangement, rather than the quieter
opening. There is no settling delay for this repeat. Matching measurements
are preserved in
`tmp/music-audit-2026-10-10/conquer-sands-repeat-search.json`.

The 16-second preview starts at source second 126, blends from clip time
four to eight seconds, then continues at source second 38. Constant audition
gain remains -9.80 dB; the measured sample peak is -10.59 dBFS, with no
clipped samples. The player approved this revision for use; it is the
selected repeat, and the raw tagged candidate remains unapproved.
Full-recording vocal sign-off and repeated-play listening remain open.
Exact points, prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/conquer-sands-loop-revision.json`.

Approved revision preview SHA-256:
`60346dde3ceb08203bf2066be89e58fe3b0b8106212b4369e6a48f9f10878fd2`.

#### Arabic Music approved repeat

For the other North African port candidate, initial playback retains the
first 780,000 samples (16.25 s at 48,000 Hz) once, then enters the repeated
section contiguously. The loop runs from source sample 780,000 through
5,099,880 (end exclusive), a 4,319,880-sample section (89.9975 s). It returns
to an active earlier passage before the file's ending.

The last 192,000 samples (four seconds) blend source seconds
102.2475–106.2475 into source seconds 12.25–16.25 using sine/cosine gains,
with no settling delay. The coarse four-second pitch-spectrum similarity
is 0.610; native-rate waveform refinement shifts the later passage by
-2.5 ms, producing mono waveform correlation of 0.345. Stereo RMS levels
differ by approximately 2.91 dB. These are heuristic passage-selection
measurements, not proof of a clean musical seam. Search details are
preserved in
`tmp/music-audit-2026-10-10/kiravale-arabic-phrase-search.json`.

The 16-second preview starts at source second 98.2475, blends from clip time
four to eight seconds, then continues at source second 16.25. Constant
audition gain is -12.82 dB; the measured sample peak is -10.42 dBFS.
The unattenuated prepared float loop reaches +2.40 dBFS during the overlap:
apply attenuation before integer conversion or playback. The preview is
attenuated before conversion and has no clipped samples.

The player approved this repeat for use. Full-recording vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in
`tmp/music-audit-2026-10-10/kiravale-arabic-loop.json`.

Approved preview SHA-256:
`ee6de920f135fa048ab8d16bae6fe91adeca71b8d2bf236563c1935ed4c390da`.

#### Dellasera approved repeat

For Mediterranean ports, initial playback retains the first 1,764,000
samples (40 s at 44,100 Hz) once, then enters the repeated section
contiguously. The loop runs from source sample 1,764,000 through 9,631,752
(end exclusive), a 7,867,752-sample section (178.407075 s). It retains most
of the arrangement, including the central changes in intensity, and returns
before the closing passage.

The last 176,400 samples (four seconds) blend source seconds
214.407075–218.407075 into source seconds 36–40. Native-rate mono waveform
correlation is 0.475; stereo RMS levels differ by approximately 1.52 dB.
The repeat interval matches 336 beats at the file's tagged 113 BPM to
within one sample. These measurements support passage and rhythm alignment;
they do not prove a clean musical seam. Complementary raised-cosine gains
sum to one to avoid a boost between correlated passages. There is no
settling delay for this repeat. Matching measurements are preserved in
`tmp/music-audit-2026-10-10/dellasera-repeat-search.json`.

The 16-second preview starts at source second 210.407075, blends from clip
time four to eight seconds, then continues at source second 40. Constant
audition gain is -9.18 dB; the measured sample peak is -9.55 dBFS, with no
clipped samples. The player approved this repeat for use. Full-recording
vocal sign-off and repeated-play listening remain open. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/dellasera-loop.json`.

Approved preview SHA-256:
`623666c38f57dd784ae104440dd27e2f954e0525b4294920ef2f8db8b61970d5`.

#### Atlas • Greece approved repeat

For the first Mediterranean voyage candidate, initial playback retains the
first 1,164,000 samples (24.25 s at 48,000 Hz) once, then enters the
repeated section contiguously. The loop runs from source sample 1,164,000
through 5,040,372 (end exclusive), a 3,876,372-sample section (80.75775 s).
It returns to the fuller earlier arrangement before the file's ending.

The last 192,000 samples (four seconds) blend source seconds
101.00775–105.00775 into source seconds 20.25–24.25 using sine/cosine gains,
with no settling delay. The coarse four-second pitch-spectrum similarity
is 0.659; native-rate waveform refinement shifts the later passage by
+7.75 ms, producing mono waveform correlation of 0.125. Stereo RMS levels
differ by approximately 1.39 dB. These are heuristic passage-selection
measurements, not proof of a clean musical seam or identical waveforms.
Search details are preserved in
`tmp/music-audit-2026-10-10/atlas-greece-phrase-search.json`.

The 16-second preview starts at source second 97.00775, blends from clip
time four to eight seconds, then continues at source second 24.25. Constant
audition gain is -8.44 dB; the measured sample peak is -10.07 dBFS, with no
clipped samples. The player approved this repeat for use. Full-recording
vocal sign-off and repeated-play listening remain open. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/atlas-greece-loop.json`.

Approved preview SHA-256:
`b109cf7c2e47c78ff18ef4d733baa201e55234f662597d5d4ae2a802de25c39d`.

#### Cinematic Latin Music approved repeat

For the other Mediterranean voyage candidate, initial playback retains the
first 981,225 samples (22.25 s at 44,100 Hz) once, then enters the repeated
section contiguously. The loop runs from source sample 981,225 through
4,629,618 (end exclusive), a 3,648,393-sample section (82.73 s). It returns
to an active earlier passage before the closing section and quiet tail.

The last 176,400 samples (four seconds) blend source seconds 100.98–104.98
into source seconds 18.25–22.25 using sine/cosine gains, with no settling
delay. The coarse four-second pitch-spectrum similarity is 0.709. A bounded
native-rate waveform comparison selects the later passage 20 ms earlier,
at the edge of its search window; mono waveform correlation there is 0.154.
Stereo RMS levels differ by approximately 1.50 dB. These are heuristic
passage-selection measurements, not proof of waveform identity or a clean
musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/cinematic-latin-phrase-search.json`.

The 16-second preview starts at source second 96.98, blends from clip time
four to eight seconds, then continues at source second 22.25. Constant
audition gain is -14.64 dB; the measured sample peak is -12.74 dBFS. The
unattenuated prepared float loop reaches +1.90 dBFS during the overlap:
apply attenuation before integer conversion or playback. The preview is
attenuated before conversion and has no clipped samples.

The player approved this repeat for use. Full-recording vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in
`tmp/music-audit-2026-10-10/cinematic-latin-loop.json`.

Approved preview SHA-256:
`a60f3ceaec1d39db917a1fd8725d46aeab6a5792356bc1a5190d5d94afe46c31`.

#### Lord of the Land approved repeat

For the first Northern Frangistan port candidate, initial playback retains
the first 1,102,500 samples (25 s at 44,100 Hz) once, then enters the
repeated section contiguously. The loop runs from source sample 1,102,500
through 7,882,875 (end exclusive), a 6,780,375-sample section (153.75 s).
It retains most of the recording and returns before the closing decay and
quiet tail.

The last 176,400 samples (four seconds) blend source seconds 174.75–178.75
into source seconds 21–25 using sine/cosine gains, with no settling delay.
The four-second pitch-spectrum similarity is 0.760; native-rate mono
waveform correlation is 0.115. Stereo RMS levels differ by approximately
2.00 dB. The selected spectral window points are retained without waveform
timing refinement. These are heuristic passage-selection measurements,
not proof of waveform identity or a clean musical seam. Search details are
preserved in `tmp/music-audit-2026-10-10/lord-phrase-search.json`.

The 16-second preview starts at source second 170.75, blends from clip time
four to eight seconds, then continues at source second 25. Constant audition
gain is +0.20 dB, capped by the original recording's measured -2.20 dBTP
peak rather than using the +1.07 dB needed to reach -23 LUFS. The preview's
measured sample peak is -2.22 dBFS, with no clipped samples; its mixed true
peak has not been measured separately.

The player approved this repeat for use. Full-recording vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in `tmp/music-audit-2026-10-10/lord-loop.json`.

Approved preview SHA-256:
`27396d3c143ebd1d679a66f11e3790d57e60b305417268aec954ea4f6ef89372`.

#### Townsong approved repeat

For the other Northern Frangistan port candidate, initial playback retains
the first 1,433,250 samples (32.5 s at 44,100 Hz) once, then enters the
repeated section contiguously. The loop runs from source sample 1,433,250
through 7,021,601 (end exclusive), a 5,588,351-sample section (126.719977 s).
It retains the quieter middle section and returns to the earlier main
melody before the closing passage.

The last 176,400 samples (four seconds) blend source seconds
155.219977–159.219977 into source seconds 28.5–32.5 using sine/cosine gains,
with no settling delay. The coarse four-second pitch-spectrum similarity
is 0.841. Native-rate waveform comparison within 80 ms of the spectral
candidate selects the later passage approximately 30 ms earlier, with its
maximum inside the search window. Mono waveform correlation is 0.324;
stereo RMS levels differ by approximately 0.72 dB. These are heuristic
passage-selection measurements, not proof of waveform identity or a clean
musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/townsong-phrase-search.json`.

The 16-second preview starts at source second 151.219977, blends from clip
time four to eight seconds, then continues at source second 32.5. Constant
audition gain is -13.06 dB; the measured sample peak is -10.32 dBFS. The
unattenuated prepared float loop reaches +2.74 dBFS during the overlap:
apply attenuation before integer conversion or playback. The preview is
attenuated before conversion and has no clipped samples.

The player approved this repeat for use. Full-recording vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop files
and hashes are preserved in `tmp/music-audit-2026-10-10/townsong-loop.json`.

Approved preview SHA-256:
`f51d14310f32dc2a00a8c5eaa64a9660e6d05dc43eef41c0f83a01b79262228b`.

#### Home Was You approved repeat

For the retained Northern Frangistan port alternative, initial playback
retains the first 1,830,150 samples (41.5 s at 44,100 Hz) once, then enters
the repeated section contiguously. The loop runs from source sample
1,830,150 through 9,150,750 (end exclusive), a 7,320,600-sample section
(166 s). It retains the central build and changes in intensity, returning
before the extended quiet outro.

The last 176,400 samples (four seconds) blend source seconds 203.5–207.5
into source seconds 37.5–41.5 using sine/cosine gains, with no settling
delay. The four-second pitch-spectrum similarity is 0.624; native-rate mono
waveform correlation is -0.018. Stereo RMS levels differ by approximately
1.61 dB. The selected incoming window includes the louder entry at its end
within the overlap, rather than immediately after it. Spectral window points
are retained without waveform timing refinement. These are heuristic
passage-selection measurements, not proof of waveform identity or a clean
musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/home-phrase-search.json`.

The 16-second preview starts at source second 199.5, blends from clip time
four to eight seconds, then continues at source second 41.5. Constant
audition gain is -8.59 dB; the measured sample peak is -9.56 dBFS, with no
clipped samples. The player approved this repeat for use. Full-recording
vocal sign-off and repeated-play listening remain open. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/home-loop.json`.

Approved preview SHA-256:
`f1d5895a118fbd4e02526969e85ae7424c3f3a97fa404ca46cfd6d40c0ac4ca7`.

#### Pathfinder approved repeat

For Northern Frangistan voyages, initial playback retains the first
2,348,325 samples (53.25 s at 44,100 Hz) once, then enters the repeated
section contiguously. The loop runs from source sample 2,348,325 through
8,775,900 (end exclusive), a 6,427,575-sample section (145.75 s). It retains
the quieter middle and later build, returning before the closing decay.

The last 176,400 samples (four seconds) blend source seconds 195–199 into
source seconds 49.25–53.25 using sine/cosine gains, with no settling delay.
The four-second pitch-spectrum similarity is 0.665; native-rate mono
waveform correlation is -0.004. Stereo RMS levels differ by approximately
2.10 dB. Spectral window points are retained without waveform timing
refinement. These are heuristic passage-selection measurements, not proof
of waveform identity or a clean musical seam. Search details are preserved
in `tmp/music-audit-2026-10-10/pathfinder-phrase-search.json`.

The 16-second preview starts at source second 191, blends from clip time
four to eight seconds, then continues at source second 53.25. Constant
audition gain is -9.00 dB; the measured sample peak is -10.55 dBFS, with no
clipped samples. The player approved this repeat for use. Full-recording
vocal sign-off and repeated-play listening remain open. Exact points,
prepared intro/loop
files and hashes are preserved in
`tmp/music-audit-2026-10-10/pathfinder-loop.json`.

Approved preview SHA-256:
`f27edd85b188a8b41368bac7953f5381cdfb3750db05cf0ebbd6fb82ee3ddb18`.

#### Swing Train approved repeat

For North American ports, initial playback retains the first 1,334,025
samples (30.25 s at 44,100 Hz) once, then enters the repeated section
contiguously. The loop runs from source sample 1,334,025 through 4,659,649
(end exclusive), a 3,325,624-sample section (75.411 s). It retains the
middle section and louder return, looping before the closing passage.

The last 176,400 samples (four seconds) blend source seconds
101.660975–105.660975 into source seconds 26.25–30.25 using sine/cosine
gains, with no settling delay. The initial four-second pitch-spectrum
similarity is 0.788. A bounded timing search within 100 ms moved the
outgoing window approximately 89 ms earlier; its best native-rate mono
waveform correlation is 0.113, away from the search limits. Stereo RMS
levels differ by approximately 1.63 dB. These are heuristic
passage-selection measurements, not proof of waveform identity, beat
alignment or a clean musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/swing-train-phrase-search.json`.

The 16-second preview starts at source second 97.660975, blends from clip
time four to eight seconds, then continues at source second 30.25.
Constant audition gain is -6.13 dB; the measured sample peak is -7.72 dBFS,
with no clipped samples. The player approved this repeat for use.
Full-recording vocal sign-off and repeated-play listening remain open.
Exact points, prepared
intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/swing-train-loop.json`.

Approved preview SHA-256:
`e9b97d306782957594059e3dc669d342215066816b95fd7a781b2acba2f1afe6`.

#### Dark Red Wine repeat: track reconsideration requested

For Caribbean ports, initial playback retains the first 1,157,625 samples
(26.25 s at 44,100 Hz) once, then enters the repeated section contiguously.
The loop runs from source sample 1,157,625 through 8,588,938 (end
exclusive), a 7,431,313-sample section (168.510 s). It retains most of the
recording, returning to an earlier passage before the closing section.

The last 176,400 samples (four seconds) blend source seconds
190.760499–194.760499 into source seconds 22.25–26.25 using complementary
raised-cosine gains, with no settling delay. Their sum remains one,
avoiding the gain boost that equal-power curves can add to closely matched
passages. The initial four-second pitch-spectrum similarity is 0.904. A
bounded timing search within 100 ms moved the outgoing window
approximately 10.5 ms later; its best native-rate mono waveform
correlation is 0.605, away from the search limits. Stereo RMS levels
differ by approximately 0.30 dB. The selected pair retains a longer
section than the highest-scoring spectral pair, with almost the same
spectral score. These are heuristic passage-selection measurements, not
proof of waveform identity, beat alignment or a clean musical seam.
Search details are preserved in
`tmp/music-audit-2026-10-10/dark-red-wine-phrase-search.json`.

The 16-second preview starts at source second 186.760499, blends from clip
time four to eight seconds, then continues at source second 26.25.
Constant audition gain is -7.31 dB; the measured sample peak is -9.91 dBFS,
with no clipped samples. The player requested reconsidering the track,
so the loop is not approved and the Caribbean port selection is reopened.
This is a track-fit decision, not a report of vocals or a specific seam
defect. Exact points, prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/dark-red-wine-loop.json`.

Unapproved preview SHA-256:
`ad9514a832d6c841074da1338046c1fb934ca968fcc93d4ab3a028ff20737164`.

#### Beachfront Celebration supplemental audition

[Beachfront Celebration](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1200022)
by Kevin MacLeod is the accepted Caribbean port replacement after the
player requested reconsidering Dark Red Wine. The official catalog
lists bass, percussion, brass, steel drums and piano at 120 BPM, with
bouncy, bright, grooving and uplifting tags. This suggests a lively port
candidate; regional and background fit require the player's audition.
The catalog's island styling is not a claim of specifically Panamanian
musical identity.

The official track page's attribution template specifies CC BY 4.0. The
free MP3 was downloaded directly from Incompetech; retain the composer,
source, license link and edit notice if it is selected. The source page
and refreshed catalog are preserved as `beachfront-source.html` and
`macleod-pieces-caribbean-refresh.json` in the temporary audit directory.
Catalog ISRC is `USUAN1200022`. Its embedded title has a spelling error,
`Beachfromt Celebration`; the official filename and catalog title both
identify Beachfront Celebration.

The source decodes to 8,259,840 stereo samples at 44,100 Hz (187.297959 s).
Measured source loudness is -9.20 LUFS, with +0.24 dBTP. The complete
audition uses constant -13.80 dB gain, preserving the arrangement and
dynamics without a loop edit. Its measured sample peak is -13.73 dBFS,
with no clipped samples. Automated screening produced no voice flags at
0.30; the highest voice-class score was Singing at 0.0171. This does not
prove the absence of voices. The player accepted this replacement after
the full-recording audition. Full vocal sign-off, repeated-play
suitability remain open; the repeat below is approved.

Source SHA-256:
`73ffcea8277780253b4e42dcbc3c5b3c50ba8ad343023372726a8678f43cc68e`.

Full audition SHA-256:
`33c3a06fd251c6a0a8ddc9f20f5057194347fef87794c21b98dc62c7d6ae0a3a`.

Exact source and preview paths, download URL, grant, measurements and hashes
are preserved in
`tmp/music-audit-2026-10-10/beachfront-celebration-analysis.json`.
This supplemental recording is outside the initial 32-recording audit;
the original batch statistics have not been rewritten.

#### Beachfront Celebration approved repeat

For the accepted Caribbean port replacement, initial playback retains the
first 1,223,775 samples (27.75 s at 44,100 Hz) once, then enters the
repeated section contiguously. The loop runs from source sample 1,223,775
through 7,574,175 (end exclusive), a 6,350,400-sample section (144 s). It
retains most of the recording, including the quieter passages, while
returning before the ending.

The last 176,400 samples (four seconds) blend source seconds 167.75–171.75
into source seconds 23.75–27.75 using complementary raised-cosine gains,
with no settling delay. Their sum remains one to avoid boosting closely
matched passages. The initial four-second pitch-spectrum similarity is
0.861. A bounded timing search within 100 ms retained the original points;
its best native-rate mono waveform correlation is 0.765, away from the
search limits. Stereo RMS levels differ by approximately 0.11 dB. The
selected pair starts the repeated section before the quieter passage
around source second 32, rather than at its entry. These are heuristic
passage-selection measurements, not proof of waveform identity or a clean
musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/beachfront-celebration-phrase-search.json`.

The 16-second preview starts at source second 163.75, blends from clip
time four to eight seconds, then continues at source second 27.75.
Constant audition gain is -13.80 dB; the measured sample peak is
-13.79 dBFS, with no clipped samples. The prepared unattenuated float loop
has a +0.056 dBFS sample peak inherited from the decoded source; apply the
chosen gain before integer conversion. The player approved this repeat
for use. Full-recording vocal sign-off and repeated-play listening remain
open. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/beachfront-celebration-loop.json`.

Approved preview SHA-256:
`e080ade9be390667ab770dbe4e46a4ce9e47bc2a2f3bf8ba3dbb80278cb7a4fb`.

#### Setting Sail approved repeat

For Caribbean voyages, initial playback retains the first 1,918,350
samples (43.5 s at 44,100 Hz) once, then enters the repeated section
contiguously. The loop runs from source sample 1,918,350 through 5,093,550
(end exclusive), a 3,175,200-sample section (72 s). It repeats the main
arrangement after the opening build, returning before the closing decay.

The last 176,400 samples (four seconds) blend source seconds 111.5–115.5
into source seconds 39.5–43.5 using sine/cosine gains, with no settling
delay. The four-second pitch-spectrum similarity is 0.664; native-rate
mono waveform correlation at the selected points is -0.024. Stereo RMS
levels differ by approximately 0.86 dB. A bounded waveform timing search
within 100 ms found only a weak maximum of 0.074, so the original spectral
window points are retained. The 72-second interval equals 144 beats at the
source's tagged 120 BPM; this does not establish beat phase alignment.
These are heuristic passage-selection measurements, not proof of
waveform identity or a clean musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/setting-sail-phrase-search.json`.

The 16-second preview starts at source second 107.5, blends from clip time
four to eight seconds, then continues at source second 43.5. Constant
audition gain is -12.13 dB; the measured sample peak is -11.27 dBFS, with no
clipped samples. The prepared unattenuated float loop has a +0.86 dBFS
sample peak; apply the chosen gain before integer conversion. The player
approved this repeat for use. Full-recording vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop
files and hashes are preserved in
`tmp/music-audit-2026-10-10/setting-sail-loop.json`.

Approved preview SHA-256:
`493760882848b9bc4e16eef3af177dbfdbfee6ddfca583fa583c9344da304dda`.

#### Epic Cinematic Salsa approved repeat

For the retained Caribbean voyage alternative, initial playback retains
the first 1,058,400 samples (24 s at 44,100 Hz) once, then enters the
repeated section contiguously. The loop runs from source sample 1,058,400
through 8,886,150 (end exclusive), a 7,827,750-sample section (177.5 s). It
retains the middle sections and much of the later arrangement, returning
before the quiet ending.

The last 176,400 samples (four seconds) blend source seconds 197.5–201.5
into source seconds 20–24 using sine/cosine gains, with no settling delay.
The four-second pitch-spectrum similarity is 0.715; native-rate mono
waveform correlation at the selected points is -0.020. Stereo RMS levels
differ by approximately 2.01 dB. A bounded waveform timing search within
100 ms found only a weak maximum of 0.043, so the original spectral window
points are retained. This pair retains 19.5 additional seconds compared
with the highest-scoring spectral pair, with nearly the same spectral
score. These are heuristic passage-selection measurements, not proof of
waveform identity, beat alignment or a clean musical seam. Search details
are preserved in
`tmp/music-audit-2026-10-10/epic-salsa-phrase-search.json`.

The 16-second preview starts at source second 193.5, blends from clip time
four to eight seconds, then continues at source second 24. Constant
audition gain is -11.38 dB; the measured sample peak is -10.85 dBFS, with no
clipped samples. The prepared unattenuated float loop has a +0.53 dBFS
sample peak; apply the chosen gain before integer conversion. The player
approved this repeat for use. Full-recording vocal sign-off and
repeated-play listening remain open. Exact points, prepared intro/loop
files and hashes are preserved in
`tmp/music-audit-2026-10-10/epic-salsa-loop.json`.

Approved preview SHA-256:
`ae81dea0e24853860f0110d6529e06be1ee1132c1b19b9744f629439e3712c9e`.

#### Tropical Contact repeat: track reconsideration requested

For Brazilian ports, initial playback retains the first 1,157,625 samples
(26.25 s at 44,100 Hz) once, then enters the repeated section contiguously.
The loop runs from source sample 1,157,625 through 7,961,963 (end
exclusive), a 6,804,338-sample section (154.293 s). It retains the quieter
middle section, returning to an earlier passage before the closing fade.

The last 176,400 samples (four seconds) blend source seconds
176.543379–180.543379 into source seconds 22.25–26.25 using sine/cosine
gains, with no settling delay. The initial four-second pitch-spectrum
similarity is 0.855. A bounded timing search within 100 ms moved the
outgoing window approximately 43.4 ms later; its best native-rate mono
waveform correlation is 0.194, away from the search limits. Stereo RMS
levels differ by approximately 0.006 dB. These are heuristic
passage-selection measurements, not proof of waveform identity, beat
alignment or a clean musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/tropical-contact-phrase-search.json`.

The 16-second preview starts at source second 172.543379, blends from clip
time four to eight seconds, then continues at source second 26.25.
Constant audition gain is -11.17 dB; the measured sample peak is
-9.75 dBFS, with no clipped samples. The prepared unattenuated float loop
has a +1.42 dBFS sample peak; apply the chosen gain before integer
conversion. The player requested reconsidering the track, so the loop is
not approved and the Brazilian port selection is reopened. No specific
seam defect or vocal failure was reported. Exact points, prepared
intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/tropical-contact-loop.json`.

Unapproved preview SHA-256:
`e704112885229d2c77225914b72019c435c41c07e602a288391447321324f67c`.

#### Sideways Samba supplemental audition

[Sideways Samba](https://audionautix.com/free-music/jazz) by Jason Shaw is
the accepted Brazilian port replacement after the player requested
reconsidering Tropical Contact. The official Jazz catalog lists medium
tempo with relaxing, calming and bright tags. Its samba framing suggests
a Brazilian port candidate; background fit and sufficient variation
require the player's audition. A full orchestral arrangement is not
documented by the listing.

The catalog offers the exact MP3 at
`https://audionautix.com/Music/SidewaysSamba.mp3`. Its footer grants free
commercial use under CC BY 4.0 with appropriate credit, as part of another
created work. Retain the composer, source, license link and edit notice if
selected. The source page is preserved as `sideways-samba-source.html` in
the temporary audit directory.

The source decodes to 8,421,120 stereo samples at 44,100 Hz (190.955102 s).
Measured source loudness is -12.90 LUFS, with +0.40 dBTP. The complete
audition uses constant -10.10 dB gain, preserving the arrangement and
dynamics without a loop edit. Its measured sample peak is -9.85 dBFS,
with no clipped samples. Automated screening produced no voice flags at
0.30; the highest voice-class score was Speech at 0.0335. This does not
prove the absence of voices. The player accepted this replacement after
the full-recording audition. Full vocal sign-off, repeated-play
suitability remain open; the repeat below is approved.

Source SHA-256:
`2ee432954197d30320b95a915d3c029e446130f5eb0490347c87bb535dc7e159`.

Full audition SHA-256:
`6302332f64e70a7e06a6974a53d210a86ddbd6074b98a86c736e95740e24ead9`.

Exact source and preview paths, download URL, grant, measurements and hashes
are preserved in
`tmp/music-audit-2026-10-10/sideways-samba-analysis.json`.
This supplemental recording is outside the initial 32-recording audit;
the original batch statistics have not been rewritten.

#### Sideways Samba approved repeat

For the accepted Brazilian port replacement, initial playback retains
the first 1,708,875 samples (38.75 s at 44,100 Hz) once, then enters the
repeated section contiguously. The loop runs from source sample 1,708,875
through 8,191,581 (end exclusive), a 6,482,706-sample section (147.000 s).
It retains most of the recording, returning to an earlier passage before
the ending fades.

The last 176,400 samples (four seconds) blend source seconds
181.750136–185.750136 into source seconds 34.75–38.75 using sine/cosine
gains, with no settling delay. The initial four-second pitch-spectrum
similarity is 0.832. A bounded timing search within 100 ms moved the
outgoing window six samples (0.136 ms) later; its best native-rate mono
waveform correlation is 0.338, away from the search limits. Stereo RMS
levels differ by approximately 0.27 dB. These are heuristic
passage-selection measurements, not proof of waveform identity, beat
alignment or a clean musical seam. Search details are preserved in
`tmp/music-audit-2026-10-10/sideways-samba-phrase-search.json`.

The 16-second preview starts at source second 177.750136, blends from clip
time four to eight seconds, then continues at source second 38.75.
Constant audition gain is -10.10 dB; the measured sample peak is
-10.32 dBFS, with no clipped samples. The prepared unattenuated float loop
has a +0.25 dBFS sample peak; apply the chosen gain before integer
conversion. The player approved this repeat for use. Full-recording
vocal sign-off and repeated-play listening remain open. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/sideways-samba-loop.json`.

Approved preview SHA-256:
`cb15ee9b73e3eea36577b0db2bf4da6b7274e4a8c21f0236c93f6165ca72c388`.

#### Up In The Air approved repeat

For Brazilian voyages, initial playback retains the first 628,425 samples
(14.25 s at 44,100 Hz) once, then enters the repeated section contiguously.
The loop runs from source sample 628,425 through 8,290,800 (end exclusive),
a 7,662,375-sample section (173.75 s). It retains nearly the full
arrangement, returning to an earlier active passage before the final
ending.

The last 176,400 samples (four seconds) blend source seconds 184–188 into
source seconds 10.25–14.25 using sine/cosine gains, with no settling delay.
The four-second pitch-spectrum similarity is 0.584; native-rate mono
waveform correlation at the selected points is 0.027. Stereo RMS levels
differ by approximately 1.58 dB. A bounded waveform timing search within
100 ms found only a weak maximum of 0.101, so the original spectral window
points are retained. These are heuristic passage-selection measurements,
not proof of waveform identity, beat alignment or a clean musical seam.
Search details are preserved in
`tmp/music-audit-2026-10-10/up-in-air-phrase-search.json`.

The 16-second preview starts at source second 180, blends from clip time
four to eight seconds, then continues at source second 14.25. Constant
audition gain is -11.04 dB; the measured sample peak is -12.06 dBFS, with no
clipped samples. The player approved this repeat for use. Full-recording
vocal sign-off and repeated-play listening remain open. Exact points,
prepared intro/loop files and hashes are preserved in
`tmp/music-audit-2026-10-10/up-in-air-loop.json`.

Approved preview SHA-256:
`773d4d6cc75170b073cdec26c70498ada69748340018e40994a6a4b654993a8a`.

#### Preparation for other recordings

For recordings without supplied loops or a verified repeated section, use an
edited musical loop or a same-track crossfade. Tail values measured below
-50 dBFS identify possible trim regions, not permission to discard audible
reverb automatically. In particular, Beautiful Korea and The World At Your
Door each have about eight seconds below that threshold at the end; Epic
Cinematic Salsa has about twelve. A full-file hard restart would retain those
quiet gaps. Do not use a selection settling delay for a routine track repeat.

## Crossfades

All sixteen updated port-to-voyage pairings are approved using the revised
selection timing: three seconds to settle, a five-second outgoing cosine
fade and a two-second incoming sine fade over its final two seconds. The
current transition listening pass is complete. This pass checks the listed
handoffs; full-recording vocal sign-off, repeated-play suitability,
unreviewed initial entries and actual client playback remain open.

The later playback clarification preserves these stable-selection auditions:
a selected ship's departure automatically invokes the voyage transition, and
ports sharing the same port music continue without a new transition. A changed
selection during the initial three seconds cancels the incoming piece; the
original five-second fade completes, then one second of silence precedes the
latest piece's two-second fade-in. Further changes while silent reset a
three-second silent wait. Each new fade-in displays title, artists and source
link at the screen top. Rapid reselection and these display requirements remain
unauditioned and unimplemented; the sixteen handoff approvals do not verify
them. DESIGN.md is the playback contract.

Lord of the Land is selected for the initial Northern Frangistan port slot;
Townsong and Home Was You remain approved alternatives. Bombay Summer by Shane
Ivers is restored as a South Asian port alternative in the shortlist. Its
official page offers CC BY 4.0, but its exact recording has not been audited.
There is no recorded rejection that establishes a musical or license defect.

Sixteen original port-to-voyage examples cover all twelve palettes and the
initial multiple leads. Each example starts with five seconds of music. The
selection occurs at clip time 5 s, the incoming recording starts at 8 s, the old
recording is silent at 9 s, and the new recording reaches full chosen gain at 12
s. These preserve the earlier three-second settle and four-second fades, now
superseded for selection transitions by the five-second outgoing fade and
two-second incoming fade requested after the Caribbean audition. Approved
same-track repeat edits are unchanged. The initial Caribbean port example uses
Dark Red Wine, now set aside; the revised Beachfront Celebration transition
below is approved. The initial Brazilian port example uses Tropical Contact,
also now set aside; the replacement-specific transition below is approved.

Both linear and sine/cosine gain curves are rendered. On 10 October 2026 the
player selected sine/cosine after comparing the Chinese-coast previews.
Fade-out uses a quarter cosine wave and fade-in a quarter sine wave: for
normalized fade progress `p` from zero to one, the respective gain factors are
`cos(pi * p / 2)` and `sin(pi * p / 2)`. A fade-out starts from the current gain,
including when interrupted, and a fade-in ends at the chosen track gain.

With equally loud uncorrelated sustained signals, the earlier delayed timing has
its deepest overlap valley at 3.5 s after selection: about -15.05 dB for linear
gains and -11.18 dB for the selected sine/cosine gains. Actual music can dip
further when its opening is quiet. A quieter handoff is inherent in this timing;
the three-second delay was not shortened to hide it. The current timing instead
overlaps the final two seconds of a five-second outgoing fade with the complete
two-second incoming fade, ending both together.

For previews only, whole-track gain targets -23 LUFS with a -2 dBTP ceiling.
These are audition levels, not a decision about the game's initial volume.
Gain adjustment does not flatten each track's musical dynamics. The original
transition comparison set's loudest sample peak is -3.91 dBFS; mixed-preview
true peaks were not measured.
Preview construction does not test the future LiveView/Tauri audio controller,
rapid reselections, autoplay restrictions, background pause, decoder buffering
or device playback.

### Current Caribbean port-to-voyage audition

The first updated candidate switched from Beachfront Celebration to Setting
Sail. It uses the approved prepared port loop, starting at loop offset 20 s
(original source time 47.75 s), and the unchanged opening of Setting Sail. The
voyage's quiet opening is preserved; approval of its repeat seam does not
establish that this initial entry works during a selection handoff.

Selection occurs at clip time 5 s. The outgoing quarter-cosine fade starts
immediately and ends at 9 s. After the three-second settling delay, the
incoming quarter-sine fade runs from 8 to 12 s. Constant audition gains are
-13.80 dB and -12.13 dB respectively. This 23-second, 44,100 Hz stereo
preview has a measured sample peak of -13.83 dBFS and no clipped samples.
Source hashes, selected source passages, prepared files and the complete
fade render were independently checked. The player reported a couple of
seconds of apparent silence between the tracks and requested revised timing.
This version is superseded and is not approved.

Preview: `previews/caribbean-current-port-to-voyage.wav` under the local
audit directory. Metadata: `caribbean-current-transition-v1.json`.
Preview SHA-256:
`6e656452eac731cd901813f97dc05f7143af5434ea6d2474d7038b4a730ce857`.

The revised preview starts the outgoing cosine fade at clip time 5 s and ends it
at 10 s. After the unchanged three-second settling delay, the new sine fade runs
from 8 to 10 s, overlapping the final two seconds and finishing at full chosen
gain as the old track reaches silence. Setting Sail starts at source time 8 s to
bypass its very quiet opening; this new entry does not alter the approved
repeat. The outgoing source passage and both constant audition gains are
unchanged. The 23-second stereo preview has a measured sample peak of -13.83
dBFS and no clipped samples. Its source passages and complete fade render were
checked; the player approved this version, including its revised timing and
entry. Full-recording vocal sign-off and repeated-play listening remain open.

Revised preview: `previews/caribbean-current-port-to-voyage-5s-2s.wav`.
Current metadata: `caribbean-current-transition.json`.
Revised preview SHA-256:
`d84cc8fef217f6308c322fdeb8d21c017708f8813a2b25efcfadd1498f0500ef`.

### Current Brazilian port-to-voyage audition

The approved preview switches from Sideways Samba to Up In The Air using the
approved prepared recordings and the accepted selection timing. The port
starts at loop offset 20 s (original source time 58.75 s). The voyage starts
at source time zero, retaining its original opening; after 14.25 s of
playback its prepared intro continues contiguously into the approved loop.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -10.10 dB and -11.04 dB
respectively. The 23-second, 44,100 Hz stereo preview has a measured sample
peak of -11.37 dBFS and no clipped samples. Original hashes, selected source
passages, prepared files and the complete fade render were independently
checked. The player approved this transition. Full-recording vocal sign-off
and repeated-play listening remain open.

Preview: `previews/brazil-current-port-to-voyage-5s-2s.wav` under the local
audit directory. Metadata: `brazil-current-transition.json`.
Preview SHA-256:
`cf58f88b24a9581a85a8a0f17539103c03e61b0aa7e4723a9c95b3c9e30ffc0c`.

### Current Chinese coast port-to-voyage audition

The approved preview switches from Shenyang to Imperial China Cinematic. The
port starts at original source time 20 s. The voyage starts at source time 16 s,
where a fuller passage begins after the sparse opening. The player approved this
entry; the approved repeat edits for both recordings are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -9.78 dB and -12.88 dB
respectively. The 23-second, 44,100 Hz stereo preview has a measured sample
peak of -10.06 dBFS and no clipped samples. Original hashes, selected source
passages and the complete fade render were independently checked. The
voyage passage matches its prepared intro. The player approved this
transition. Full-recording vocal sign-off and repeated-play listening remain
open.

Preview: `previews/chinese-current-port-to-voyage-5s-2s.wav` under the local
audit directory. Metadata: `chinese-current-transition.json`.
Preview SHA-256:
`d90908d18f5eedd7a8375f1736f8b8e2215348fc51cddb2e145de0d3ae1de276`.

### Current Japanese port-to-voyage audition

The approved preview switches from Sakuya3 to Ametsuchi using the approved raw
supplied Ogg loops. The port starts at source time 20 s; the voyage enters
at the start of its supplied loop, retaining its original beginning. The
recordings and their approved repeat seams are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -14.04 dB and -14.11 dB
respectively. The 23-second, 44,100 Hz stereo preview has a measured sample
peak of -13.76 dBFS and no clipped samples. Source hashes, decoded loop
lengths and the complete fade render were independently checked. The player
approved this transition. Full-recording vocal sign-off and repeated-play
listening remain open.

Preview: `previews/japanese-current-port-to-voyage-5s-2s.wav` under the local
audit directory. Metadata: `japanese-current-transition.json`.
Preview SHA-256:
`fb063c42d41f0982b4cf145e437afe15b08f98d391d6bf29a14f4f77bd8c031a`.

### Current Korean port-to-voyage audition

The approved preview switches from Listening to Our Sounds to Beautiful Korea.
The port starts at loop offset 20 s (original source time 27 s), matching
the prepared port loop previously accepted as passable. The voyage starts
at source time zero, retaining its original opening. The approved repeat
edits are unchanged; handoff approval is a separate listening decision.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -6.05 dB and -16.54 dB
respectively. The 23-second, 44,100 Hz stereo preview has a measured sample
peak of -17.04 dBFS and no clipped samples. Original hashes, selected source
passages, the matching prepared port passage and the complete fade render
were independently checked. The player approved this transition. The port
repeat remains accepted as passable; full-recording vocal sign-off and
repeated-play listening remain open.

Preview: `previews/korean-current-port-to-voyage-5s-2s.wav` under the local
audit directory. Metadata: `korean-current-transition.json`.
Preview SHA-256:
`ede26b3aeeec1534c1ce32be7d81a296a41d75cfb47f291665dc1aaf9ae7363b`.

### Current Southeast Asian port-to-voyage audition

The approved preview switches from Hoi An Ancient Charm to Epic Nusantara. The
port starts at loop offset 20 s (original source time 64 s), matching its
prepared loop. The voyage starts at source time zero, retaining its original
opening. The approved repeat edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -8.92 dB and -12.03 dB
respectively. The 23-second stereo preview uses 44,100 Hz; Epic Nusantara's
48,000 Hz source is resampled for this mixed audition, with its native
prepared intro and loop unchanged. The measured sample peak is -9.90 dBFS,
with no clipped samples. Source formats, hashes, selected passages, the
matching prepared port passage and the complete fade render were
independently checked. The player approved this transition. Full-recording
vocal sign-off and repeated-play listening remain open.

Preview: `previews/southeast-asian-current-port-to-voyage-5s-2s.wav` under
the local audit directory. Metadata: `southeast-asian-current-transition.json`.
Preview SHA-256:
`0083c497db836f35207e254b4aef769ee9d81e561625c40a9cc08929549a17df`.

### Current South Asian port-to-voyage audition

The approved preview switches from Dhaka to Epic Indian Orchestral Fusion. The
port starts at loop offset 20 s (original source time 81 s), matching its
approved prepared loop. The voyage starts at source time 8 s to bypass the very
quiet opening. The player approved this entry; the approved repeat edits are
unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -3.93 dB and -11.23 dB
respectively. The 23-second stereo preview uses 44,100 Hz; the voyage's
48,000 Hz source is resampled for this mixed audition, with its native
prepared files unchanged. Its source entry is sample 384,000 at native
rate, corresponding to sample 352,800 in the audition-rate decode. The
measured sample peak is -10.25 dBFS, with no clipped samples. Source formats,
hashes, selected passages, the matching prepared port passage and the
complete fade render were independently checked. The player approved this
transition. Full-recording vocal sign-off and repeated-play listening remain
open.

Preview: `previews/south-asian-current-port-to-voyage-5s-2s.wav` under the
local audit directory. Metadata: `south-asian-current-transition.json`.
Preview SHA-256:
`60b90c1919ccf46346f975297b00d5d39667bc4184cb2ed216ef0a0be9e3b9db`.

### Current Arabian Gulf port-to-voyage audition

The approved preview switches from Middle East Ballad to Conquer The Great
Sands. The port starts at loop offset 20 s (original source time 58 s), matching
its approved prepared loop. The voyage starts at source time 30 s as it builds
into a fuller passage, bypassing the subdued opening. The player approved this
entry. After eight seconds of voyage playback, the prepared intro continues
contiguously into its loop at source time 38 s; that passage matches the
original recording. The approved repeat edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -12.55 dB and -9.80 dB
respectively. The 23-second, 44,100 Hz stereo preview has a measured sample
peak of -10.63 dBFS and no clipped samples. Source formats, hashes, selected
passages, matching prepared passages and the complete fade render were
independently checked. The player approved this transition. Full-recording
vocal sign-off and repeated-play listening remain open.

Preview: `previews/gulf-current-port-to-voyage-5s-2s.wav` under the local
audit directory. Metadata: `gulf-current-transition.json`.
Preview SHA-256:
`a000f3c793701926a88ef903d8b5cf658cc1b4c42daf39286c6b57d092c9a76f`.

### Current North African Desert2 port-to-voyage audition

The approved preview switches from Desert2 to Folk_Arabian using the approved
raw supplied Ogg recordings. The port starts at source time 20 s. The voyage
plays its 46,585-sample intro once (1.056349 s), then enters its supplied loop
contiguously, as previously approved. The intro and loop use the same constant
voyage gain. No source file or approved repeat seam is changed.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. The voyage's intro-to-loop join falls at clip time
9.056349 s within that fade. Constant audition gains are -14.85 dB and
-14.07 dB respectively. The 23-second, 44,100 Hz stereo preview has a
measured sample peak of -13.98 dBFS and no clipped samples. Source formats,
hashes, exact intro and loop lengths and the complete fade render were
independently checked. The player approved this transition. Full-recording
vocal sign-off and repeated-play listening remain open.

Preview: `previews/north-african-desert2-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`north-african-desert2-current-transition.json`.
Preview SHA-256:
`561bc71a14e4d11329256602a71347113e9776cdaf3c5be4fda2b5ff4188908c`.

### Current North African Arabic Music port-to-voyage audition

The approved preview switches from Arabic Music to Folk_Arabian. The port starts
at loop offset 20 s (original source time 36.25 s). The voyage retains the same
46,585-sample supplied intro followed by its loop as the approved Desert2
handoff. Both voyage files use the same constant gain. The approved repeat edits
are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. The intro-to-loop join falls at clip time 9.056349 s.
Constant audition gains are -12.82 dB and -14.07 dB respectively. The
23-second stereo preview uses 44,100 Hz; Arabic Music's 48,000 Hz source
is resampled for this audition, with native prepared files unchanged.
The selected source passage exactly matches the resampled prepared port
passage. The measured sample peak is -12.66 dBFS, with no clipped samples.
Source formats, hashes, exact intro and loop lengths and the complete fade
render were independently checked. The player approved this transition.
Full-recording vocal sign-off and repeated-play listening remain open.

Preview: `previews/north-african-arabic-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`north-african-arabic-current-transition.json`.
Preview SHA-256:
`92356dd6414f17a643fe5f881f670c62b5abf07a1f6cbf552d334904d6da97a3`.

### Current Mediterranean Atlas Greece port-to-voyage audition

The approved preview switches from Dellasera to Atlas • Greece. The port starts
at loop offset 20 s (original source time 60 s), matching its approved prepared
loop. The voyage starts at source time zero, retaining its original opening. The
approved repeat edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -9.18 dB and -8.44 dB
respectively. The 23-second stereo preview uses 44,100 Hz; Atlas • Greece's
48,000 Hz source is resampled for this mixed audition, with native prepared
files unchanged. The measured sample peak is -9.67 dBFS, with no clipped
samples. Source formats, hashes, selected passages, the matching prepared
port passage and the complete fade render were independently checked.
The player approved this transition. Full-recording vocal sign-off and
repeated-play listening remain open.

Preview: `previews/mediterranean-greece-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`mediterranean-greece-current-transition.json`.
Preview SHA-256:
`8e55d059f31e7a3168ecd867ece1f259df343d4d825dc0da102a09b171ef312b`.

### Current Mediterranean Cinematic Latin port-to-voyage audition

The approved preview switches from Dellasera to Cinematic Latin Music. The port
starts at loop offset 20 s (original source time 60 s), using the same passage
as the approved Atlas • Greece handoff. The voyage starts at source time 2 s,
bypassing its quiet lead-in. The player approved this entry; the approved repeat
edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -9.18 dB and -14.64 dB
respectively. Both sources and the 23-second stereo preview use 44,100 Hz.
The measured sample peak is -9.67 dBFS, with no clipped samples. Source
formats, hashes, selected passages, the matching prepared port passage and
the complete fade render were independently checked. The player approved
this transition. Full-recording vocal sign-off and repeated-play listening
remain open.

Preview: `previews/mediterranean-latin-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`mediterranean-latin-current-transition.json`.
Preview SHA-256:
`a1ad405c80dffa65b59abcc00f98eb953b1546d24afee05650490621bc81098e`.

### Current Northern Frangistan Lord port-to-voyage audition

The approved preview switches from Lord of the Land to Pathfinder. The port
starts at loop offset 20 s (original source time 45 s), matching its approved
prepared loop. The voyage starts at source time 1 s, skipping its nearly silent
lead-in while retaining the opening music. The player approved this entry; the
approved repeat edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are +0.20 dB and -9.00 dB
respectively. Both sources and the 23-second stereo preview use 44,100 Hz.
The measured sample peak is -2.47 dBFS, with no clipped samples. Source
formats, hashes, selected passages, the matching prepared port passage and
the complete fade render were independently checked. The player approved
this transition. Full-recording vocal sign-off and repeated-play listening
remain open.

Preview: `previews/northern-frangistan-lord-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`northern-frangistan-lord-current-transition.json`.
Preview SHA-256:
`4c911563dd222333295330965a420fc51d59392503ca5dd0f5be10d48926f853`.

### Current Northern Frangistan Townsong port-to-voyage audition

The approved preview switches from Townsong to Pathfinder. The port starts at
loop offset 20 s (original source time 52.5 s), matching its approved
prepared loop. The voyage starts at source time 1 s, using the same entry
as the approved Lord of the Land handoff. The approved repeat edits are
unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -13.06 dB and -9.00 dB
respectively. Both sources and the 23-second stereo preview use 44,100 Hz.
The measured sample peak is -13.07 dBFS, with no clipped samples. Source
formats, hashes, selected passages, the matching prepared port passage and
the complete fade render were independently checked. The player approved
this transition. Full-recording vocal sign-off and repeated-play listening
remain open.

Preview:
`previews/northern-frangistan-townsong-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`northern-frangistan-townsong-current-transition.json`.
Preview SHA-256:
`1db294a736ce47b413ed8396092cbbb5b25e24eae1cea76d934ae309edef0d27`.

### Current North American Market port-to-voyage audition

The approved preview switches from Market on the Sea to The World At Your Door.
The port starts at original source time 30 s, corresponding to offset
20 s within its approved raw derived loop. The voyage retains its original
ten-second prefix followed contiguously by its approved raw derived loop.
That entry occurs at clip time 18 s. The approved repeat edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -7.05 dB and -10.41 dB
respectively. Both sources and the 23-second stereo preview use 44,100 Hz.
The measured sample peak is -9.57 dBFS, with no clipped samples. Source
formats, hashes, selected passages and the complete fade render were
independently checked. The player approved this transition. Full-recording
vocal sign-off and repeated-play listening remain open.

Preview: `previews/north-american-market-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`north-american-market-current-transition.json`.
Preview SHA-256:
`77ffddc80bc2d2f42ccb7e96c1815b43997c8c4ad353573f5e76d3b5ea33ab89`.

### Current North American Swing port-to-voyage audition

The approved preview switches from Swing Train to The World At Your Door. The
port starts at loop offset 20 s (original source time 50.25 s), matching
its approved prepared loop. The voyage uses the same original ten-second
prefix followed contiguously by its raw derived loop as the approved
Market on the Sea handoff. Its prefix-to-loop entry falls at clip time
18 s. The approved repeat edits are unchanged.

Selection occurs at clip time 5 s. The outgoing cosine fade runs from
5 to 10 s; after the three-second settling delay, the incoming sine fade
runs from 8 to 10 s. Constant audition gains are -6.13 dB and -10.41 dB
respectively. Both sources and the 23-second stereo preview use 44,100 Hz.
The measured sample peak is -8.71 dBFS, with no clipped samples. Source
formats, hashes, selected passages, the matching prepared port passage and
the complete fade render were independently checked. The player approved
this transition, completing the sixteen-pair pass. Full-recording vocal
sign-off and repeated-play listening remain open.

Preview: `previews/north-american-swing-current-port-to-voyage-5s-2s.wav`
under the local audit directory. Metadata:
`north-american-swing-current-transition.json`.
Preview SHA-256:
`10ab85d2a3c1d744cba8b4ac4ce7b865afbb6fba84674c5717c6689f6770815a`.

## Local evidence and previews

The retained evidence is in the Git-ignored directory
`tmp/music-audit-2026-10-10/`, relative to the repository root. In this
checkout its absolute location is
`/Users/adsouza/Code/tijara-tides/tmp/music-audit-2026-10-10/`. Every local
file in the following index was checked on 11 October 2026. No recording was
added to the shipped game assets; cloning the repository does not restore this
local evidence. All filenames in the index tables below are relative to that
audit directory.

### Cleanup and historical audio references

On 10 October 2026, at the player's request, exactly 60 generated loop/intro
WAVs in the audit directory's root and 109 audition/transition audio files
under `previews/` were deleted. This removed 2,107.25 MiB (about 2.06 GiB) of
generated audio. Original recordings, supplied loops, ZIPs, license documents,
scripts and metadata were retained. Both publisher-supplied source WAVs were
preserved and appear in the source-file tables below.

Preview and prepared-WAV paths and hashes elsewhere in this audit describe the
files used for the earlier listening decisions; those generated audio files are
no longer present. The retained `previews/manifest.json` and
`previews/listen.html` are historical catalogs. Their preview links will fail
until the corresponding audio is regenerated. They do not indicate a missing
original recording or revoke an approved listening decision.

Retain the source recordings, edit JSON and rendering scripts together to
recreate needed audio on demand. Check regenerated files against the recorded
hashes before treating them as the previously approved render. Several old
scripts overwrite approval statuses or replace the preview manifest; do not
blindly rerun them against the retained evidence. Read or adapt the recipe to
write separate outputs and preserve the existing decisions and manifests. This
documentation update does not regenerate audio or duplicate the archive.

### Original recording index

The table lists the 32 initial audit recordings and four later replacement
candidates. `track-manifest.json` identifies the initial 32 sources; the
supplemental analysis records contain the other four sources and hashes. All 36
files were checked against those recorded SHA-256 values. A retained source is
not necessarily selected for the initial roster: rejected and reserve
recordings remain as historical evidence.

| Recording | Credited creator | Retained source file | Grant / identity record |
|---|---|---|---|
| Shenyang | Kevin MacLeod | `shenyang-mp3.mp3` | CC4 |
| Imperial China Cinematic | Shane Ivers | `imperial-china-mp3.mp3` | CC4 |
| Sakuya3 | PeriTune / Sei Mutsuki | `sakuya3-mp3.mp3` | CC4 |
| Ametsuchi | PeriTune / Sei Mutsuki | `ametsuchi-mp3.mp3` | CC4 |
| 국악 배경음악 #72 (Gugak Background Music #72) | 공유마당 (GongU Madang) | `gugak72-mp3.mp3` | CC4 |
| Beautiful Korea(뷰티플 코리아) | 윤영현 | `beautiful-korea-original.wav` | CC4 |
| Korean traditional-cinematic piece with gayageum | RibhavAgrawal | `korean-gayageum-mp3.mp3` | PB |
| Hoi An Ancient Charm | VPRODMUSIC_Asia_BGM | `hoi-an-mp3.mp3` | PB |
| Epic Nusantara - Free Gamelan Music from Indonesian | fiikuri | `epic-nusantara-mp3.mp3` | PB |
| Indian | Sub_Clair | `sub-clair-indian-mp3.mp3` | PB |
| Epic Indian Orchestral Fusion | Alejandro Piñero Amerio (vjgalaxy) | `epic-indian-fusion-mp3.mp3` | PB |
| Middle East Ballad | Abydos_Music | `middle-east-ballad-mp3.mp3` | PB |
| Conquer The Great Sands | Darren Curtis | `conquer-sands-files/Conquer the Great Sands OGG.ogg` | DC |
| Arabic Music | kiravale | `kiravale-arabic-mp3.mp3` | PB |
| Desert2 | PeriTune / Sei Mutsuki | `peritune-desert2-mp3.mp3` | CC4 |
| Folk_Arabian | PeriTune / Sei Mutsuki | `folk-arabian-mp3.mp3` | CC4 |
| Dellasera | Shane Ivers | `dellasera-mp3.mp3` | CC4 |
| Atlas • Greece | Vadim_Makes_Sound | `atlas-greece-mp3.mp3` | PB |
| Cinematic Latin Music | Sonican | `cinematic-latin-mp3.mp3` | PB |
| Lord of the Land | Kevin MacLeod | `lord-mp3.mp3` | CC4 |
| Townsong | Alexander Nakarada | `townsong-mp3.mp3` | CC4 |
| Home Was You | Scott Buckley | `home-mp3.mp3` | CC4 |
| Pathfinder | Scott Buckley | `pathfinder-mp3.mp3` | CC4 |
| Swing Train - Big Band Miller Style | JuliusH | `swing-train-mp3.mp3` | PB |
| Market on the Sea | Jonathan Shaw (InspectorJ) | `market-sea-legacy/Market on the Sea - MP3.mp3` | CC3 |
| The World At Your Door | Jonathan Shaw (InspectorJ) | `jshaw-world-legacy/The World At Your Door MP3.mp3` | CC3 |
| Dark Red Wine | Jason Shaw | `shaw-reggae-mp3.mp3` | CC4 |
| Setting Sail | Alexander Nakarada | `setting-sail-mp3.mp3` | CC4 |
| Atlas • Panama | Vadim_Makes_Sound | `atlas-panama-mp3.mp3` | PB |
| Epic Cinematic Salsa | Sonican | `epic-salsa-mp3.mp3` | PB |
| Tropical Contact | Jason Shaw | `shaw-lofi-mp3.mp3` | CC4 |
| Up In The Air | DonnySombrero | `brazil-up-in-air-mp3.mp3` | PB |
| 우리네 소리를 듣다 | 임다솔 (Im Dasol) | `im-dasol-our-sounds-mp3.mp3` | CC4; `im-dasol-our-sounds-analysis.json` |
| Dhaka | Kevin MacLeod | `dhaka-mp3.mp3` | CC4; `dhaka-analysis.json` |
| Beachfront Celebration | Kevin MacLeod | `beachfront-celebration-mp3.mp3` | CC4; `beachfront-celebration-analysis.json` |
| Sideways Samba | Jason Shaw | `sideways-samba-mp3.mp3` | CC4; `sideways-samba-analysis.json` |

CC4, CC3, DC and PB are defined in the license conditions above. Per-track
download links and source hashes are preserved in the recording identities
below and the supplemental analysis records. The shortlist contains exploratory
titles without downloaded originals, including Bombay Summer; those titles have
no retained source file in this archive yet.

### Supplied loops and alternate source formats

These are retained publisher-supplied audio files, not the deleted generated
WAVs. The PeriTune Ogg loops and Folk_Arabian Ogg intro are the approved
playback sources. Their MP3/M4A equivalents remain as alternate formats.
Beautiful Korea's two MP3 filenames have identical contents; its source WAV
remains the selected edit input. Curtis's Ogg is the selected edit input, with
its original WAV and MP3 also retained.

| Retained audio file | Purpose |
|---|---|
| `ametsuchi-loops/PerituneMaterial_Ametsuchi_loop.m4a` | Publisher-supplied loop or intro |
| `ametsuchi-loops/PerituneMaterial_Ametsuchi_loop.mp3` | Publisher-supplied loop or intro |
| `ametsuchi-loops/PerituneMaterial_Ametsuchi_loop.ogg` | Publisher-supplied loop or intro |
| `beautiful-korea-mp3.mp3` | Alternate original format / download |
| `beautiful-korea-original.mp3` | Alternate original format / download |
| `conquer-sands-files/Conquer the Great Sands MP3.mp3` | Alternate original format / download |
| `conquer-sands-files/Conquer the Great Sands WAV.wav` | Alternate original format / download |
| `folk-arabian-loops/PerituneMaterial_Folk_Arabian_loop.m4a` | Publisher-supplied loop or intro |
| `folk-arabian-loops/PerituneMaterial_Folk_Arabian_loop.mp3` | Publisher-supplied loop or intro |
| `folk-arabian-loops/PerituneMaterial_Folk_Arabian_loop.ogg` | Publisher-supplied loop or intro |
| `folk-arabian-loops/PerituneMaterial_Folk_Arabian_loop_intro.m4a` | Publisher-supplied loop or intro |
| `folk-arabian-loops/PerituneMaterial_Folk_Arabian_loop_intro.mp3` | Publisher-supplied loop or intro |
| `folk-arabian-loops/PerituneMaterial_Folk_Arabian_loop_intro.ogg` | Publisher-supplied loop or intro |
| `peritune-desert2-loops/PerituneMaterial_Desert2_loop.m4a` | Publisher-supplied loop or intro |
| `peritune-desert2-loops/PerituneMaterial_Desert2_loop.mp3` | Publisher-supplied loop or intro |
| `peritune-desert2-loops/PerituneMaterial_Desert2_loop.ogg` | Publisher-supplied loop or intro |
| `sakuya3-loops/PerituneMaterial_Sakuya3_loop.m4a` | Publisher-supplied loop or intro |
| `sakuya3-loops/PerituneMaterial_Sakuya3_loop.mp3` | Publisher-supplied loop or intro |
| `sakuya3-loops/PerituneMaterial_Sakuya3_loop.ogg` | Publisher-supplied loop or intro |

### License documents and source-grant evidence

Four publisher-supplied PDF documents are retained below. Each current PDF hash
agrees with the corresponding hash already recorded in this audit; the two
Jonathan Shaw license PDFs are byte-identical. The text extractions are
convenient reading copies, not substitutes for the supplied PDFs.

| Document | Purpose | SHA-256 |
|---|---|---|
| `conquer-sands-files/Conquer the Great Sands Materials Release.pdf` | Curtis signed Materials Release | `6daa2978433b5461564021acb89f12df37ffc126ac15a2f108ed25f7fc117c7a` |
| `jshaw-world-legacy/LICENSE - RPG Orchestral Essentials.pdf` | Jonathan Shaw legacy EULA | `10a7ac194bb5d0c63687468d366639e3540ec33b7ed7a393a9c98dcbae067d3a` |
| `jshaw-world-legacy/README - RPG Orchestral Essentials.pdf` | Jonathan Shaw recording/loop instructions | `249099d71031e02563e841a9fdf81397897396e10544aeebb5f8d66391d6d1a7` |
| `market-sea-legacy/LICENSE - RPG Orchestral Essentials.pdf` | Jonathan Shaw legacy EULA | `10a7ac194bb5d0c63687468d366639e3540ec33b7ed7a393a9c98dcbae067d3a` |

| Evidence | Retained local files |
|---|---|
| PDF text extractions | `curtis-release.txt`; `market-sea-license.txt`; `jshaw-world-license.txt`; `jshaw-world-readme.txt` |
| MacLeod general use notice | `macleod-use.html`; `macleod-use.txt` |
| PeriTune older-release terms | `peritune-terms.html`; `peritune-terms.txt` |
| Scott Buckley use instructions | `buckley-use.html`; `buckley-use.txt` |
| Alexander Nakarada FAQ | `nakarada-faq.html`; `nakarada-faq.txt` |
| Darren Curtis FAQ | `curtis-faq.html`; `curtis-faq.txt` |
| Jason Shaw / Audionautix FAQ | `audionautix-faq.html`; `audionautix-faq.txt` |
| shenyang source-page snapshots | `shenyang.html`; `shenyang.txt` |
| imperial-china source-page snapshots | `imperial-china.html`; `imperial-china.txt` |
| sakuya3 source-page snapshots | `sakuya3.html`; `sakuya3.txt` |
| ametsuchi source-page snapshots | `ametsuchi.html`; `ametsuchi.txt` |
| gugak72 source-page snapshots | `gugak72.html`; `gugak72.txt` |
| beautiful-korea source-page snapshots | `beautiful-korea.html`; `beautiful-korea.txt` |
| peritune-desert2 source-page snapshots | `peritune-desert2.html`; `peritune-desert2.txt` |
| folk-arabian source-page snapshots | `folk-arabian.html`; `folk-arabian.txt` |
| dellasera source-page snapshots | `dellasera.html`; `dellasera.txt` |
| lord source-page snapshots | `lord.html`; `lord.txt` |
| townsong source-page snapshots | `townsong.html`; `townsong.txt` |
| home source-page snapshots | `home.html`; `home.txt` |
| pathfinder source-page snapshots | `pathfinder.html`; `pathfinder.txt` |
| setting-sail source-page snapshots | `setting-sail.html`; `setting-sail.txt` |
| shaw-reggae source-page snapshots | `shaw-reggae.html`; `shaw-reggae.txt` |
| shaw-lofi source-page snapshots | `shaw-lofi.html`; `shaw-lofi.txt` |
| market-sea source-page snapshots | `market-sea.html`; `market-sea.txt` |
| jshaw-world source-page snapshots | `jshaw-world.html`; `jshaw-world.txt` |
| jshaw-rpg source-page snapshots | `jshaw-rpg.html`; `jshaw-rpg.txt` |
| Beachfront Celebration source page | `beachfront-source.html` |
| Sideways Samba source page | `sideways-samba-source.html` |
| Beautiful Korea download page | `beautiful-korea-download.html` |

The five offered Pixabay certificate PDFs listed in the license conditions
remain undownloaded. Their remote links are recorded there; this index does not
represent them as local files. Source URLs and recorded grants for other
recordings remain in this audit, the shortlist and `track-manifest.json`; the
local snapshot table only lists captures that actually exist. Not every source
grant has an offline page capture.

### Edit metadata and decision index

The JSON files below were retained unchanged by cleanup. Their
original-recording paths still exist; paths naming generated intro/loop WAVs or
previews are historical outputs, now absent. The per-track edit records retain
sample boundaries, fade curves, gains and hashes.
`player-listening-results.json` records decisions, raw supplied-loop
selections, the approved Folk_Arabian intro entry, Jonathan Shaw's derived loop
points and the selected transition behavior.

| Accepted repeat/edit | Metadata file |
|---|---|
| Shenyang | `shenyang-repeat-earlier-crossfade.json` |
| Imperial China Cinematic | `imperial-china-loop-revision.json` |
| Listening to Our Sounds — passable repeat | `im-dasol-our-sounds-loop.json` |
| Beautiful Korea | `beautiful-korea-original-repeat-crossfade.json` |
| Korean gayageum alternative | `korean-gayageum-loop-revision.json` |
| Hoi An Ancient Charm | `hoi-an-loop.json` |
| Epic Nusantara | `epic-nusantara-loop.json` |
| Dhaka | `dhaka-loop-phrase-revision.json` |
| Epic Indian Orchestral Fusion | `epic-indian-fusion-loop.json` |
| Middle East Ballad | `middle-east-ballad-loop.json` |
| Conquer The Great Sands | `conquer-sands-loop-revision.json` |
| Arabic Music | `kiravale-arabic-loop.json` |
| Dellasera | `dellasera-loop.json` |
| Atlas • Greece | `atlas-greece-loop.json` |
| Cinematic Latin Music | `cinematic-latin-loop.json` |
| Lord of the Land | `lord-loop.json` |
| Townsong alternative | `townsong-loop.json` |
| Home Was You alternative | `home-loop.json` |
| Pathfinder | `pathfinder-loop.json` |
| Swing Train | `swing-train-loop.json` |
| Beachfront Celebration | `beachfront-celebration-loop.json` |
| Setting Sail | `setting-sail-loop.json` |
| Epic Cinematic Salsa alternative | `epic-salsa-loop.json` |
| Sideways Samba | `sideways-samba-loop.json` |
| Up In The Air | `up-in-air-loop.json` |
| Sakuya3 — accepted edited alternative; supplied Ogg preferred | `sakuya3-loop-revision.json` |

| Raw loop / intro recipe | Decision file | Measurements / historical render catalog |
|---|---|---|
| Sakuya3, Ametsuchi, Desert2 and Folk_Arabian supplied Ogg loops | `player-listening-results.json` | `loops.json` |
| Folk_Arabian supplied intro followed by loop | `player-listening-results.json` | `previews/manifest.json` |
| Market on the Sea and The World At Your Door derived raw loops | `player-listening-results.json` | `loops.json` |

| Approved handoff | Metadata file |
|---|---|
| Sideways Samba → Up In The Air | `brazil-current-transition.json` |
| Beachfront Celebration → Setting Sail | `caribbean-current-transition.json` |
| Shenyang → Imperial China Cinematic | `chinese-current-transition.json` |
| Middle East Ballad → Conquer The Great Sands | `gulf-current-transition.json` |
| Sakuya3 → Ametsuchi | `japanese-current-transition.json` |
| Listening to Our Sounds → Beautiful Korea | `korean-current-transition.json` |
| Dellasera → Atlas • Greece | `mediterranean-greece-current-transition.json` |
| Dellasera → Cinematic Latin Music | `mediterranean-latin-current-transition.json` |
| Arabic Music → Folk_Arabian | `north-african-arabic-current-transition.json` |
| Desert2 → Folk_Arabian | `north-african-desert2-current-transition.json` |
| Market on the Sea → The World At Your Door | `north-american-market-current-transition.json` |
| Swing Train → The World At Your Door | `north-american-swing-current-transition.json` |
| Lord of the Land → Pathfinder | `northern-frangistan-lord-current-transition.json` |
| Townsong → Pathfinder | `northern-frangistan-townsong-current-transition.json` |
| Dhaka → Epic Indian Orchestral Fusion | `south-asian-current-transition.json` |
| Hoi An Ancient Charm → Epic Nusantara | `southeast-asian-current-transition.json` |

#### Earlier edits and recordings set aside

Keep these records as listening history. Their presence does not make them the
selected edit or track; prefer the accepted recipes and decisions above.

| Metadata file | Recorded disposition |
|---|---|
| `caribbean-current-transition-v1.json` | superseded; player reported apparent silence and revised fade timing |
| `conquer-sands-loop.json` | not approved; player reports transition needs work |
| `dark-red-wine-loop.json` | track reconsideration requested; loop not approved; Caribbean port selection reopened |
| `dhaka-loop-revision.json` | not approved; player reports melodic transition still needs work |
| `dhaka-loop.json` | not approved; player finds beginning and blend too drone-heavy; melodic revision needed |
| `gugak72-mp3-repeat-crossfade.json` | not approved; player reports silence before blend and repeat fatigue |
| `imperial-china-mp3-repeat-crossfade.json` | not selected; player reports silence on both sides of blend |
| `korean-gayageum-mp3-repeat-crossfade.json` | not approved; player accepts blend around four seconds but reports fade to silence near eight seconds |
| `shenyang-mp3-repeat-crossfade.json` | blend approved, but pre-blend interlude felt slightly jarring; revision requested |
| `sub-clair-indian-full-audition.json` | seam approved; song choice reconsidered after full-loop audition; variation not approved |
| `sub-clair-indian-loop-revision.json` | seam approved; song choice reconsidered after full-loop audition; variation not approved |
| `sub-clair-indian-loop.json` | not approved; player reports transition needs work |
| `tropical-contact-loop.json` | track reconsideration requested; loop not approved; Brazilian port selection reopened |

#### Analysis, manifests and search records

| Retained record | Purpose |
|---|---|
| `track-manifest.json` | Initial 32 source identities and grants |
| `analysis.json` | Initial 38-file screening and loudness results |
| `player-listening-results.json` | Player decisions and selected recipes |
| `previews/manifest.json` | Historical render metadata, hashes and approvals; audio deleted |
| `previews/listen.html` | Historical listening page; preview audio links are now missing |

| Other source / analysis metadata | Purpose |
|---|---|
| `beachfront-celebration-analysis.json` | Source/analysis/download record |
| `dhaka-analysis.json` | Source/analysis/download record |
| `downloads.json` | Source/analysis/download record |
| `extra-downloads.json` | Source/analysis/download record |
| `im-dasol-our-sounds-analysis.json` | Source/analysis/download record |
| `imperial-china-mp3-repeat-analysis.json` | Source/analysis/download record |
| `macleod-pieces-caribbean-refresh.json` | Downloaded catalogue lookup; not a roster selection |
| `macleod-pieces.json` | Downloaded catalogue lookup; not a roster selection |
| `pages.json` | Source/analysis/download record |
| `pixabay-downloads.json` | Source/analysis/download record |
| `sakuya3-repeat-analysis.json` | Source/analysis/download record |
| `shenyang-mp3-repeat-analysis.json` | Source/analysis/download record |
| `sideways-samba-analysis.json` | Source/analysis/download record |
| `voice-control-result.json` | Source/analysis/download record |

| Phrase / repeat search metadata | Purpose |
|---|---|
| `atlas-greece-phrase-search.json` | Search measurements; not a listening approval |
| `beachfront-celebration-phrase-search.json` | Search measurements; not a listening approval |
| `cinematic-latin-phrase-search.json` | Search measurements; not a listening approval |
| `conquer-sands-repeat-search.json` | Search measurements; not a listening approval |
| `dark-red-wine-phrase-search.json` | Search measurements; not a listening approval |
| `dellasera-repeat-search.json` | Search measurements; not a listening approval |
| `dhaka-phrase-search.json` | Search measurements; not a listening approval |
| `epic-indian-fusion-phrase-search.json` | Search measurements; not a listening approval |
| `epic-salsa-phrase-search.json` | Search measurements; not a listening approval |
| `home-phrase-search.json` | Search measurements; not a listening approval |
| `kiravale-arabic-phrase-search.json` | Search measurements; not a listening approval |
| `lord-phrase-search.json` | Search measurements; not a listening approval |
| `middle-east-ballad-repeat-search.json` | Search measurements; not a listening approval |
| `pathfinder-phrase-search.json` | Search measurements; not a listening approval |
| `setting-sail-phrase-search.json` | Search measurements; not a listening approval |
| `sideways-samba-phrase-search.json` | Search measurements; not a listening approval |
| `swing-train-phrase-search.json` | Search measurements; not a listening approval |
| `townsong-phrase-search.json` | Search measurements; not a listening approval |
| `tropical-contact-phrase-search.json` | Search measurements; not a listening approval |
| `up-in-air-phrase-search.json` | Search measurements; not a listening approval |

Rendering and inspection scripts remain in the same directory.
`verify_current_transition.py` checks a regenerated handoff against its
recorded inputs; the corresponding `prepare_*_transition.py` scripts contain
the handoff recipes, with `prepare_caribbean_transition_v2.py` providing the
accepted Caribbean version. Loop recipes are in the per-track
`prepare_*_loop.py` scripts and accepted revisions such as
`revise_dhaka_phrases.py`, `revise_conquer_sands_loop.py`,
`revise_imperial_repeat.py`, `revise_korean_gayageum_loop.py` and
`revise_shenyang_repeat.py`. Preserve these scripts when moving the evidence
directory.

## Recording identities and download sources

The following manifest fixes source recording identity. SHA-256 is for the
inspected audio member, not a ZIP or player page. Source page links above attach
the grant; download links below locate the matching asset or containing ZIP.
Temporary CDN URLs may change, so preserve both the source page and hash.

### Shenyang

- Creator: Kevin MacLeod.
- File: `tmp/music-audit-2026-10-10/shenyang-mp3.mp3`.
- [Download source](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Shenyang.mp3).
- SHA-256: `1cf2e0f57f820d82e9066ba4dca076735aedd512bc1909fdaa2e0065bd866786`.

### Imperial China Cinematic

- Creator: Shane Ivers.
- File: `tmp/music-audit-2026-10-10/imperial-china-mp3.mp3`.
- [Download source](https://www.silvermansound.com/wp-content/uploads/imperial-china-cinematic.mp3).
- SHA-256: `4a8bf29f72af49ad3e031f2c4f6c4bc05af2b2fadc2013dccb4dbaa4e800bc54`.

### Sakuya3

- Creator: PeriTune / Sei Mutsuki.
- File: `tmp/music-audit-2026-10-10/sakuya3-mp3.mp3`.
- [Download source](https://peritune.com/music/PerituneMaterial_Sakuya3.mp3).
- SHA-256: `21ff78d194af9557d299fee64730b8726d3a440e583a70b979bc7f6a6df254cf`.

### Ametsuchi

- Creator: PeriTune / Sei Mutsuki.
- File: `tmp/music-audit-2026-10-10/ametsuchi-mp3.mp3`.
- [Download source](https://peritune.com/music/PerituneMaterial_Ametsuchi.mp3).
- SHA-256: `c17eb0bf7dc6b23417d05628b26221ec51f66d1b35b25cb41d88363cfded3c3e`.

### 국악 배경음악 #72 (Gugak Background Music #72)

- Creator: 공유마당 (GongU Madang).
- File: `tmp/music-audit-2026-10-10/gugak72-mp3.mp3`.
- [Download source](https://gongu.copyright.or.kr/gongu/wrt/cmmn/wrtFileMediaPlay.do?wrtSn=13379655&fileSn=1).
- SHA-256: `bee4657c35613f750ef54d86c71ea3a9667286d5e7d0d8f273179a1fb71fd880`.

### Beautiful Korea(뷰티플 코리아)

- Creator: 윤영현.
- File: `tmp/music-audit-2026-10-10/beautiful-korea-original.wav`.
- [Download source](https://gongu.copyright.or.kr/gongu/wrt/cmmn/wrtFileDownload.do?wrtSn=13048827&fileSn=2).
- SHA-256: `9cf1764e974607463713c024151e6372759bbf6f05a928d737cdb9321474e215`.

### Korean traditional-cinematic piece with gayageum

- Creator: RibhavAgrawal.
- File: `tmp/music-audit-2026-10-10/korean-gayageum-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/08/20/audio_b0679da34f.mp3).
- SHA-256: `07eabbeefd563b41613a2ef7f8a932f2c8e8ced7553a34c660112178e92e7de0`.

### Hoi An Ancient Charm

- Creator: VPRODMUSIC_Asia_BGM.
- File: `tmp/music-audit-2026-10-10/hoi-an-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2023/04/20/audio_9b0ae5b8d1.mp3).
- SHA-256: `4ccc84353258f828ba25fdabb1c94f37e9279754d02f0470c128f56a7e5632c8`.

### Epic Nusantara - Free Gamelan Music from Indonesian

- Creator: fiikuri.
- File: `tmp/music-audit-2026-10-10/epic-nusantara-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2025/04/17/audio_109f028816.mp3).
- SHA-256: `84b32f1ecc6cdfafe9bed28e67260d93fd67f65a5c4c293caf35c84940130943`.

### Indian

- Creator: Sub_Clair.
- File: `tmp/music-audit-2026-10-10/sub-clair-indian-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/09/26/audio_9f3c1171e3.mp3).
- SHA-256: `de9f3c5ef7aa881109cd1ca0c36a316da22675199b25815f5b45cc8e82565282`.

### Epic Indian Orchestral Fusion

- Creator: Alejandro Piñero Amerio (vjgalaxy).
- File: `tmp/music-audit-2026-10-10/epic-indian-fusion-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/07/20/audio_f3e1af1ab3.mp3).
- SHA-256: `1d5f8d754964439415180f39cbcbee52963168063e922bd6af23bd78c6bffc18`.

### Middle East Ballad

- Creator: Abydos_Music.
- File: `tmp/music-audit-2026-10-10/middle-east-ballad-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2024/01/31/audio_bb4dc26759.mp3).
- SHA-256: `d59dd1ae0e41bb069683e644bbe34b09d9c8a4e74a35536f336a46496645e5c1`.

### Conquer The Great Sands

- Creator: Darren Curtis.
- File: `tmp/music-audit-2026-10-10/conquer-sands-files/Conquer the Great Sands OGG.ogg`.
- [Download source](https://www.mediafire.com/file_premium/axsv9ca4a1h3gd3/Darren_Curtis_Music_-_Conquer_the_Great_Sands.zip/file).
- SHA-256: `f3ac8a49aa79aeb5e7f801194a023b498c3dcbe950c52947d48638942fe2c59b`.

### Arabic Music

- Creator: kiravale.
- File: `tmp/music-audit-2026-10-10/kiravale-arabic-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/08/28/audio_1b94e0d496.mp3).
- SHA-256: `d6f50a99dcae46e2d9b6df15052effdca4bc8eb123b9da965223dbae40a856f1`.

### Desert2

- Creator: PeriTune / Sei Mutsuki.
- File: `tmp/music-audit-2026-10-10/peritune-desert2-mp3.mp3`.
- [Download source](https://peritune.com/music/PerituneMaterial_Desert2.mp3).
- SHA-256: `591d1e5bc6de1f4c2b9b48299f6048d2d3baba87cf6ff5d42530f707e563465f`.

### Folk_Arabian

- Creator: PeriTune / Sei Mutsuki.
- File: `tmp/music-audit-2026-10-10/folk-arabian-mp3.mp3`.
- [Download source](https://peritune.com/music/PerituneMaterial_Folk_Arabian.mp3).
- SHA-256: `958c97661057ac0bed77df638f94d1c2e6fdd95be84695b028eba860c61e0d83`.

### Dellasera

- Creator: Shane Ivers.
- File: `tmp/music-audit-2026-10-10/dellasera-mp3.mp3`.
- [Download source](https://www.silvermansound.com/wp-content/uploads/dellasera.mp3).
- SHA-256: `ad7fd4e2801e4639e036c6c8e853590a343c843ab4999c2cb84157f2b4a32bd3`.

### Atlas • Greece

- Creator: Vadim_Makes_Sound.
- File: `tmp/music-audit-2026-10-10/atlas-greece-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/06/27/audio_d598f8d41c.mp3).
- SHA-256: `3ea6cf484d3a50da687356147ae17c3dc6baee038ec26e808df86595052987fb`.

### Cinematic Latin Music

- Creator: Sonican.
- File: `tmp/music-audit-2026-10-10/cinematic-latin-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/05/07/audio_1f827b6355.mp3).
- SHA-256: `f247da8604b430656d6a5b6195601b90146ed40dac4f03a8ea97556139c580e7`.

### Lord of the Land

- Creator: Kevin MacLeod.
- File: `tmp/music-audit-2026-10-10/lord-mp3.mp3`.
- [Download source](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Lord%20of%20the%20Land.mp3).
- SHA-256: `47ce185fdc1f2e5514566307d652d6cb62a06bed47ea730e28214d3cedc2f948`.

### Townsong

- Creator: Alexander Nakarada.
- File: `tmp/music-audit-2026-10-10/townsong-mp3.mp3`.
- [Download source](https://d19p7hqu4j8vx0.cloudfront.net/media/media/data/mp3s/Townsong.mp3).
- SHA-256: `44cd85056f2c82dcd03c7c3b60e914f3b3a6fd2305d23af38c9a32ce1b5c70af`.

### Home Was You

- Creator: Scott Buckley.
- File: `tmp/music-audit-2026-10-10/home-mp3.mp3`.
- [Download source](https://www.scottbuckley.com.au/library/wp-content/uploads/2026/07/HomeWasYou.mp3).
- SHA-256: `4d4cf96e941c61cbdab71ef49c6dd6b67d6fd1df00926fac2f6e419e34d76d61`.

### Pathfinder

- Creator: Scott Buckley.
- File: `tmp/music-audit-2026-10-10/pathfinder-mp3.mp3`.
- [Download source](https://www.scottbuckley.com.au/library/wp-content/uploads/2021/04/sb_pathfinder.mp3).
- SHA-256: `f20e3e9aaac2d947510ec971d7ea477320370091c3ea7b1541792c3fe5683e78`.

### Swing Train - Big Band Miller Style

- Creator: JuliusH.
- File: `tmp/music-audit-2026-10-10/swing-train-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2021/02/07/audio_75fb7fc1d6.mp3).
- SHA-256: `b66669c82cd86ca93f0ceb2556c7c4fa5713dd592b81a6ac2f97870e2877048b`.

### Market on the Sea

- Creator: Jonathan Shaw (InspectorJ).
- File: `tmp/music-audit-2026-10-10/market-sea-legacy/Market on the Sea - MP3.mp3`.
- [Download source](https://opengameart.org/sites/default/files/market_on_the_sea_mp3.zip).
- SHA-256: `8c7b6db9dd571cb1ec6eea6c7b035f2c0541c37d95d10f868bc38fe87eff6d8d`.

### The World At Your Door

- Creator: Jonathan Shaw (InspectorJ).
- File: `tmp/music-audit-2026-10-10/jshaw-world-legacy/The World At Your Door MP3.mp3`.
- [Download source](https://opengameart.org/sites/default/files/The%20World%20At%20Your%20Door%20MP3.zip).
- SHA-256: `e9de1adfaf385d003ae3e281bd1d7158e0d8c127964177daf8eea75a072eaa64`.

### Dark Red Wine

- Creator: Jason Shaw.
- File: `tmp/music-audit-2026-10-10/shaw-reggae-mp3.mp3`.
- [Download source](https://audionautix.com/Music/DarkRedWine.mp3).
- SHA-256: `b32dc17007bbc3459a581b9ba5c79c78a6a2c999ba7a2ea7b3994073d74d3d0c`.

### Setting Sail

- Creator: Alexander Nakarada.
- File: `tmp/music-audit-2026-10-10/setting-sail-mp3.mp3`.
- [Download source](https://d19p7hqu4j8vx0.cloudfront.net/media/media/data/mp3s/Setting_Sail.mp3).
- SHA-256: `e496000eaa81a0a8eaeb8ae7fe5c441cf6b3a8610678600069f8e50bf9231e9c`.

### Atlas • Panama

- Creator: Vadim_Makes_Sound.
- File: `tmp/music-audit-2026-10-10/atlas-panama-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/07/30/audio_2a08e56d6a.mp3).
- SHA-256: `80db98ab772bfae9182d2f79d8bc944909fc216bee2b38bd932ad2f8d78807c7`.

### Epic Cinematic Salsa

- Creator: Sonican.
- File: `tmp/music-audit-2026-10-10/epic-salsa-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2024/11/30/audio_279ee24e7b.mp3).
- SHA-256: `ff76412039d6d9bf6d04c13f3c598f7438c23339ff446ec73acb0c07ad964714`.

### Tropical Contact

- Creator: Jason Shaw.
- File: `tmp/music-audit-2026-10-10/shaw-lofi-mp3.mp3`.
- [Download source](https://audionautix.com/Music/TropicalContact.mp3).
- SHA-256: `d1d9f183156ac74a53c9859d3cdc9f3644f08663573a1aee42c147ee9fe6abfd`.

### Up In The Air

- Creator: DonnySombrero.
- File: `tmp/music-audit-2026-10-10/brazil-up-in-air-mp3.mp3`.
- [Download source](https://cdn.pixabay.com/audio/2026/03/10/audio_0a2917ad6e.mp3).
- SHA-256: `ba9ad15d406ddba4f9aa7df0ef8e51631a82605a1992e947c7698611fddc951e`.

Additional loop files and the Korean MP3 are recorded here so the actual
analysis variants remain identifiable.

| Inspected variant | SHA-256 |
|---|---|
| PerituneMaterial_Ametsuchi_loop.ogg | `80e7da0a3f0e2521dca894a542cb0aa4cc665a4631b7461bcd4ef2ec4dcb5690` |
| beautiful-korea-mp3.mp3 | `db7d5a3e8f2cc8e80545b197620ca069498300531a0a3b996d53574548f33e27` |
| PerituneMaterial_Folk_Arabian_loop.ogg | `3f4222b81f8e629e32e67397f4ab2b25185de8309e95b174aba56da2ea878eab` |
| PerituneMaterial_Folk_Arabian_loop_intro.ogg | `9bedd0b6b54fc7e5d2dac75efa5c009b4df01786cb155a8253bf58e46897a4fc` |
| PerituneMaterial_Desert2_loop.ogg | `5a52ac399d599866b1f87659b40c7ffa2418e11baf5a34fc899b37df19c9f43a` |
| PerituneMaterial_Sakuya3_loop.ogg | `96f99c1604f819e08962e74ac3e78c6760b1cc49029f820543b51f867f0b64da` |

Curtis release SHA-256:
`6daa2978433b5461564021acb89f12df37ffc126ac15a2f108ed25f7fc117c7a`.

Jonathan Shaw license PDF SHA-256 (identical in both selected legacy ZIPs):
`10a7ac194bb5d0c63687468d366639e3540ec33b7ed7a393a9c98dcbae067d3a`.

The World At Your Door README PDF SHA-256:
`249099d71031e02563e841a9fdf81397897396e10544aeebb5f8d66391d6d1a7`.

Screening model SHA-256:
`d3835ffbbd4a1bb3e777f0ca217b5007907f5171dd5d17c4236b95b2af8f908e`.

## Outstanding before adding the soundtrack

1. Choose the initial roster where multiple leads remain. Older exploratory
   reserves require their own exact-file audit if promoted.
2. Listen to the complete chosen recordings and record explicit vocal absence
   and repeated-play suitability. The two flagged passages have player
   decisions; Atlas • Panama is excluded. The current repeat-seam pass and
   sixteen listed port-to-voyage handoffs are complete, with the Korean port
   repeat accepted as passable. Unreviewed initial entries remain to check.
3. Save the five offered Pixabay certificate PDFs with the asset provenance.
4. Prepare final encodes, loop points and credits, then verify playback and
   selection behavior, rapid reselection and the top-of-screen track display
   in the actual client when music is implemented.

## Release listening gate

On 12 October 2026 the player auditioned the prepared soundtrack locally with
`TIJARA_MUSIC_AUDITION=true` and approved release. `priv/music/approvals.json`
records a blanket approval: all 28 recordings, all 28 encoded selection entries
and whole-recording repeats, the sixteen within-palette port-to-voyage pairings,
and three representative cross-region voyage handoffs, each with its reverse:
Conquer The Great Sands and Epic Indian Orchestral Fusion, Atlas • Greece and
Folk Arabian, and Imperial China Cinematic and Ametsuchi. These are samples of
the 89 possible cross-region pairs among the 14 voyage pieces; handoffs between
other regions still play. Each record notes that not every complete recording,
repeat or pairing was necessarily heard in full, so these records do not
certify a complete listen of every asset. The approval report contains only
approved entries; removing a reverse handoff makes it pending again.

## Client playback probes

On 12 October 2026, on macOS 27.0.1, the Tauri 2.11.5 desktop client (WKWebView)
connected to a local audition server and played the soundtrack after the first
click, so the Opus assets need no AAC fallback. The rapid-reselection listening
check in Chromium was not run.

[ametsuchi]: https://peritune.com/blog/2018/10/01/ametsuchi/
[atlas-greece]: https://pixabay.com/music/orchestral-atlas-greece-555434/
[atlas-panama]: https://pixabay.com/music/instrumental-atlas-panama-576797/
[audionautix-faq]: https://audionautix.com/faqs.php
[beautiful-korea]: https://gongu.copyright.or.kr/gongu/wrt/wrt/view.do?menuNo=200020&wrtSn=13048827
[brazil-up-in-air]: https://pixabay.com/music/samba-latin-up-in-the-air-499093/
[buckley-use]: https://www.scottbuckley.com.au/library/using-this-music/
[cinematic-latin]: https://pixabay.com/music/latin-cinematic-latin-music-523433/
[conquer-sands]: https://www.darrencurtismusic.com/world-music
[curtis-faq]: https://www.darrencurtismusic.com/faqs
[dellasera]: https://www.silvermansound.com/free-music/dellasera
[epic-indian-fusion]: https://pixabay.com/music/india-epic-indian-orchestral-fusion-570933/
[epic-nusantara]: https://pixabay.com/music/world-epic-nusantara-free-gamelan-music-from-indonesian-328513/
[epic-salsa]: https://pixabay.com/music/samba-latin-epic-cinematic-salsa-270433/
[folk-arabian]: https://peritune.com/blog/2016/11/28/folk_arabian/
[gugak72]: https://gongu.copyright.or.kr/gongu/wrt/wrt/view.do?menuNo=200020&wrtSn=13379655
[hoi-an]: https://pixabay.com/music/world-hoi-an-ancient-charm-147064/
[home]: https://www.scottbuckley.com.au/library/home-was-you/
[imperial-china]: https://www.silvermansound.com/free-music/imperial-china-cinematic
[jshaw-world]: https://opengameart.org/content/the-world-at-your-door-rpg-orchestral-essentials-overworld-music
[kiravale-arabic]: https://pixabay.com/music/arabic-arabic-music-593673/
[korean-gayageum]: https://pixabay.com/music/orchestral-korean-traditional-cinematic-piece-with-gayageum-589500/
[lord]: https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1400022
[market-sea]: https://opengameart.org/content/market-on-the-sea-rpg-orchestral-essentials-village-music
[middle-east-ballad]: https://pixabay.com/music/world-middle-east-ballad-188926/
[nakarada-faq]: https://creatorchords.com/faq/
[pathfinder]: https://www.scottbuckley.com.au/library/pathfinder/
[peritune-desert2]: https://peritune.com/blog/2018/05/01/desert2/
[peritune-terms]: https://peritune.com/about/
[pixabay-terms]: https://pixabay.com/service/terms/
[sakuya3]: https://peritune.com/blog/2016/10/18/sakuya3/
[setting-sail]: https://creatorchords.com/music/setting-sail/
[shaw-lofi]: https://audionautix.com/free-music/lo-fi
[shaw-reggae]: https://audionautix.com/free-music/reggae
[shenyang]: https://www.incompetech.com/music/royalty-free/index.html?isrc=USUAN1600066
[sub-clair-indian]: https://pixabay.com/music/india-indian-610511/
[swing-train]: https://pixabay.com/music/big-band-swing-train-big-band-miller-style-2667/
[townsong]: https://creatorchords.com/music/townsong/
[cc4]: https://creativecommons.org/licenses/by/4.0/
[cc3]: https://creativecommons.org/licenses/by/3.0/
[yamnet]: https://huggingface.co/audiomagic/yamnet-onnx
