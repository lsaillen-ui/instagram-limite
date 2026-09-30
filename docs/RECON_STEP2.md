# Step 2 — Recon guide

Goal: observe how the real mobile site behaves (does a reel open as a page or as an overlay, which URLs do stories use, which DOM anchors exist) so that the route policy and the CSS rules of Phase B are based on facts, not guesses.

Everything here is DEBUG only: the recon script, the log lines and the **Mark** button are not compiled into Release builds.

## What the tooling prints

In the Xcode console, on every route change and on every Mark tap:

- `[FocusBrowser] route: <kind> <path>`: `kind` is `push`, `replace`, `pop` or `initial`.
- `[FocusRecon] <kind> <path> <json>`: a DOM snapshot taken 1.5 s after the route change (`mark` for a Mark tap): links, aria-labels, dialogs, scroll containers, videos.
- `[FocusRecon] ---- MARK n ----`: the separator printed by the Mark button.
- `[FocusBrowser] decidePolicyFor …`: full-page navigations and the verdict of the navigation hygiene.

Usernames, thread ids, reel ids and post ids are replaced by short tokens (`#3fa1`). A token is stable during one app session, so "reel A then reel B" stays visible, but it changes on the next launch.

## Scénario (à suivre sur ton iPhone, connecté)

Prépare-toi : branche l'iPhone, lance l'app depuis Xcode (Run, build Debug) et garde la console Xcode ouverte. Le bouton orange **Mark** flotte au-dessus de la page ; tu peux le faire glisser pour qu'il ne gêne pas.

**Avant chaque étape numérotée, appuie sur Mark.** Ça sépare les étapes dans le log.

1. Lance l'app (boîte de réception).
2. Ouvre une conversation.
3. Touche un reel reçu dans cette conversation. Attends 3 s.
4. Balaye vers le haut une fois sur ce reel. Attends 3 s.
5. Reviens à la conversation (avec le contrôle de retour que la page propose).
6. Touche un post (`/p/`) reçu en message, s'il y en a un. Reviens.
7. Ouvre le profil du contact depuis la conversation. Ouvre son onglet Reels. Touche un reel. Balaye vers le haut une fois. Reviens deux fois en arrière.
8. Ouvre un profil qui a une story active, touche l'avatar, et laisse la story défiler jusqu'à la story de la personne suivante. Ferme-la.
9. Touche chaque icône de la barre de navigation du site, une par une : Accueil, Explorer/Recherche, Reels. Reviens aux messages entre chaque.
10. Ouvre le champ de recherche, s'il y en a un.

## Ronde 2 (ce qui manquait à la ronde 1)

Même méthode : **Mark avant chaque étape**, puis copie toute la console. Cette fois le log est bien plus court : ne fais que ces étapes. Les noms d'utilisateur des `aria-label` sont maintenant masqués par l'outil, mais relis quand même avant de coller.

Pour chaque balayage, attends 2 s, puis appuie sur Mark **avant et après** le balayage. Le snapshot indique maintenant la position de défilement (`scrollTop`) et quelle vidéo est à l'écran (`inView`), ce qui montre si le balayage a avancé.

A. **Reel reçu en message (overlay).** Ouvre une conversation, touche un reel reçu. Mark. Balaie vers le haut une fois. Mark. Balaie encore une fois. Mark. Ferme avec la croix du reel. Mark.
B. **Reel depuis un profil (page).** Ouvre un profil, onglet Reels, touche un reel. Mark. Balaie vers le haut une fois. Mark. Reviens en arrière. Mark.
C. **Stories.** Ouvre une story depuis un avatar (accueil ou profil). Mark. Laisse-la avancer jusqu'à la story de la personne suivante (ou touche pour avancer). Mark. Ferme. Mark. Si une conversation contient une story reçue, touche-la aussi. Mark.
D. **Reels dans la barre du bas.** Depuis une page avec la barre du bas (un profil par exemple), touche l'icône Reels. Mark. Balaie vers le haut une fois. Mark. Reviens aux messages.
E. **Flèche Retour de la boîte de réception.** Dans la boîte de réception, touche la flèche Retour en haut à gauche. Mark. Reviens aux messages.

## Avant de coller le log

