# Audio Asset Rules

This project uses a calm, healing audio direction. Sounds should feel soft, natural, and low-pressure. Avoid arcade pings, sharp reward stingers, synthetic beeps, loud fanfare, and busy music.

## The tone budget (enforced, not advisory)

"Calm" is measurable, and the generators assert it. Every new one-shot must clear two numbers before it ships:

- **Spectral centroid ≤ 4300 Hz** (`tools/synth_feedback_sfx.py`), or **≤ 6100 Hz** for the water-layered catch sounds (`tools/prepare_catch_and_foley.py`). Reference points from the assets that were already accepted: `upgrade` 697 Hz, `bite` 721 Hz, `cast` 1191 Hz, `catch_rare` 4286 Hz, `catch_common` 6048 Hz. A chime whose inharmonic partials out-shine `catch_rare` reads as an arcade ping against the watercolour palette — this is exactly what the first draft of these sounds did.
- **|DC offset| ≤ 0.0015**. Karplus-Strong seeds from a noise burst whose mean is not zero; the loudest DC among the shipping recorded assets is `ui_click` at 0.00143.

Both scripts exit non-zero when a sound breaks budget. Don't relax the numbers to make a sound fit.

## The catch ladder (asserted in the generator and in validate_game.gd)

A rarer fish must never sound weaker or shorter than a commoner one. Four tiers, mapped by `CornerFishing._catch_sfx()`:

| Sound | Fires on | peak | onset RMS | eff. duration |
| --- | --- | --- | --- | --- |
| `catch_common` | everything else | 0.300 | 0.0264 | 0.34 s |
| `catch_good` | ★★ quality | 0.310 | 0.0263 | 0.40 s |
| `catch_rare` | rare/epic tier, 斑斓 variant, or ★★★ | 0.320 | 0.0289 | 0.44 s |
| `catch_epic` | 鎏金/七彩 variant, or 传说/神话 tier | 0.320 | 0.0333 | 1.80 s |

`verify_ladder()` in `tools/prepare_catch_and_foley.py` re-measures these on every build and fails if the ordering breaks. Two traps it exists to catch:

- **Full-file RMS is the wrong loudness measure.** `catch_epic`'s long shimmer tail drags its mean RMS *below* `catch_common`'s. What the player registers is the attack — hence `onset_rms`, the RMS of the first 300 ms.
- **Peak-normalising a multi-layer mix scales the anchor down.** Every layer overlapping the splash transient raises the mix peak, and normalisation then shrinks the splash. Adding a "bigger" layer made `catch_epic` *quieter*, twice. Multi-layer sounds use `"anchor"` mode instead: the splash alone is scaled to `peak`, extra layers add on top, and `peak_limit` is a clip guard rather than a loudness target.

`catch_epic`'s timeline mirrors `catch_rare`'s one tier up — splash at 0.00 s, a *sustained* layer at 0.18 s, then melody. Most of `catch_rare`'s perceived weight comes from its sustained confirmation tone (crest 2.3), not from its water. A plucked-string tail decays instantly (crest 4.2) and cannot fill that role, so `catch_epic` uses a thrashing-fish recording as its sustain — measured to contribute the same post-scale RMS the confirmation tone does.

## Current Asset Set

All runtime audio assets live under `res://assets/audio/`.

