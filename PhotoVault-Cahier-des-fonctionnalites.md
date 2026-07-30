# PhotoVault
### Clone SwiftUI d'Immich — Cahier des fonctionnalités
*Expérience native Apple — iOS / iPadOS*

Version 1.0 — Juillet 2026

---

## Sommaire

0. [Vision produit](#0-vision-produit)
1. [Authentification & connexion au serveur](#1-authentification--connexion-au-serveur)
2. [Sauvegarde & synchronisation](#2-sauvegarde--synchronisation)
3. [Bibliothèque & navigation](#3-bibliothèque--navigation)
4. [Visionneuse & détail d'un média](#4-visionneuse--détail-dun-média)
5. [Édition non destructive](#5-édition-non-destructive)
6. [Recherche & intelligence artificielle](#6-recherche--intelligence-artificielle)
7. [Carte](#7-carte)
8. [Albums & partage](#8-albums--partage)
9. [Intégration système iOS](#9-intégration-système-ios)
10. [Réglages & administration compte](#10-réglages--administration-compte)
11. [Feuille de route synthétique](#11-feuille-de-route-synthétique)
12. [Notes techniques transverses](#12-notes-techniques-transverses)

---

## 0. Vision produit

PhotoVault est un client iOS natif pour un serveur Immich, pensé comme si Apple l'avait conçu en interne. L'objectif n'est pas de reproduire l'UI web d'Immich, mais d'offrir les mêmes capacités via les patterns d'interface, de gestes et d'animation propres à iOS — à la manière de l'app Photos native.

> **Principe directeur** : si une fonctionnalité existe déjà dans Photos.app ou dans les guidelines Apple, on adopte le même vocabulaire d'interaction plutôt que d'inventer le sien.

### 0.1 Piliers d'expérience "Apple-like"

- SF Symbols partout, jamais d'icônes custom quand un symbole système convient
- Typographie : SF Pro / New York via Dynamic Type, respect des tailles d'accessibilité
- Navigation : `NavigationStack`, swipe-back natif, pas de gestes custom qui cassent les réflexes iOS
- Animations : spring animations natives (`.animation(.spring)`), pas d'easing linéaire
- Haptics : `UIFeedbackGenerator` sur les actions clés (like, suppression, sélection multiple)
- Grilles photo : layout identique à Photos.app (zoom pinch pour changer la densité de grille)
- Mode sombre first-class, pas un simple recolorage
- Widgets, Live Activities et Shortcuts comme citoyens de première classe, pas des ajouts tardifs
- Confidentialité visible : Face ID/Touch ID pour déverrouiller l'app ou un album, comme Photos
- Support iPad natif : sidebar, multi-colonnes, drag & drop, pas un iPhone agrandi

### 0.2 Légende des priorités

| Tag | Signification |
|---|---|
| **MVP** | Nécessaire pour une v1 utilisable au quotidien |
| **V2** | Complète l'expérience, à faire une fois le socle stable |
| **V3** | Fonctionnalités avancées / différenciantes, non bloquantes |

---

## 1. Authentification & connexion au serveur

Contrairement à Immich (self-hosted par définition), cet écran doit rester simple et rassurant même si l'utilisateur configure un serveur perso pour la première fois.

- Connexion à un serveur Immich existant (URL + email/mot de passe) — **MVP**
- Support OAuth / connexion via clé API pour les serveurs qui l'exposent — **V2**
- Détection automatique et test de connexion au serveur (feedback en temps réel, style Apple ID) — **MVP**
- Stockage sécurisé des identifiants dans le Keychain iOS — **MVP**
- Déverrouillage de l'app par Face ID / Touch ID (App Lock) — **MVP**
- Multi-comptes / bascule rapide entre plusieurs serveurs — **V3**
- Écran d'onboarding façon "Bonjour" (Hello screen) au premier lancement — **MVP**

---

## 2. Sauvegarde & synchronisation

Le cœur de l'app : une synchro invisible et fiable, sur le modèle du Volet Photos iCloud.

- Sauvegarde automatique en arrière-plan (`BackgroundTasks` / `BGProcessingTask`) — **MVP**
- Sélection fine des albums locaux à synchroniser — **MVP**
- Support HEIC/HEIF et vidéos HEVC natif (pas de conversion inutile) — **MVP**
- Barre de progression globale avec statut par étape (façon transfert AirDrop) — **MVP**
- Alerte proactive si Faible consommation d'énergie / Actualisation en arrière-plan désactivée empêche la sauvegarde — **MVP**
- Upload en parallèle dès le réveil de l'app (background refresh) pour maximiser la fenêtre système iOS — **V2**
- Sauvegarde Wi-Fi uniquement (option, comme Photos iCloud) — **MVP**
- Reprise automatique après interruption (perte réseau, app tuée) — **MVP**
- Indicateur par miniature : sauvegardé / en attente / erreur (petit badge discret) — **V2**
- Synchronisation multi-appareils en temps réel (WebSocket) — un ajout depuis un autre device apparaît en live — **V2**

---

## 3. Bibliothèque & navigation

- Timeline principale par date de capture, scroll infini avec chargement paresseux (100k+ assets fluides) — **MVP**
- Grille pinch-to-zoom pour changer la densité (1 à 8 colonnes, comme Photos.app) — **MVP**
- Scrubber latéral avec aperçu de date au survol (drag scroll bar) — **MVP**
- En-têtes de section collants (jour / mois / année) style Photos — **MVP**
- Onglet "Ajouts récents" trié par date d'import plutôt que date de capture — **V2**
- Vue "Souvenirs" façon Photos (retour sur cette date les années précédentes) — **V2**
- Vue Jours / Mois / Années avec transitions de zoom fluides (pinch pour changer d'échelle temporelle) — **V2**
- Extension système : ouvrir l'app comme visionneuse depuis d'autres apps (Document Interaction / share sheet) — **V2**
- Bibliothèques externes : indexer un dossier serveur existant sans dupliquer les fichiers — **V3**
- Corbeille avec suppression différée (30 jours, comme Photos) — **MVP**
- Éléments masqués (protégés par Face ID) séparés de la corbeille — **V2**

---

## 4. Visionneuse & détail d'un média

- Visionneuse plein écran avec swipe horizontal fluide et zoom pinch natif — **MVP**
- Lecture vidéo native (`AVPlayer`), scrubbing, picture-in-picture — **MVP**
- Panneau Infos (façon "i" de Photos) : EXIF complet (objectif, focale, ISO, appareil), lieu, taille fichier — **MVP**
- Carte miniature intégrée si géolocalisé, avec lieu nommé (reverse geocoding) — **MVP**
- Slideshow plein écran, transitions douces, musique optionnelle — **V2**
- Lecture Live Photo (appui long) si l'asset le supporte — **V2**
- Transcodage à la volée (HLS) pour vidéos volumineuses non pré-transcodées côté serveur — **V3**
- Reconnaissance de texte dans l'image (Live Text natif via VisionKit) — **V2**
- Partage natif (`ShareLink` / `UIActivityViewController`) — **MVP**

---

## 5. Édition non destructive

Pas d'accès direct à l'éditeur natif de Photos.app (aucune API publique ne l'expose). L'éditeur doit être reconstruit avec Core Image, mais avec l'exigence de fluidité et de réversibilité de Photos.

- Recadrage avec grille des tiers, rotation libre au doigt, redressement automatique de l'horizon — **MVP**
- Ratios prédéfinis (carré, 16:9, 4:3...) façon éditeur Photos — **MVP**
- Ajustements lumière/couleur via Core Image (`CIFilter`) : exposition, contraste, saturation, chaleur — **MVP**
- Filtres prédéfinis avec aperçu en temps réel (miniatures façon Photos) — **V2**
- Historique d'édition non destructif stocké en JSON (crop rect, angle, filtres) — jamais de ré-encodage tant que non exporté — **MVP**
- Bouton "Revenir à l'original" à tout moment — **MVP**
- Retouche locale au pinceau (masquage de zone) via Core Image + Metal — **V3**
- Édition synchronisée avec le serveur (les ajustements suivent l'asset sur tous les appareils) — **V2**

---

## 6. Recherche & intelligence artificielle

- Recherche par texte libre sur EXIF (objectif, modèle d'appareil, orientation) — **MVP**
- Recherche sémantique ("chien sur une plage") via l'API ML du serveur Immich — **MVP**
- Reconnaissance faciale : regroupement automatique par visage, nommage manuel — **MVP**
- Détection d'objets et classification de scènes, tags cliquables — **MVP**
- Page de recherche avec suggestions visuelles (lieux, objets, personnes en avant), façon onglet Rechercher de Photos — **V2**
- Recherche vocale (Siri / dictée native) — **V2**
- Filtres combinés (personne + lieu + date) avec chips visuelles — **V2**
- Recherche par couleur dominante — **V3**

---

## 7. Carte

- Vue carte (MapKit natif) avec clusters de photos géolocalisées — **MVP**
- Appui sur un cluster → mini-grille des photos du lieu — **MVP**
- Lieux mis en avant (curated places), façon onglet Lieux de Photos — **V2**
- Mode voyage : regroupement automatique par déplacement géographique + temporel — **V3**

---

## 8. Albums & partage

- Création d'albums, ajout par sélection multiple (long press + drag pour sélection rapide) — **MVP**
- Albums partagés collaboratifs entre utilisateurs du même serveur — **MVP**
- Partage via lien public, avec protection par mot de passe optionnelle — **MVP**
- Partage "Partenaire" : accès total à la bibliothèque d'un proche sans duplication de stockage — **V2**
- Albums intelligents / dynamiques (règles automatiques : personne X, lieu Y) — **V3**
- Drag & drop d'assets entre albums (particulièrement sur iPad) — **V2**
- Widget iOS "Album partagé" sur l'écran d'accueil — **V3**

---

## 9. Intégration système iOS

- Widgets Écran d'accueil / Verrouillé (photo du jour, souvenir, statut de sauvegarde) — **V2**
- Live Activity pendant un import massif (progression en Dynamic Island) — **V2**
- Raccourcis Siri / App Intents ("Sauvegarder mes photos maintenant", "Montre-moi mes souvenirs") — **V2**
- Notifications push : fin de sauvegarde, nouveau partage reçu, visage à confirmer — **MVP**
- Partage système (share extension) pour importer depuis n'importe quelle app — **MVP**
- Handoff entre iPhone et iPad — **V3**
- Prise en charge clavier + trackpad sur iPad (raccourcis façon Photos macOS/iPadOS) — **V2**

---

## 10. Réglages & administration compte

- Gestion du serveur (URL, déconnexion, changement de compte) — **MVP**
- Gestion du cache local (taille utilisée, vider le cache) — **MVP**
- Réglages de qualité d'upload (originale / optimisée) — **MVP**
- Gestion des utilisateurs et quotas (vue admin, si le compte a les droits) — **V3**
- Automatisations ("Workflows") : déclencheurs/filtres/actions déportés vers le serveur, simple UI de consultation côté app — **V3**
- Export / téléchargement en masse vers la pellicule locale — **MVP**
- Mode invité limité (lecture seule, pas de configuration serveur visible) — **V3**

---

## 11. Feuille de route synthétique

### Phase 1 — MVP (socle utilisable au quotidien)
- Connexion serveur + App Lock
- Sauvegarde automatique fiable en arrière-plan
- Timeline + visionneuse + infos EXIF
- Recherche sémantique et visages (consommation API, pas de ML on-device)
- Albums de base + partage par lien
- Édition non destructive : crop, rotation, ajustements simples

### Phase 2 — Expérience complète
- Widgets, Live Activities, Raccourcis Siri
- Souvenirs, vue carte enrichie, filtres avancés
- Synchronisation temps réel multi-appareils
- Partage partenaire, drag & drop iPad

### Phase 3 — Différenciation
- Retouche locale avancée (masquage, pinceau)
- Albums intelligents, mode voyage
- Administration serveur complète depuis l'app

---

## 12. Notes techniques transverses

| Domaine | Recommandation |
|---|---|
| Réseau | `URLSession` + Swift Concurrency (async/await), WebSocket via `URLSessionWebSocketTask` pour le temps réel |
| Persistance locale | SwiftData (ou Core Data) pour le cache métadonnées, `FileManager` pour le cache miniatures |
| Tâches de fond | `BGTaskScheduler` pour les uploads différés |
| Rendu image | Core Image / Metal pour l'éditeur, `AsyncImage` custom avec cache disque pour la grille |
| Sécurité | Keychain pour les tokens, `LocalAuthentication` pour Face ID/Touch ID |
| Cartes | MapKit natif (pas de dépendance tierce) pour rester cohérent avec le reste du système |
| Cible | iOS 17+ pour bénéficier de SwiftData, `Observable`, et des dernières APIs App Intents |
