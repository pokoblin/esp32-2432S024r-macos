<p align="center"><img src="../images/icon.png" width="128" alt="Sysmon icon"></p>

# Sysmon : un écran d’état du Mac sur une ESP32-2432S024R

[English](../../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | **Français** | [Deutsch](README.de.md) | [Português (Brasil)](README.pt-BR.md) | [Русский](README.ru.md)

Transformez une ESP32-2432S024R (une carte avec écran ST7789 de 2,4", alias « Cheap Yellow Display ») en un petit écran d’état à côté de votre moniteur. D’un coup d’œil, vous voyez le processeur, la pression mémoire et le débit réseau, ce qu’il reste de vos limites d’abonnement Claude et ChatGPT, ainsi qu’un minuteur pomodoro qui vous rappelle de faire des pauses, de vous lever et de boire de l’eau.

L’app de barre des menus **Sysmon** échantillonne votre Mac toutes les 2 secondes et envoie les données à la carte par USB série ; la carte dessine les anneaux et les graphiques. Pas de Wi-Fi, et aucun port ouvert sur votre Mac.

![Écran Sysmon à côté d’un moniteur](../images/sysmon-preview.jpg)

<sub>Les illustrations sont dessinées d’après la mise en page et les couleurs réelles du firmware ; les données sont fictives.</sub>

> **Note sur les langues :** l’app Mac existe en 10 langues. La carte elle-même n’affiche pour l’instant que du texte chinois ; les images de ce README montrent une version anglaise des mêmes écrans.

## Écrans

Portrait 240×320, fond sombre. Quatre écrans : Système, Pomodoro, utilisation de Claude et utilisation de ChatGPT. Une bannière de rappel peut recouvrir n’importe lequel d’entre eux.

![Les quatre écrans](../images/screens.jpg)

### Système

- **En haut :** anneaux du processeur et de la pression mémoire. Le processeur passe au jaune à 50 % et au rouge à 80 %. L’anneau mémoire suit le niveau de pression mémoire de macOS (normal / avertissement / critique), exactement comme Moniteur d’activité.
- **En bas :** débits de téléchargement et d’envoi actuels, plus un graphique à deux couleurs des 5 dernières minutes. Le graphique s’adapte au pic de ces 5 minutes.

### Pomodoro

- Un grand anneau montre ce qu’il reste de la session en cours, avec le temps restant, la phase et l’heure de fin. La concentration est rouge tomate, la pause courte verte, la pause longue bleue ; en pause ou pas encore démarré, gris.
- En dessous : des points pour le cycle en cours (4 sessions de concentration par défaut), p. ex. « #2 · 2 more until long break » (n° 2 · encore 2 avant la pause longue), et le total du jour, p. ex. « 5 done · 2h 05m » (5 terminées · 2 h 05 min).
- Valeurs par défaut : 25 min de concentration, 5 min de pause courte, 15 min de pause longue après chaque 4e concentration. Tout est réglable ; les changements s’appliquent à partir de la prochaine session.
- Seule la concentration demande un démarrage manuel : une concentration terminée enchaîne directement sur une pause, et une pause terminée vous attend.
- Démarrez, mettez en pause et reprenez avec un seul raccourci global ou depuis le menu ; le menu propose aussi Passer et Réinitialiser le cycle. Passer une concentration l’abandonne, et elle n’est pas comptée.
- Le minuteur suit le temps réel : il continue de tourner quand vous êtes absent, que l’écran est verrouillé ou que le Mac est en veille. Le total du jour est remis à zéro à minuit et survit aux redémarrages.
- Pendant la concentration, les autres écrans affichent tout en haut une fine ligne de progression rouge tomate de 3 px (grise en pause).

### Utilisation de Claude et de ChatGPT

- Un grand anneau pour la limite de 5 heures avec le temps avant sa réinitialisation, et des barres pour la limite hebdomadaire (« This week · resets Thu 14:00 », cette semaine · réinitialisation jeu. à 14:00). Claude affiche aussi ses limites hebdomadaires par modèle lorsque l’API les fournit.
- Mêmes seuils de couleur que pour le processeur. Le pied d’écran indique l’offre (Max, Plus…) et la fraîcheur des données.
- Les données périmées sont toujours signalées : « Expired » (Expiré) quand la connexion a expiré, « Couldn’t read » (Lecture impossible) quand une requête a échoué, et « -- » quand une fenêtre a déjà été réinitialisée.

### Bannières de rappel

![Les quatre bannières de rappel](../images/banners.jpg)

Quel que soit l’écran affiché, une bannière prend toute la place et la lumière RGB au dos de la carte respire de la même couleur (vous pouvez éteindre la lumière). Touchez la carte ou appuyez sur le raccourci de changement d’écran pour la fermer.

| Bannière | Quand | Couleur | Disparaît d’elle-même |
|---|---|---|---|
| Concentration terminée | Une session de concentration se termine et la pause commence ; affiche le compte à rebours de la pause et les rappels retenus pendant la concentration | vert | à la fin de la pause |
| Fin de la pause | La pause se termine | rouge | quand vous lancez la concentration suivante |
| Levez-vous | 50 minutes d’utilisation réelle de l’ordinateur | orange | après 5 minutes d’absence |
| Buvez de l’eau | 60 minutes d’utilisation de l’ordinateur | bleu | non, touchez pour la fermer |

- « Utilisation de l’ordinateur » désigne une activité au clavier ou à la souris. Le temps d’inactivité et un écran verrouillé ou en veille s’additionnent en temps d’absence : 5 minutes d’absence remettent à zéro le minuteur pour se lever, 30 minutes celui pour boire.
- Aucune bannière pendant la concentration (y compris en pause) : elles sont retenues et regroupées dans la bannière « Concentration terminée ».
- Une seule bannière à la fois, dans l’ordre du tableau.

### Changer d’écran et éteindre

- Ordre : Système → Pomodoro → Claude → ChatGPT. Touchez n’importe où sur la carte ou appuyez sur le raccourci global. Pendant l’affichage d’une bannière, la même action la ferme à la place.
- Les écrans désactivés dans les Réglages sont ignorés. Les points de pagination en haut à droite indiquent où vous en êtes.
- L’écran et la lumière s’éteignent dès que l’affichage se met en veille, que l’écran se verrouille, que vous changez d’utilisateur ou que le Mac s’endort, et reviennent automatiquement. Environ 10 secondes après la fermeture de Sysmon ou le débranchement du câble, l’écran s’éteint.

## L’app de barre des menus

- L’icône est un module ESP32 ; elle est barrée tant qu’aucune carte n’est connectée.
- Le menu contient l’état de la connexion, les actions pomodoro pertinentes à cet instant, Réglages…, À propos de Sysmon et Quitter.
- Les Réglages comptent quatre onglets :
  - **Général :** le raccourci de changement d’écran, la lumière RGB, la langue de l’app (Langue du système ou l’une des 10 langues) et Ouvrir à l’ouverture de session.
  - **Pomodoro :** l’écran Pomodoro, le raccourci démarrer / pause, les durées et le nombre de sessions par cycle.
  - **Rappels :** les rappels pour se lever et pour boire, et leurs intervalles.
  - **Utilisation :** les écrans d’utilisation de Claude et de ChatGPT avec leur état, et l’origine des données.
- Les raccourcis globaux utilisent les touches rapides Carbon : aucune autorisation d’accessibilité n’est nécessaire. Pour savoir si vous êtes devant l’ordinateur, l’app lit le temps d’inactivité du système, ce qui ne demande aucune autorisation non plus.
- Elle trouve la carte grâce à l’identifiant fabricant USB de WCH (CH340) et se reconnecte après un rebranchement. Ouvrir ou fermer le port ne réinitialise jamais la carte.
- L’utilisation du processeur reste proche de 0 %.

<p align="center">
  <img src="../images/macos-settings-general.png" width="49%" alt="Settings: General">
  <img src="../images/macos-settings-pomodoro.png" width="49%" alt="Settings: Pomodoro">
</p>
<p align="center">
  <img src="../images/macos-settings-reminders.png" width="49%" alt="Settings: Reminders">
  <img src="../images/macos-settings-usage.png" width="49%" alt="Settings: Usage">
</p>

### D’où viennent les données d’utilisation

Sysmon emprunte, en lecture seule, les connexions déjà présentes sur votre Mac :

- **Claude :** les identifiants de Claude Code dans le trousseau de session (élément `Claude Code-credentials`, lu via `/usr/bin/security`, donc sans demande d’autorisation), envoyés au point d’accès d’utilisation d’Anthropic.
- **ChatGPT :** le fichier `~/.codex/auth.json` de Codex, envoyé au point d’accès d’utilisation de ChatGPT.

Sysmon ne renouvelle jamais ces connexions et n’écrit jamais dans le trousseau ni dans `auth.json` : il ne peut donc pas vous déconnecter. Le revers : si vous n’utilisez pas Claude Code ou Codex pendant un moment, la connexion expire et l’écran garde les derniers chiffres, marqués « Expiré ». Pour corriger, lancez `claude` une fois dans un terminal, ou ouvrez Codex une fois ; de nouveaux chiffres apparaissent en moins de 2 minutes. L’utilisation est récupérée toutes les 2 minutes, et pas quand l’écran est éteint.

Aucun des deux points d’accès n’est documenté, et l’un comme l’autre peut changer. Si l’un d’eux ne peut pas être interprété, seul cet écran affiche « Lecture impossible ».

## Prérequis

| Élément | Prérequis |
|---|---|
| Carte | ESP32-2432S024R (ESP32-D0WD-V3, 4 Mo de flash, ST7789 240×320, série CH340) |
| Mac | macOS 14 ou ultérieur |
| Chaîne d’outils du firmware | [PlatformIO](https://platformio.org/) |
| Chaîne d’outils du Mac | Xcode Command Line Tools (Swift 6) |

## Démarrage rapide

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. Flasher le firmware

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` utilise `/dev/cu.usbserial-114110` ; remplacez-le par votre port (`ls /dev/cu.usbserial-*`). Quittez Sysmon avant de flasher, sinon le port sera occupé.

> Via un hub USB, cette carte échoue au flashage à 921600 et 460800 ; `upload_speed` est donc fixé à 115200.

### 2. Installer l’app de barre des menus

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` compile une version release, crée `Sysmon.app`, la signe en ad hoc et l’installe dans `~/Applications`. Activez « Ouvrir à l’ouverture de session » dans les Réglages si vous le souhaitez.

## Développement

Lancer les tests :

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

Piloter la carte sans Sysmon (nécessite pyserial ; le Python de PlatformIO l’inclut déjà) :

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # sys / pomo / cl / gpt avec --page
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # fait défiler les écrans automatiquement
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

Les titres des bannières utilisent une minuscule police qui ne contient que les caractères nécessaires (le firmware occupe déjà plus de 90 % de sa flash). Après avoir modifié les titres dans `lib/sysmon_core/banner_titles.h`, régénérez-la ; la police est Source Han Sans CN Bold (SIL Open Font License 1.1) et doit être installée en local :

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

Les images du README sont générées par `docs/images/make_preview.py` et `docs/images/make_screens.py` ; les commandes figurent dans l’en-tête de chaque script.

### Protocole série

115200 8N1, texte brut, un enregistrement par ligne :

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| Champ | Signification |
|---|---|
| `cpu` | utilisation du processeur, 0–100 |
| `mem` | pourcentage de pression mémoire, 0–100 |
| `lvl` | niveau de pression mémoire : 1 normal, 2 avertissement, 4 critique |
| `rx` / `tx` | débit de téléchargement / d’envoi, en octets par seconde |
| `OFF` | éteint l’écran jusqu’à la prochaine ligne `S` |

Le firmware ignore les lignes et les champs inconnus. Les pages, l’utilisation, le pomodoro et les bannières utilisent les lignes `P`, `U`, `T` et `B`, et la carte envoie `TAP` quand on la touche : voir les commentaires d’en-tête de `usage_protocol.h`, `timer_protocol.h` et `Protocol.swift`.

## Structure du dépôt

```
sysmon/
  firmware/            ESP32 firmware (PlatformIO + Arduino + LovyanGFX)
    lib/sysmon_core/   pure logic: protocol parsing, screen-off state, chart history, copy, tap debounce, colors, breathing curve
    src/               display config, drawing, RGB light, generated banner font, main loop
    test/              unit tests that run on the computer
  macos/               menu bar app (SwiftPM)
    Sources/SysmonCore/  CPU/memory/network sampling, serial, device discovery, usage credentials and parsing,
                         page order, pomodoro and reminder rules, localization
    Sources/Sysmon/      SwiftUI menu bar UI, Settings, About, global shortcuts
    scripts/bundle.sh    build and install the .app
    scripts/make_icon.sh     compiles the app icon from AppIcon.icon (Icon Composer)
  tools/fake_feed.py   fake data for the board, no Mac app needed
  tools/make_banner_font.swift  generates the banner title font
hw_probe/              hardware probe firmware: display driver, touch chip and pins
touch_diag/            raw XPT2046 touch diagnostics
touch_test/            touch calibration and drawing test; board.h is the verified display config
docs/images/           README pictures and their generators
docs/readme/           translated READMEs
```

## Notes sur le matériel

- Le contrôleur d’affichage est un **ST7789**, pas un ILI9341. Avec `Panel_ILI9341`, l’image sort transposée et en miroir.
- Réglages LovyanGFX : `rgb_order=false` (à true, le rouge et le bleu sont échangés), `invert=false`, rotation 0.
- Rétroéclairage sur GPIO27, actif à l’état haut. Le MISO de l’écran n’est pas connecté, son identifiant ne peut donc pas être lu.
- La LED RGB au dos est à anode commune, active à l’état bas : GPIO4 rouge, GPIO16 bleu, GPIO17 vert (le bleu et le vert sont inversés par rapport à ce que disent la plupart des notes sur la CYD).
- Le CH340 pilote EN et GPIO0 via DTR/RTS. Sysmon les relâche tous les deux juste après l’ouverture du port et désactive `HUPCL` : ouvrir ou fermer le port ne réinitialise donc jamais la carte.