| ID | File | Use | Loop |
| --- | --- | --- | --- |
| `ui_click` | `res://assets/audio/ui/ui_click.wav` | Generic button/toggle/tab tap | No |
| `ui_error` | `res://assets/audio/ui/ui_error.wav` | Invalid action, insufficient coins | No |
| `cast` | `res://assets/audio/fishing/cast.wav` | Rod cast / line movement | No |
| `bobber_splash` | `res://assets/audio/fishing/bobber_splash.wav` | Bobber lands in water | No |
| `bite` | `res://assets/audio/fishing/bite.wav` | Fish bite / bobber twitch cue | No |
| `catch_common` | `res://assets/audio/fishing/catch_common.wav` | Common catch | No |
| `catch_good` | `res://assets/audio/fishing/catch_good.wav` | ★★ quality catch | No |
| `catch_rare` | `res://assets/audio/fishing/catch_rare.wav` | Rare tier / 斑斓 / ★★★ | No |
| `catch_epic` | `res://assets/audio/fishing/catch_epic.wav` | 鎏金·七彩 variant, 传说·神话 tier | No |
| `coin` | `res://assets/audio/economy/coin.wav` | Money gained / sell payout | No |
| `upgrade` | `res://assets/audio/economy/upgrade.wav` | Upgrade purchased | No |
| `sfx_new_species` | `res://assets/audio/feedback/sfx_new_species.wav` | First-ever capture of a species | No |
| `sfx_record` | `res://assets/audio/feedback/sfx_record.wav` | Personal-best weight broken | No |
| `sfx_achievement` | `res://assets/audio/feedback/sfx_achievement.wav` | Achievement unlocked | No |
| `sfx_focus_reward` | `res://assets/audio/feedback/sfx_focus_reward.wav` | Focus reward earned (25/50 min) | No |
| `sfx_event_appear` | `res://assets/audio/feedback/sfx_event_appear.wav` | A random event begins | No |
| `sfx_competition_win` | `res://assets/audio/feedback/sfx_competition_win.wav` | Weekly giant-fish contest gold | No |
| `sfx_spot_unlock` | `res://assets/audio/feedback/sfx_spot_unlock.wav` | New fishing spot unlocked | No |
| `sfx_cat_steal` | `res://assets/audio/feedback/sfx_cat_steal.wav` | The cat steals a fish | No |
| `sfx_fish_struggle` | `res://assets/audio/feedback/sfx_fish_struggle.wav` | A 巨物 breaks the surface | No |
| `sfx_reel_tension` | `res://assets/audio/feedback/sfx_reel_tension.wav` | Bite → catch window (0.9 s) | Yes |
| `bgm_day` | `res://assets/audio/music/bgm_day.ogg` | Main loop (dawn/day/dusk) | Yes |
| `bgm_night` | `res://assets/audio/music/bgm_night.ogg` | Night variation | Yes |
| `ambience_water_loop` | `res://assets/audio/ambience/ambience_water_loop.wav` | Background water ambience | Yes |
| `amb_stream_loop` | `res://assets/audio/ambience/amb_stream_loop.wav` | Stream/riffle ambience layer | Yes |
| `amb_birds_day` | `res://assets/audio/ambience/amb_birds_day.wav` | Daytime woodland birdsong layer | Yes |
| `amb_wind_loop` | `res://assets/audio/ambience/amb_wind_loop.wav` | Open-air wind layer | Yes |
| `amb_night_insects` | `res://assets/audio/ambience/amb_night_insects.wav` | Night cricket layer | Yes |
| `amb_waves_loop` | `res://assets/audio/ambience/amb_waves_loop.wav` | Ocean swell layer | Yes |
| `amb_gulls_day` | `res://assets/audio/ambience/amb_gulls_day.wav` | Coastal gull layer | Yes |
| `amb_cave_drip` | `res://assets/audio/ambience/amb_cave_drip.wav` | Cave water-drip echo layer | Yes |

The machine-readable manifest is `res://assets/audio/audio_manifest.json`.

`feedback/sfx_epic_tail.wav` is rendered to disk but deliberately **absent from the manifest**: it is only
layered into `catch_epic` by the build, never played on its own, and `AudioManager` eagerly `load()`s every
manifest entry at startup. `NOT_PLAYABLE` in `tools/synth_feedback_sfx.py` is what keeps it out.

## Ambience Bed (layered, biome × time-of-day)

