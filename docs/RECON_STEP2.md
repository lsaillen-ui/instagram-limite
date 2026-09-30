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

## Avant de coller le log

1. Copie **toute** la console Xcode (clic dans la console, Cmd+A, Cmd+C).
2. **Relis-la avant de la coller** et supprime tout ce qui est personnel et que la redaction a manqué. Les `aria-label` peuvent contenir des noms (par exemple le nom d'un contact ou « Photo de profil de … »). Remplace-les par `XXX`.
3. Colle le log dans la conversation avec Claude Code.

## Findings

_To be filled in Phase B (B0), from the pasted log._
