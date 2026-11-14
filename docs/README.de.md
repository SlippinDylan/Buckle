<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>Alltägliche Mac-Werkzeuge, nur einen Klick entfernt.</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <strong>Deutsch</strong> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>
</div>

Buckle ist eine native macOS-Menüleisten-App für Systemwerkzeuge, Browserstarts in einer anderen Sprache und häufige Finder-Aktionen. Sie läuft im Hintergrund ohne Dock-Symbol.

> [!NOTE]
> Für Buckle 0.1.1 gibt es noch kein öffentliches Installationspaket. Die Bauanleitung steht unten.

## Funktionen

<table>
  <tr>
    <td width="36%"><strong>Systemwerkzeuge in der Menüleiste</strong><br><br>Öffne das Systemfenster zur Speichernutzung, setze Maus-Hilfsprogramme mit Fortschritts- und Ergebnisanzeige zurück oder starte die Systemmenüleiste neu. Finder-Aktionen lassen sich einzeln umschalten; ein Häkchen bedeutet aktiviert.</td>
    <td width="64%" align="center"><img src="images/readme/menu-bar.png" width="310" alt="Systemwerkzeuge in der Menüleiste"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Aktionen direkt im Finder</strong><br><br>Ergänze das Finder-Kontextmenü um AirDrop, Im Terminal öffnen, Pfad kopieren und Objekte hierherbewegen. Das Terminal öffnet sich im ausgewählten oder aktuellen Ordner; mehrere Pfade werden zeilenweise kopiert.</td>
    <td width="64%" align="center"><img src="images/readme/finder-context-menu.png" width="285" alt="Aktionen direkt im Finder"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Browser in acht Sprachen starten</strong><br><br>Wähle einen installierten Browser und anschließend eine Sprache. Buckle erkennt unterstützte Browser bei jedem Öffnen des Menüs. Der Start erfolgt direkt durch die App, ohne persönliche Skripte.</td>
    <td width="64%" align="center"><img src="images/readme/browser-language.png" width="580" alt="Browser in acht Sprachen starten"></td>
  </tr>
</table>

### Einstellungen

Unter **Einstellungen → Allgemein** verwaltest du den Start bei der Anmeldung und die App-Sprache. Standardmäßig folgt sie macOS. Zur Auswahl stehen Englisch, vereinfachtes und traditionelles Chinesisch, Japanisch, Koreanisch, Deutsch, Französisch und Spanisch. Sprachänderungen werden nach einem Neustart von Buckle wirksam.

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="Allgemeine Einstellungen">
  <img src="images/readme/permissions-settings.png" width="340" alt="Berechtigungsstatus">
</p>

Die Screenshots zeigen die englische Oberfläche. Menüs hängen von installierten Browsern, aktivierten Aktionen und kopierten Dateien ab.

## Installation und erster Start

Erfordert **macOS 15 oder neuer** auf Apple Silicon oder Intel. CI-Builds zielen auf Universal 2.

1. Folge den Bau- und Installationsschritten unten und öffne dann die installierte App aus `/Applications`.
2. Klicke auf das Menüleistensymbol, um Werkzeuge zu verwenden oder Finder-Aktionen zu aktivieren. Alle vier Finder-Aktionen sind anfangs ausgeschaltet; deine Auswahl wird gespeichert.
3. Öffne **Einstellungen → Berechtigungen**, um die Finder-Erweiterung zu aktivieren oder benötigte Zugriffe zu erlauben. Der Status aktualisiert sich automatisch. Grüner Text und ein Häkchen zeigen erteilten Zugriff oder eine aktivierte Erweiterung an.

Die Builds sind ad-hoc-signiert und nicht notarisiert. Heruntergeladene Builds benötigen möglicherweise eine Freigabe in den Systemeinstellungen; nach einem Update können erneute Berechtigungen nötig sein.

## Hinweise zur Verwendung