`AudioManager` mixes a **layered ambience bed** instead of one flat water loop. Multiple looping streams play
simultaneously and crossfade (≈2.5 s) whenever the fishing spot or day-phase changes, driven by a recipe of
`biome × phase`. `main.gd` calls `Audio.set_ambience_scene(spot_key, day_phase)` on start, on phase change
(`_apply_phase`), and on spot change (`_apply_spot_visuals`).

**Graceful degradation:** a layer that has no asset in the manifest simply gets no player and is skipped in
every recipe — so the bed silently falls back to whatever layers do exist. All eight layers ship today; if a
layer's wav is ever removed the bed still varies by time-of-day via a global gain (night quietest, golden
hours softer, daytime fullest), so behaviour never regresses, and a layer lights back up the moment its wav
returns.

| Layer ID | Role | Loop | Status |
| --- | --- | --- | --- |
| `ambience_water_loop` | Generic still-water base (most freshwater spots) | Yes | **Present** |
| `amb_stream_loop` | Faster stream/riffle (mountain_stream, river_bend) | Yes | **Present** |
| `amb_birds_day` | Daytime woodland birdsong (freshwater/forest, day + golden) | Yes | **Present** |
| `amb_wind_loop` | Open-air wind (lake, polar) | Yes | **Present** |
| `amb_night_insects` | Night crickets (warm freshwater/lake nights; not polar/sea) | Yes | **Present** |
| `amb_waves_loop` | Ocean swell (sea base: coast_pier, estuary, deep_sea, coral_reef) | Yes | **Present** |
| `amb_gulls_day` | Gulls (coast, daytime) | Yes | **Present** |
| `amb_cave_drip` | Cave water-drip echo (cavern_pool base) | Yes | **Present** |

Spot→biome mapping and the per-biome recipe live in `audio_manager.gd` (`SPOT_BIOME`, `_ambience_recipe`).
Keep all layers quiet (same 10-16 dB below SFX guidance) — they are a bed, not a focal sound. Each new layer
should be a seamless loop ≥15 s, gentle, with no obvious repeat spike. To enable one, drop the wav under
`res://assets/audio/ambience/` and add a manifest entry with `"loop": true`, e.g.:

```json
"amb_birds_day": {
  "path": "res://assets/audio/ambience/amb_birds_day.wav",
  "duration_seconds": 20.0,
  "loop": true,
  "description": "Quiet daytime woodland birdsong bed. Source: <CC0 pack>."
}
```

**How the seven natural layers were made.** The local SFX packs hold no nature field recordings, so these
layers are built from **real CC0 / public-domain recordings** sourced from Wikimedia Commons (Freesound CC0
mirror) and OpenGameArt CC0 (exact origins in the source table below). Two committed scripts make the pipeline
reproducible:

1. `tools/fetch_ambience_sources.py` — downloads the raw CC0 recordings into
   `E:\ai-audio\free-sfx\ambience_sources\` (outside the repo, like the other free-SFX sources).
2. `tools/prepare_ambience_assets.py` — converts each to mono 44.1 kHz, gently softens it (high-pass ~45 Hz to
   kill rumble, low-pass ~11 kHz to tame harsh highs), and turns it into a seamless loop ≥15 s. Continuous
   textures (stream/wind/birds/insects/cave) use an **equal-power boundary crossfade** (tail blended back over
   the head); event beds (waves/gulls) **scatter the real crashes/calls into a ring buffer** with wrap-around.
   Either way the loop is click-free, and file peaks are normalized to 0.12–0.18 (below the 0.20–0.32 SFX peaks;
   runtime `ambience_volume × recipe gain` drops them further).

Regenerate (fetch first, then build):

```powershell
E:\ai-audio\stable-audio-open\.venv\Scripts\python.exe tools\fetch_ambience_sources.py
E:\ai-audio\stable-audio-open\.venv\Scripts\python.exe tools\prepare_ambience_assets.py
```

After regenerating, run `godot --headless --import` so the new wavs are imported before the game can see
them. The script **merges** its seven keys into the manifest; `prepare_free_sfx_assets.py` likewise merges,
so either generator can be rerun without clobbering the other's entries.

## Music (bgm_day / bgm_night)

Two CC0 tracks, cross-faded over 4 s by `Audio.set_music_scene(phase)` — `bgm_night` at night, `bgm_day` otherwise. Driven from the same call site as the ambience bed, so start / phase-change / spot-change are all covered.

Music sits **under** the ambience bed (music peaks 0.24 vs. ambience 0.12–0.18, and `music_volume` defaults to 0.30). This is a desk-corner companion, not a media player. `music_enabled` is a separate field from `music_volume` so switching music off and back on remembers the level.

Both tracks were trimmed to their musical body **before** looping. Cross-fading a composed fade-out back over a full-volume head produces an audible swell every loop; `trim_to_body()` cuts where the music was still at ≥50% of its typical loudness. Seams are verified against the interior maximum sample-delta on every build.

> **Windows/libsndfile trap:** a single `sf.write` of more than ~10 s of Vorbis overflows the stack (0xC00000FD). `write_ogg()` streams in 4 s blocks instead. Also, Ogg files carry a random bitstream serial number, so **two byte-identical builds have different md5s** — compare decoded PCM, not file hashes.

## Reel tension (bite → catch)

`sfx_reel_tension` is the only *sustained* SFX. It gets its own `AudioStreamPlayer` — the 8-voice round-robin pool would let the next `play_sfx` cut it off mid-loop. Fast fade in (0.10 s: tension must establish immediately), slower fade out (0.22 s: no hard cut at the moment the fish lands).

`Audio.start_tension(tier)` pitches down for bigger fish, but `main.gd` always passes `1`. The fish isn't rolled until `_do_catch()`, and rolling early would shift the RNG sequence and break validate's deterministic baseline. Size is expressed at the moment of the catch instead, via `sfx_fish_struggle`.

## Playback Rules

- Route all playback through `AudioManager`; do not scatter `AudioStreamPlayer` nodes across UI/business logic.
- Keep `ambience_water_loop` quiet. Suggested ambience bus volume is lower than SFX by roughly 10-16 dB.
- High-frequency sounds need cooldowns. `DEFAULT_COOLDOWNS_MS` in `audio_manager.gd` is the source of truth; the milestone stingers are long and will smear over their own tails without one (`sfx_achievement` 700 ms — one `_check_achievements()` can unlock several at once; `sfx_cat_steal` 1200 ms — otherwise the cat becomes a meow machine gun).
- Reward sounds should never block or overpower the scene. `catch_rare` is for rare-tier and above (see the catch ladder); ★★ quality gets `catch_good`.
- Avoid layering `coin`, `upgrade`, and the catch sounds at full volume in the same frame. Prefer a short stagger (`sfx_new_species` and `sfx_record` are delayed 0.35 s so they clear the splash peak; `events.gd` staggers `coin` 0.30 s behind `sfx_event_appear` to preserve the cause→effect reading) or choose the strongest semantic sound.
- **Muting must stop the sustained layers too.** `muted` only gates `play_sfx`; BGM and the tension loop keep playing unless `set_muted()` explicitly stops them. Regression-tested in `_check_audio()`.
- Persist user audio settings: master, SFX, ambience, music volume, music on/off, and mute.

## Regenerating (order matters)

`tools/prepare_catch_and_foley.py` consumes `sfx_epic_tail` from the synth step, so:

```powershell
# One-time (or after a machine wipe): rebuild the out-of-repo source packs.
python tools\fetch_foley_sources.py       # 3 CC0 packs + cat/thrash/creak, with size asserts
python tools\fetch_ambience_sources.py    # the 7 nature recordings
python tools\fetch_music_sources.py       # the 5 CC0 music tracks