1. Copie **toute** la console Xcode (clic dans la console, Cmd+A, Cmd+C).
2. **Relis-la avant de la coller** et supprime tout ce qui est personnel et que la redaction a manqué. Les `aria-label` peuvent contenir des noms (par exemple le nom d'un contact ou « Photo de profil de … »). Remplace-les par `XXX`.
3. Colle le log dans la conversation avec Claude Code.

## Findings

Round 1, logged in, iPhone 13, iOS 27.0.1. Redacted: only tokens, never names. The log was **incomplete**: steps 4 (partly), 7 (swipe), 8 (stories) and the Reels icon of step 9 were not captured, see "Not observed".

### Route events by scenario

| What the user did | Events | Notes |
|---|---|---|
| Cold launch, logged in | `replace /direct/inbox/` ×2, then `initial /direct/inbox/` | The site calls `replaceState` twice on load. |
| Inbox → conversation | `push /direct/t/{id}/` | |
| Conversation → inbox (page's Back arrow) | `push /direct/inbox/` | The Back arrow is a **push**, not a history traversal: `history.length` keeps growing. |
| Conversation → shared post | `push /p/{id}/` | Opens as a page. |
| Post → back | `pop /direct/t/{id}/` | Here the back control is a real `pop`. |
| Conversation → contact profile | `push /{user}/` | |
| Profile → back | `pop /direct/t/{id}/` | |
| Inbox → home feed `/` | `push /` | Reached from the inbox with no bottom bar there, so most likely the header Back arrow (the log does not say which control). |
| Home → Explore | `push /explore/` immediately followed by `push /explore/search/` | Explore opens straight in search mode (keyboard up). |
| Search result → profile | `push /{user}/` | |
| Profile → Reels tab | `push /{user}/reels/` | |
| Reels tile → reel | `push /{user}/reel/{id}/` | **Not** `/reel/{id}/`. The user segment can differ from the profile being browsed. The reel id equals the id in `/p/{id}/comments/` on the same page. |

### Contradiction with the policy table: reels received in a DM open as an overlay

Tapping a reel in a conversation produced **no route event at all**. The path stays `/direct/t/{id}/`, `history.length` is unchanged, and there is no `role=dialog` (dialog count is 0 on every page of the log).

While the overlay is open the snapshot shows:
- one scroller (`div`, depth 19, 390×693, `scrollHeight` 6299) containing **9 `video` elements** (1 playing): the tapped reel followed by about 8 reels from unrelated authors. This is the infinite reels feed, and it is invisible to the route layer;
- controls labelled Close, Toggle audio / Audio is muted, Like, Comment, Repost, Share, More, Press to play, Choose an emoji;
- links to `/{user}/reels/` (one per slide), `/reels/audio/{id}/`, `/explore/tags/{id}/`, `/explore/locations/{id}/`.

After the swipe (MARK 6) the snapshot is almost identical and there is still no route event. The recon did not capture `scrollTop`, so it does not show whether the swipe moved to the next reel. After Close (MARK 7) the overlay is gone (0 videos, only the conversation scroller remains).

Consequence: the "reel → another reel = `goBack`" rule cannot apply to DM reels, because nothing in the URL changes. Blocking the feed there needs the behavior layer (scroll lock on that container, detected from the DOM).

### Stable anchors found

- **Bottom bar** (home, post, profile, reel, explore pages; absent on the inbox and conversation pages): `a[href="/"]`, `a[href="/explore/"]`, `a[href="/reels/"]`, `a[href="/direct/inbox/"]` and an unlabeled `a[href="/{own user}/"]`. Each contains an `svg[aria-label]` (Home, Explore, Reels, Messages). **None of them is inside `nav` or `[role=navigation]`**, so the `nav` anchor is unusable: `a[href]` is the anchor to use.
- **Inbox header**: `a[href="/direct/new/"]` (label New message, inside `nav`), plus `svg` labelled Back, Search and Down Chevron Icon.
- **Scrollers**: inbox `div` depth 16; conversation `div` depth 18; home, post, profile, reels tab and reel pages scroll the document (`html`). None has a role or aria-label.
- **Videos**: on the reel page (`/{user}/reel/{id}/`) there is 1 `video`, not playing (autoplay is off as configured), and no other slides in the DOM.
- **Story links**: `/stories/{user}/{id}/?…` appears in a conversation (a story mention or reply), and `/stories/highlights/{id}/` on profiles. A story was never opened in this round.

### Not observed (needs a second round)

1. Swipe up on the DM overlay: does it advance, and does the URL or `history.length` ever change?
2. Swipe up on a page reel `/{user}/reel/{id}/`: does it navigate to another reel (route change) or scroll inside the page?
3. Stories: URL shape when opened, and the advance to the next person's story.
4. The Reels bottom-bar icon (`/reels/`) and how the feed behaves.
5. Which control brought the user from the inbox to `/`.
6. The DOM ancestors of the DM overlay scroller (needed to find an anchor other than "a `div` at depth 19 that contains videos").

### Privacy note on the recon logs

`aria-label`s carry usernames (profile links, "React to message from …", "Story by …", "… reels", highlight titles). `PathRedactor` cannot catch those. Round 2 masks them in `recon.js`, but every log must still be skimmed before it is shared.