- **Speicherfenster:** öffnet macOS LowMemoryPanel manuell, auch bei normaler Speichernutzung. Der eingebaute Speicherwarntext ist keine Diagnose von Buckle. Die Funktion nutzt einen privaten System-Debug-Pfad. Buckle prüft das konkrete Speicherwarnfenster, stellt die temporäre Einstellung wieder her und meldet einen Fehler, wenn das Fenster nicht bestätigt werden kann. Die Kompatibilität muss je macOS-Version getestet werden. Bedienungshilfen und System Events-Automatisierung sind erforderlich; es gibt keine Hintergrundüberwachung.
- **Maus zurücksetzen:** Verwalte die Programmliste unter **Einstellungen → Maus-Reset**. Die Standardliste enthält Moom, MonitorControl, BetterMouse und iShot Pro. Bei jedem Vorgang werden laufende Programme aus der Liste beendet, die gemeinsamen macOS-Einstellungsdienste und systemweiten Berechtigungsdienste aktualisiert und die Programme wieder geöffnet. Nur zuvor laufende Programme werden erneut geöffnet. Die Dienstaktualisierung kann andere Programme kurz beeinflussen und erfordert Administratorrechte. Deinstallierte Programme werden übersprungen; auch bei leerer Liste werden die Dienste aktualisiert. Ausstehende Wiederherstellungen werden gespeichert. Nach einer Unterbrechung fragt Buckle beim nächsten Start, ob die Programme wieder geöffnet werden sollen; „Später“ behält den Eintrag.
- **Systemmenüleiste neu starten:** startet den SystemUIServer deines Benutzers ohne sudo neu. Symbole anderer Apps werden dadurch möglicherweise nicht repariert.
- **Browserprofile:** verwendet die vorhandenen Browserdaten und gespeicherten Anmeldungen, ohne ein separates Profil anzulegen. Die Profilauswahl folgt dem Verhalten des Browsers. Beende den Browser vor einem Sprachwechsel. Läuft er bereits, zeigt Buckle nur einen Hinweis. IP-Adresse und Zeitzone bleiben gleich; die Sprache einer Website wird nicht garantiert.
- **Finder:** Pfad kopieren wird in der Erweiterung ausgeführt; andere Aktionen starten Buckle bei Bedarf. Kopiere zum Bewegen zuerst Dateien im Finder und klicke dann mit der rechten Maustaste auf den Zielordner oder dessen Hintergrund. Verschiebungen erfordern eine Bestätigung, ersetzen keine vorhandenen Objekte und sind nicht in Finder-Widerrufen integriert. Bei einem Teilfehler bleiben abgeschlossene Verschiebungen bestehen. Prüfe vor dem nächsten Versuch beide Ordner. Die Menüposition bestimmt Finder. Eigene Finder-Menütexte folgen nach einem Neustart von Buckle der App-Sprache; der native AirDrop-Name folgt dem System.
- **Updates:** Sparkle ist integriert. Manuelle Prüfungen findest du unter **Einstellungen → Info**, automatische unter **Allgemein**. Entwicklungs- und Pull-Request-Builds deaktivieren Updates; CI-Release-Builds auf main aktivieren sie. Online-Updates erfordern ein veröffentlichtes Installationspaket und einen signierten Feed.

## Aus dem Quellcode bauen

Erfordert Xcode 26 oder neuer, Node.js und Python 3. Für Debug-Builds ist kein Apple-Entwickleraccount nötig.

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

Wähle nach dem Bauen einen der folgenden Abläufe.

### Für den täglichen Gebrauch installieren

Beende ein laufendes Buckle über **Beenden** im Menüleistenmenü und warte, bis es beendet ist. Verschiebe im Finder die gesamte `Buckle.app` aus `build/DerivedData/Build/Products/Debug/` nach `/Applications`. Auch eine vorhandene Kopie darf erst nach dem Beenden ersetzt werden. Öffne `/Applications/Buckle.app` und behalte nur eine installierte Kopie.

### Für die Entwicklung ausführen

Schließe ein laufendes Buckle über **Beenden** und warte, bis es beendet ist, bevor du den folgenden Befehl ausführst. Alternativ öffne danach `Buckle.xcodeproj` und führe das Scheme `Buckle` in Debug aus. Buckle erlaubt nur eine laufende Instanz: Läuft bereits eine andere Kopie, beendet sich der neue Prozess. Verwende während der Entwicklung den zu testenden Build und öffne nicht gleichzeitig die installierte Kopie.

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

## Entwicklerdokumentation

Der [Entwicklungsleitfaden](development.md) (vereinfachtes Chinesisch) beschreibt Build-Prüfungen, CI, Paketierung, Update-Veröffentlichung, Signierung und die Prüfung auf echten Geräten. Öffentliche Installationspakete erscheinen künftig unter [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases).
