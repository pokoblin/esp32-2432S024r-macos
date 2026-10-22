<p align="center"><img src="../images/icon.png" width="128" alt="Sysmon icon"></p>

# Sysmon: ein Mac-Statusbildschirm auf einem ESP32-2432S024R

[English](../../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | **Deutsch** | [Português (Brasil)](README.pt-BR.md) | [Русский](README.ru.md)

Verwandle einen ESP32-2432S024R (ein 2,4"-ST7789-Board, auch bekannt als „Cheap Yellow Display“) in einen kleinen Statusbildschirm neben deinem Monitor. Auf einen Blick siehst du CPU, Speicherdruck und Netzwerkgeschwindigkeit, wie viel von deinen Claude- und ChatGPT-Abo-Limits noch übrig ist, und einen Pomodoro-Timer, der dich an Pausen, ans Aufstehen und ans Trinken erinnert.

Die Menüleisten-App **Sysmon** misst alle 2 Sekunden die Werte deines Macs und schickt sie per USB-Seriell an das Board; das Board zeichnet die Ringe und Diagramme. Kein WLAN, und auf deinem Mac werden keine Ports geöffnet.

![Sysmon-Bildschirm neben einem Monitor](../images/sysmon-preview.jpg)

<sub>Die Abbildungen sind nach dem tatsächlichen Layout und den Farben der Firmware gezeichnet; die Daten sind erfunden.</sub>

> **Sprachhinweis:** Die Mac-App gibt es in 10 Sprachen. Das Board selbst zeigt derzeit nur chinesischen Text; die Bilder in dieser README zeigen eine englische Fassung derselben Bildschirme.

## Bildschirme

Hochformat 240×320, dunkler Hintergrund. Vier Bildschirme: System, Pomodoro, Claude-Nutzung und ChatGPT-Nutzung. Ein Erinnerungsbanner kann jeden davon überdecken.

![Die vier Bildschirme](../images/screens.jpg)

### System

- **Oben:** Ringe für CPU und Speicherdruck. Die CPU wird ab 50 % gelb und ab 80 % rot. Der Speicherring folgt dem Speicherdruck-Level von macOS (normal / Warnung / kritisch), genau wie in der Aktivitätsanzeige.
- **Unten:** aktuelle Download- und Upload-Geschwindigkeit sowie ein zweifarbiges Diagramm der letzten 5 Minuten. Das Diagramm skaliert auf den Spitzenwert der 5 Minuten.

### Pomodoro

- Ein großer Ring zeigt, wie viel von der aktuellen Einheit noch übrig ist, mit der Restzeit, der Phase und dem Ende. Fokus ist tomatenrot, kurze Pause grün, lange Pause blau; pausiert oder nicht gestartet ist grau.
- Darunter: Punkte für die aktuelle Runde (standardmäßig 4 Fokus-Einheiten), z. B. „#2 · 2 more until long break“ (noch 2 bis zur langen Pause), und die Tagesbilanz, z. B. „5 done · 2h 05m“ (5 erledigt · 2 Std. 05 Min.).
- Standardwerte: 25 Min. Fokus, 5 Min. kurze Pause, 15 Min. lange Pause nach jedem 4. Fokus. Alles einstellbar; Änderungen gelten ab der nächsten Einheit.
- Nur der Fokus muss von Hand gestartet werden: Ein beendeter Fokus geht direkt in eine Pause über, und nach einer beendeten Pause wird auf dich gewartet.
- Starten, Pausieren und Fortsetzen geht mit einem globalen Tastenkürzel oder über das Menü; das Menü bietet außerdem „Überspringen“ und „Runde zurücksetzen“. Überspringt man einen Fokus, wird er abgebrochen und nicht gezählt.
- Der Timer läuft in Echtzeit und läuft deshalb weiter, wenn du weg bist, der Bildschirm gesperrt ist oder der Mac schläft. Die Tagesbilanz wird um Mitternacht zurückgesetzt und übersteht Neustarts.
- Solange du im Fokus bist, zeigen die anderen Bildschirme ganz oben eine dünne, 3 px hohe tomatenrote Fortschrittslinie (grau, solange pausiert).

### Claude- und ChatGPT-Nutzung

- Ein großer Ring für das 5-Stunden-Limit mit der Zeit bis zum Zurücksetzen und Balken für das Wochenlimit („This week · resets Thu 14:00“, also: Diese Woche · Reset Do 14:00). Claude zeigt auch die Wochenlimits pro Modell, wenn die API sie meldet.
- Dieselben Farbschwellen wie bei der CPU. Die Fußzeile zeigt den Tarif (Max, Plus …) und wie aktuell die Daten sind.
- Veraltete Daten sind immer markiert: „Abgelaufen“, wenn die Anmeldung abgelaufen ist, „Lesen fehlgeschlagen“, wenn eine Anfrage fehlgeschlagen ist, und „--“, wenn ein Zeitfenster bereits zurückgesetzt wurde.

### Erinnerungsbanner

![Die vier Erinnerungsbanner](../images/banners.jpg)

Egal, auf welchem Bildschirm du bist: Ein Banner übernimmt den ganzen Bildschirm, und das RGB-Licht auf der Rückseite des Boards pulsiert in derselben Farbe (das Licht lässt sich ausschalten). Tippe auf das Board oder drücke das Tastenkürzel zum Bildschirmwechsel, um das Banner zu schließen.

| Banner | Wann | Farbe | Verschwindet von selbst |
|---|---|---|---|
| Fokus beendet (*Focus done*) | Eine Fokus-Einheit endet und die Pause beginnt; zeigt den Pausen-Countdown und alle während des Fokus zurückgehaltenen Erinnerungen | grün | wenn die Pause endet |
| Pause vorbei (*Break over*) | Die Pause endet | rot | wenn du den nächsten Fokus startest |
| Aufstehen (*Stand up*) | 50 Minuten tatsächliche Computernutzung | orange | nach 5 Minuten Abwesenheit |
| Wasser trinken (*Drink water*) | 60 Minuten Computernutzung | blau | nein, zum Schließen tippen |

- „Computernutzung“ bedeutet Tastatur- oder Mausaktivität. Leerlauf sowie ein gesperrter oder schlafender Bildschirm zählen als Abwesenheit: 5 Minuten Abwesenheit setzen den Aufsteh-Timer zurück, 30 Minuten den Wasser-Timer.
- Keine Banner während des Fokus (auch nicht bei Pause): Sie werden zurückgehalten und in das Banner „Fokus beendet“ übernommen.
- Immer nur ein Banner gleichzeitig, in der Reihenfolge der Tabelle.

### Bildschirme wechseln und ausschalten

- Reihenfolge: System → Pomodoro → Claude → ChatGPT. Tippe irgendwo auf das Board oder drücke das globale Tastenkürzel. Solange ein Banner angezeigt wird, schließt dieselbe Aktion stattdessen das Banner.
- In den Einstellungen ausgeschaltete Bildschirme werden übersprungen. Die Seitenpunkte oben rechts zeigen, wo du gerade bist.
- Bildschirm und Licht gehen aus, sobald das Display schlafen geht, der Bildschirm gesperrt wird, du den Benutzer wechselst oder der Mac in den Ruhezustand geht, und kommen automatisch wieder. Etwa 10 Sekunden nachdem Sysmon beendet oder das Kabel abgezogen wurde, schaltet sich der Bildschirm aus.

## Die Menüleisten-App

- Das Symbol ist ein ESP32-Modul; solange kein Board verbunden ist, ist es durchgestrichen.
- Das Menü zeigt den Verbindungsstatus, die gerade sinnvollen Pomodoro-Aktionen, Einstellungen, „Über Sysmon“ und „Beenden“.
- Die Einstellungen haben vier Tabs:
  - **Allgemein:** das Tastenkürzel zum Bildschirmwechsel, das RGB-Licht, die App-Sprache („Wie System“ oder eine von 10 Sprachen) und „Bei der Anmeldung starten“.
  - **Pomodoro:** der Pomodoro-Bildschirm, das Start/Pause-Tastenkürzel, Dauer und Einheiten pro Runde.
  - **Erinnerungen:** Aufsteh- und Trink-Erinnerungen und ihre Intervalle.
  - **Nutzung:** die Nutzungsbildschirme von Claude und ChatGPT mit ihrem Status und woher die Daten kommen.
- Globale Tastenkürzel nutzen Carbon-Hotkeys, daher ist keine Bedienungshilfen-Berechtigung nötig. Ob du am Computer bist, wird über die System-Leerlaufzeit erkannt, auch dafür ist keine Berechtigung nötig.
- Die App findet das Board über die USB-Hersteller-ID von WCH (CH340) und verbindet sich nach dem erneuten Einstecken wieder. Das Öffnen oder Schließen des Ports setzt das Board nie zurück.
- Die CPU-Last bleibt nahe 0 %.

<p align="center">
  <img src="../images/macos-settings-general.png" width="49%" alt="Settings: General">
  <img src="../images/macos-settings-pomodoro.png" width="49%" alt="Settings: Pomodoro">
</p>
<p align="center">
  <img src="../images/macos-settings-reminders.png" width="49%" alt="Settings: Reminders">
  <img src="../images/macos-settings-usage.png" width="49%" alt="Settings: Usage">
</p>

### Woher die Nutzungsdaten kommen

Sysmon verwendet die Anmeldungen, die auf deinem Mac bereits vorhanden sind, nur lesend:

- **Claude:** die Claude-Code-Zugangsdaten im Schlüsselbund „Anmeldung“ (Eintrag `Claude Code-credentials`, gelesen über `/usr/bin/security`, daher ohne Berechtigungsabfrage), gesendet an den Nutzungs-Endpunkt von Anthropic.
- **ChatGPT:** die Datei `~/.codex/auth.json` von Codex, gesendet an den Nutzungs-Endpunkt von ChatGPT.

Sysmon erneuert diese Anmeldungen nie und schreibt nie in den Schlüsselbund oder in `auth.json`, kann dich also nicht abmelden. Der Haken: Wenn du Claude Code oder Codex eine Weile nicht benutzt, läuft die Anmeldung ab, und der Bildschirm zeigt weiter die letzten Werte, markiert mit „Abgelaufen“. Abhilfe: einmal `claude` im Terminal ausführen oder Codex einmal öffnen; neue Werte erscheinen innerhalb von 2 Minuten. Die Nutzung wird alle 2 Minuten abgerufen, nicht aber bei ausgeschaltetem Bildschirm.

Keiner der beiden Endpunkte ist dokumentiert, und beide können sich ändern. Lässt sich einer nicht auswerten, zeigt nur dieser Bildschirm „Lesen fehlgeschlagen“.

## Voraussetzungen

| Punkt | Voraussetzung |
|---|---|
| Board | ESP32-2432S024R (ESP32-D0WD-V3, 4 MB Flash, ST7789 240×320, CH340-Seriell) |
| Mac | macOS 14 oder neuer |
| Firmware-Toolchain | [PlatformIO](https://platformio.org/) |
| Mac-Toolchain | Xcode Command Line Tools (Swift 6) |

## Schnellstart

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. Firmware flashen

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` verwendet `/dev/cu.usbserial-114110`; ändere das auf deinen Port (`ls /dev/cu.usbserial-*`). Beende Sysmon vor dem Flashen, sonst ist der Port belegt.

> Über einen USB-Hub lässt sich dieses Board mit 921600 und 460800 nicht flashen, daher ist `upload_speed` fest auf 115200 gesetzt.

### 2. Menüleisten-App installieren

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` baut ein Release, erstellt `Sysmon.app`, signiert es ad hoc und installiert es in `~/Applications`. Aktiviere in den Einstellungen bei Bedarf „Bei der Anmeldung starten“.

## Entwicklung

Tests ausführen:

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

Das Board ohne Sysmon ansteuern (benötigt pyserial; das Python von PlatformIO bringt es schon mit):

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # sys / pomo / cl / gpt mit --page
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # Bildschirme automatisch wechseln
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

Die Banner-Titel verwenden eine winzige Schrift, die nur die benötigten Zeichen enthält (die Firmware belegt schon über 90 % ihres Flashs). Nach einer Änderung der Titel in `lib/sysmon_core/banner_titles.h` muss sie neu erzeugt werden; die Schrift ist Source Han Sans CN Bold (SIL Open Font License 1.1) und muss lokal installiert sein:

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

Die Bilder dieser README werden von `docs/images/make_preview.py` und `docs/images/make_screens.py` erzeugt; die Befehle stehen im Kopf des jeweiligen Skripts.

### Serielles Protokoll

115200 8N1, Klartext, ein Datensatz pro Zeile:

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| Feld | Bedeutung |
|---|---|
| `cpu` | CPU-Auslastung, 0–100 |
| `mem` | Speicherdruck in Prozent, 0–100 |
| `lvl` | Speicherdruck-Level: 1 normal, 2 Warnung, 4 kritisch |
| `rx` / `tx` | Download- / Upload-Geschwindigkeit, Bytes pro Sekunde |
| `OFF` | Bildschirm ausschalten bis zur nächsten `S`-Zeile |

Die Firmware ignoriert unbekannte Zeilen und Felder. Seiten, Nutzung, Pomodoro und Banner verwenden die Zeilen `P`, `U`, `T` und `B`, und das Board sendet `TAP`, wenn man darauf tippt: siehe die Header-Kommentare von `usage_protocol.h`, `timer_protocol.h` und `Protocol.swift`.

## Repository-Struktur

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
.superpowers/          UI mockups from the design phase
docs/images/           README pictures and their generators
docs/readme/           translated READMEs
```

## Hardware-Hinweise

- Der Display-Controller ist ein **ST7789**, kein ILI9341. Mit `Panel_ILI9341` erscheint das Bild transponiert und gespiegelt.
- LovyanGFX-Einstellungen: `rgb_order=false` (bei true sind Rot und Blau vertauscht), `invert=false`, Rotation 0.
- Hintergrundbeleuchtung an GPIO27, active high. MISO des Displays ist nicht angeschlossen, daher lässt sich seine ID nicht auslesen.
- Die RGB-LED auf der Rückseite hat gemeinsame Anode und ist active low: GPIO4 Rot, GPIO16 Blau, GPIO17 Grün (Blau und Grün sind also vertauscht gegenüber dem, was die meisten CYD-Notizen sagen).
- Der CH340 steuert EN und GPIO0 über DTR/RTS. Sysmon setzt beide direkt nach dem Öffnen des Ports zurück und schaltet `HUPCL` aus, sodass das Öffnen oder Schließen des Ports das Board nie zurücksetzt.
