# VideoTrimmer

Kleines natives macOS-Werkzeug zum Trimmen von MP4-/MOV-Videos mit Vorschau –
wie die Trimmfunktion auf dem iPhone: gelbe Griffe für Anfang und Ende,
Abspielmarke, Bild-für-Bild-Navigation, dann „Sichern unter…“.

Geschrieben in Objective-C++ (C++17-Kern, Cocoa/AVFoundation für Fenster,
Wiedergabe und Schnitt). Keine Abhängigkeiten außer den Xcode Command Line Tools.

## Bauen und starten

```sh
make            # erzeugt build/VideoTrimmer.app
make run        # baut und öffnet die App
make install    # kopiert die App nach /Applications
make test       # Unit-Test der Zeit-Hilfsfunktionen
make icon       # App-Icon neu erzeugen (resources/VideoTrimmer.icns)
```

Ein Video öffnen: per Drag & Drop ins Fenster, mit ⌘O, über „Öffnen mit…“ im
Finder oder direkt beim Start:

```sh
build/VideoTrimmer.app/Contents/MacOS/VideoTrimmer ~/Movies/urlaub.mp4
```

## Bedienung

| Aktion | Maus | Tastatur |
|---|---|---|
| Wiedergabe / Pause | ▶︎-Knopf | Leertaste |
| Ein Bild vor / zurück | Knöpfe neben ▶︎ | → / ← |
| Eine Sekunde vor / zurück | – | ⇧→ / ⇧← |
| Position ändern | Klick oder Ziehen in der Zeitleiste | – |
| Anfang / Ende der Auswahl setzen | gelbe Griffe ziehen, oder „Start setzen“ / „Ende setzen“ | I / O |
| Zeiten exakt eingeben | in die Felder tippen (z. B. `1:23.5`, `0:01:23`), Return | – |
| Zum Auswahlanfang / -ende springen | – | ⌘← / ⌘→ |
| Auswahl zurücksetzen | Knopf | ⌘R |
| **Auswahl sichern** | „Auswahl sichern…“ | ⌘S |
| **Anfang bis Abspielposition sichern** | „Anfang → hier sichern…“ | ⇧⌘A |
| **Abspielposition bis Ende sichern** | „Hier → Ende sichern…“ | ⇧⌘E |

Die Wiedergabe stoppt automatisch am Auswahlende; ▶︎ außerhalb der Auswahl
startet am Auswahlanfang.

## Export-Modi

* **Schnell (verlustfrei)** – Bild- und Tondaten werden unverändert kopiert
  (Passthrough), fertig in Sekunden, keine Qualitätsverluste. Der Schnitt ist
  über eine Edit-Liste exakt; QuickTime, VLC, ffmpeg und Browser respektieren
  sie. Einige ältere Player ignorieren Edit-Listen und zeigen am Anfang bis zum
  vorigen Schlüsselbild etwas mehr (typisch 1–2 s).
* **Bildgenau (neu kodieren)** – Video wird als H.264 in Originalauflösung neu
  kodiert. Dauert deutlich länger, dafür ist der Schnitt in jedem Player exakt.

Der gewählte Modus wird gemerkt. Die Ausgabe heißt standardmäßig
`<name>_<start>-<ende>.mp4` und landet im Ordner des Originals; bei Quellen,
die MP4 nicht aufnehmen kann (z. B. PCM-Ton), wird `.mov` vorgeschlagen.

## Kommandozeile

Schneiden ohne Fenster, z. B. für Skripte:

```sh
build/VideoTrimmer.app/Contents/MacOS/VideoTrimmer --cut EIN AUS START ENDE [--reencode]
build/VideoTrimmer.app/Contents/MacOS/VideoTrimmer --cut urlaub.mp4 kurz.mp4 1:23.5 4:10
```

## Grenzen

Es wird alles abgespielt und geschnitten, was macOS selbst dekodiert (H.264,
HEVC, MPEG-4, AAC, AC-3, MP3 …). Exotische Codecs in MP4 (VP9, AV1 auf älteren
Macs) öffnet die App nicht; dann vorher mit ffmpeg nach H.264 wandeln.

## Projektstruktur

```
src/AppDelegate.mm   Fenster, Menüs, Wiedergabe, Auswahl, Export-Ablauf
src/TrimView.mm      Zeitleiste: Filmstreifen, gelbe Griffe, Abspielmarke
src/Exporter.mm      Schnitt per AVAssetExportSession
src/Views.mm         AVPlayerLayer-View und Drag-&-Drop-Ziel
src/TimeUtil.hpp     Zeitformatierung/-parsing (reines C++)
src/main.mm          Start, Kommandozeilen-Modus
tests/time_test.cpp  Unit-Test für TimeUtil
tools/mkicon.mm      zeichnet das App-Icon vektoriell (AppKit) und erzeugt das .iconset/.icns
resources/           fertiges App-Icon
```

Debug-Hilfe: `VT_SNAPSHOT=/pfad/bild.png` (optional `VT_SNAPSHOT_DELAY`,
`VT_WINDOW_SIZE=880x560`) speichert den Fensterinhalt als PNG und beendet die App.