# Build:
python tools\prepare_free_sfx_assets.py   # 0. base SFX (reproduces the committed wavs bit-exact)
python tools\synth_feedback_sfx.py        # 1. synthesized voices
python tools\prepare_catch_and_foley.py   # 2. catch ladder + foley (reads sfx_epic_tail)
python tools\prepare_ambience_assets.py   # 3. biome ambience beds
python tools\prepare_music_assets.py      # 4. BGM loops
godot --headless --import                 # twice, then run validate_game.gd
```

The fetch scripts assert the byte count of every download and hard-fail rather than skipping,
so an upstream re-upload surfaces immediately instead of silently changing a sound. Wikimedia's
Ogg Vorbis files ship multiplexed with an Ogg Skeleton stream that libsndfile and Godot both
reject; `tools/ogg_strip.py` re-muxes them losslessly. Because stripping *shrinks* the file, the
size assert runs on the raw download, before the re-mux.

Every generator **merges** into `audio_manifest.json`, so any one can be rerun without clobbering the others' entries. All three are idempotent: rerunning produces sample-identical output (verified by decoded-PCM comparison). Two things that had to be fixed to make that true, and that a future edit could easily undo:

- `synth_feedback_sfx.py` re-seeds its RNG **per voice**, keyed on the asset id. A single shared generator makes every voice depend on how many voices were rendered before it, so merely *adding* a new sound silently re-rolls all the others — which broke `catch_epic`'s calibrated mix once.
- `prepare_catch_and_foley.py` regenerates the dry tension swell **in-process** rather than reading back `feedback/sfx_reel_tension.wav`, which it also writes. Reading its own output re-layered the creak and stretched the loop by 0.05 s on every run.

## Source Selection

The SFX + water-base files were prepared from free CC0 source packs, with gentle gain reduction and fades.
The seven biome ambience layers (`amb_*`) are built from real CC0 / public-domain recordings (see "How the
seven natural layers were made" above):

| Asset ID | Source File |
| --- | --- |
| `ui_click` | `E:\ai-audio\free-sfx\packs\opengameart_kenney_interface_sounds_cc0\Audio\click_001.ogg` |
| `ui_error` | `E:\ai-audio\free-sfx\packs\opengameart_kenney_interface_sounds_cc0\Audio\drop_001.ogg` |
| `cast` | `E:\ai-audio\free-sfx\packs\opengameart_202_more_sounds_cc0\Cloth\Cloth_05.wav` |
| `bobber_splash` | `E:\ai-audio\free-sfx\packs\opengameart_water_splash_slime_cc0\splash_09.ogg` |
| `bite` | `E:\ai-audio\free-sfx\packs\opengameart_water_splash_slime_cc0\bubble_02.ogg` |
| `catch_common` | `E:\ai-audio\free-sfx\packs\opengameart_water_splash_slime_cc0\splash_06.ogg` |
| `catch_rare` | `splash_01.ogg` plus `confirmation_001.ogg`, mixed softly |
| `coin` | `E:\ai-audio\free-sfx\packs\opengameart_202_more_sounds_cc0\Money\Money_07.wav` |
| `upgrade` | `E:\ai-audio\free-sfx\packs\opengameart_kenney_interface_sounds_cc0\Audio\confirmation_001.ogg` |
| `ambience_water_loop` | `E:\ai-audio\free-sfx\packs\opengameart_water_splash_slime_cc0\loop_water_03.ogg` |
| `amb_stream_loop` | Freesound #433589 'jackthemurray' stream-river-water-up-close (via Wikimedia Commons), CC0 |
| `amb_birds_day` | OpenGameArt "Ambient Bird Sounds" by isaiah658, CC0 |
| `amb_wind_loop` | OpenGameArt "wind1", CC0 |
| `amb_night_insects` | OpenGameArt "Crickets ambient noise (loopable)", CC0 |
| `amb_waves_loop` | OpenGameArt "Beach Ocean Waves" by jasinski (alkai beach), CC0 |
| `amb_gulls_day` | OpenGameArt "Solo Seagull Sound Effects" (Seagull Ambient), CC0 |
| `amb_cave_drip` | OpenGameArt "Dripping water loop" (atmosbasement), CC0 |
| `catch_good` | `splash_09.ogg` plus `confirmation_002.ogg` at -22 dB |
| `catch_epic` | `splash_01.ogg` + Commons "Bathtub water splashes" (PD) + synthesized `sfx_epic_tail` |
| `sfx_cat_steal` | Commons "Meow of a Siamese cat" by freemaster2 (CC0) + `splash_09.ogg` |
| `sfx_fish_struggle` | Commons "Bathtub water splashes" (PD), loudest 1.1 s window |
| `sfx_reel_tension` | synthesized swell + Commons "Assorted creaking noises of office chair" (PD) |
| `sfx_new_species`, `sfx_record`, `sfx_achievement`, `sfx_focus_reward`, `sfx_event_appear`, `sfx_competition_win`, `sfx_spot_unlock`, `sfx_epic_tail` | synthesized — `tools/synth_feedback_sfx.py`, no external source |
| `bgm_day` | OpenGameArt "First Light Particles" by Yoiyami, CC0 |
| `bgm_night` | OpenGameArt "Contemplation" by Joth, CC0 |

> **The `opengameart_kenney_interface_sounds_cc0` directory is misnamed.** Its contents come from
> **kenney.nl**, whose bundled `License.txt` states CC0 (committed as
> `assets/audio/licenses/kenney_interface_sounds_cc0_license.txt`). They are *not* from OpenGameArt's
> similarly-named ["Interface Sounds Starter Pack"](https://opengameart.org/content/interface-sounds-starter-pack),
> which is **CC-BY-SA 3.0 / GPL — not CC0** — and whose files aren't named `click_001.ogg` anyway.
> The directory name is kept only because the build scripts reference it. Don't "fix" the URL.

Full provenance for the foley and music, including the two sources that clip or overshoot at the
source and must not be re-normalised upward, is in `assets/audio/licenses/foley_and_music_sources.txt`.

Regenerate the SFX + water-base set with:

```powershell
python tools\prepare_free_sfx_assets.py
```

Regenerate the seven biome ambience layers with (fetch sources first, then build):

```powershell
python tools\fetch_ambience_sources.py
python tools\prepare_ambience_assets.py
```

> The old `E:\ai-audio\stable-audio-open\.venv\Scripts\python.exe` invocations these docs used to
> carry are gone — that virtualenv no longer exists on the machine. The scripts need only
> `numpy`, `scipy`, and `soundfile` on the system Python.

## Licensing Notes

Every shipping asset is CC0 or public domain. **Attribution is not required for anything.** That is a
deliberate constraint, not an accident: it keeps a Credits screen off the critical path to release.
Reject CC-BY sources even when they sound better — several were, during this work.

- Kenney Interface Sounds: CC0 (from **kenney.nl**, not OpenGameArt — see the warning above).
- OpenGameArt 40 water/splash/slime SFX: CC0.
- OpenGameArt 202 More Sound Effects: CC0.
- The seven `amb_*` biome layers are real recordings under CC0 / public domain.
- Foley (cat meow, thrashing water, creak): CC0 / public domain, all from Wikimedia Commons.
- `bgm_day` / `bgm_night`: CC0, from OpenGameArt.
- The eight synthesized voices have no source material and no licence at all.

Two known source defects, recorded so nobody "fixes" them by turning the gain up:
`cat_meow_siamese_cc0.wav` clips on ~0.05% of its samples (peak exactly 1.000), and
`line_creak_tension_pd.ogg` peaks at 1.011 from inter-sample overshoot on Vorbis decode. Both are
harmless once normalised down to their target peaks, which the build scripts do.

`sfx_reel_tension`'s creak layer is a **stand-in and flagged as one**: no CC0/PD recording of actual
fishing-line tension exists on OpenGameArt or Wikimedia Commons. It is an office chair.

Keep this file updated if any asset source changes.
