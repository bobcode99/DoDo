# Deprecated features

Things this app used to do, and no longer does. Here so a removed feature does
not get rebuilt from the same idea a year later.

---

## For You (on-device episode recommendations) — removed 2026-08-23

**What it was.** A Home section that asked Apple's on-device model to pick 3–5
episodes from the user's subscriptions, based on listening history, with a short
reason under each pick. Gated on Apple Intelligence, toggleable in Settings →
Appearance, cached in `UserDefaults` against a signature of its inputs.

**Why it went.** The suggestions were not good enough to earn the space. The
model saw only titles and truncated descriptions — never transcripts, which do
not fit in a ~4096-token context — so it was pattern-matching on wording, and the
reasons it gave read as plausible rather than true. A recommender that is wrong
often enough to be ignored is worse than no recommender: it trains the user to
skip past the top of Home.

**What was removed.**

| Deleted | |
|---|---|
| `Views/ForYouRow.swift` | the row |
| `Views/Home/ForYouSection.swift` | iOS section |
| `Models/RecommendedEpisode.swift` | `RecommendedEpisode`, `RecommendationFailure` |
| `Services/AppleFoundationModelsService.swift` | the actor and its prompt |
| `EpisodeRecommendations` | the `@Generable` output type |
| `HomeViewModel` | recommendation state, disk cache, candidate pool, `loadRecommendations()` |
| `SettingsViewModel` | the `showForYouRecommendations` toggle and its notification |
| `.forYouSettingChanged` | the notification name |

**What stayed.** `FoundationModelsAvailability` (moved to its own file). It is
what Settings → AI reads to report whether Apple Intelligence is usable on this
device, and is unrelated to recommendations.

**If it is ever revisited.** The problem was input quality, not plumbing. Titles
and blurbs are not enough signal. It would need transcripts — which means the
cloud path, the user's own API key, and a real cost per refresh — and that is a
different feature with a different trade-off, not this one tuned.
