# OpenHardwareMonitorCLI – LibreHardwareMonitor-Edition für Checkmk

> **English summary:** Drop-in replacement for the `OpenHardwareMonitorCLI.exe` used by the Checkmk Windows
> agent (section `openhardwaremonitor`), based on the actively developed
> [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) and the signed
> PawnIO driver instead of the vulnerable WinRing0 driver (CVE-2020-14979). Same file names
> (`OpenHardwareMonitorCLI.exe` + `OpenHardwareMonitorLib.dll`, deployable with the existing bakery rule),
> same WMI namespace and classes (`root\OpenHardwareMonitor`), OHM-compatible identifiers so existing
> service names stay. Requires Windows x64, .NET Framework 4.7.2 and PawnIO (`winget install namazso.PawnIO`).
> Prebuilt files: see [Releases](../../releases) or the artifacts of the [build workflow](../../actions).
> Related idea: [Replace Open Hardware Monitor with LibreHardwareMonitor](https://ideas.checkmk.com/suggestions/535894/replace-open-hardware-monitor-with-librehardwaremonitor).

Ein headless Ersatz für die `OpenHardwareMonitorCLI.exe`, die Checkmk für die Sektion
`<<<openhardwaremonitor>>>` benutzt. Statt des toten OpenHardwareMonitor (mit dem als
verwundbar gemeldeten WinRing0-Treiber, CVE-2020-14979) verwendet er die aktuelle
**LibreHardwareMonitorLib**, standardmäßig direkt aus dem aktuellen Quellcode des
[LibreHardwareMonitor-Repos](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) gebaut,
mit dem signierten **PawnIO**-Treiber.

Er ist ein **Drop-in-Ersatz**: gleiche Dateinamen, gleicher WMI-Namespace, gleiche Klassen
und Eigenschaften. Am Checkmk-Agenten, am Bakery-Plugin und an den Check-Plugins muss nichts
geändert werden.

| | Original (OHM) | Diese Version |
|---|---|---|
| Dateien | `OpenHardwareMonitorCLI.exe` + `OpenHardwareMonitorLib.dll` | dieselben zwei Dateien |
| WMI | `root\OpenHardwareMonitor`, Klassen `Sensor` und `Hardware` | identisch |
| Sensor-Eigenschaften | Index, Name, Parent, SensorType, Value, Min, Max, Identifier | identisch |
| Update-Intervall | 1 s | 1 s (einstellbar) |
| Hardware | CPU, RAM, Mainboard, Lüftersteuerung, HDD | dieselben, optional GPU, PSU, Netzwerk, Akku |
| Treiber | WinRing0 (verwundbar) | PawnIO (signiert, wird separat installiert) |

## Wie es aufgebaut ist

Der Checkmk-Bakery verteilt genau zwei Dateien. LibreHardwareMonitor braucht aber mehrere DLLs
(HidSharp, DiskInfoToolkit, RAMSPDToolkit, System.Memory, …). Deshalb:

- **`OpenHardwareMonitorLib.dll`** ist die unveränderte `LibreHardwareMonitorLib.dll`, nur umbenannt.
- **`OpenHardwareMonitorCLI.exe`** enthält alle übrigen Abhängigkeiten als eingebettete Ressourcen
  und lädt sie beim Start selbst.

Das Verhalten entspricht 1:1 dem Original (aus der Original-EXE dekompiliert): Sensoren jede
Sekunde lesen und als WMI-Instanzen veröffentlichen; der Agent fragt
`SELECT Index,Name,Parent,SensorType,Value FROM Sensor` in `Root\OpenHardwareMonitor` ab.

Zusätzlich gegenüber dem Original:

- **OHM-kompatible Kennungen** (Standard), damit bestehende Checkmk-Services ihre Namen behalten:

  | LibreHardwareMonitor | wird veröffentlicht als |
  |---|---|
  | `/nvme/1`, `/ata/0`, `/scsi/2`, `/ssd/0` … | `/hdd/1`, `/hdd/0`, `/hdd/2`, `/hdd/0` |
  | `/motherboard` | `/mainboard` |
  | `/lpc/nct6798d/0` | `/lpc/nct6798d` |
  | `/gpu-nvidia/0`, `/gpu-amd/0` | `/nvidiagpu/0`, `/atigpu/0` |
  | `/intelcpu/0`, `/amdcpu/0`, `/ram` | unverändert |

  Mit `CompatIdentifiers=false` bzw. `--native-ids` werden die LHM-Kennungen unverändert veröffentlicht.
- Kommas und Zeilenumbrüche in Sensornamen und Geräte-Kennungen werden ersetzt (der Agent trennt mit `,`,
  der Checkmk-Parser verwirft Zeilen mit falscher Spaltenzahl).
- Ungültige Messwerte (NaN/Unendlich) werden als 0 veröffentlicht. Der Agent würde NaN als `-nan(ind)` ausgeben,
  daran scheitert der Checkmk-Parser, und die ganze Sektion fiele aus (alle Services UNKNOWN).
- Übersetzte Sprachdateien der Abhängigkeiten (z. B. deutsche SMART-Attributnamen von DiskInfoToolkit) werden
  bewusst nicht mitgeliefert: Sensornamen sind auf jedem Host englisch, unabhängig von der Windows-Sprache.
- Datenmengen (`Data`, z. B. RAM-Belegung, gelesene/geschriebene Daten) werden in **GB** veröffentlicht wie bei OHM.
  Seit Ende September 2026 liefert LibreHardwareMonitor diese Werte in Bytes; die CLI erkennt das und rechnet um.
- Laufwerks-Sensor `Life` heißt `Remaining Life` (den Namen erwartet der Checkmk-Check `openhardwaremonitor_smart`).
- Feste Grenz- und Konfigurationswerte, die LibreHardwareMonitor als Temperatursensoren meldet, werden nicht
  veröffentlicht, sonst entstünden dauerhaft kritische Temperatur-Services:
  NVMe `Warning Temperature`, `Critical Temperature`, `Available Spare Threshold`;
  RAM-Module `Temperature Sensor Resolution`, `Thermal Sensor (Critical) Low/High Limit`.
- Lüfter erscheinen erst, wenn sie einmal gedreht haben (wie bei OHM). Unbelegte Lüfteranschlüsse tauchen
  so nicht als Services mit 0 U/min auf.
- Die 24-Stunden-Werte-Historie von LHM ist abgeschaltet → konstanter Speicherverbrauch.
- Updates laufen nie parallel (langsame SMART-/GPU-Abfragen stauen sich nicht).
- Sauberes Beenden (Treiber-Handles werden geschlossen), nur eine Instanz gleichzeitig.
- Testmodi `--dump` und `--report`, optionales Logfile.

## Voraussetzungen auf dem Windows-Host

1. **.NET Framework 4.7.2 oder neuer** (ab Windows 10 1803 / Server 2019 vorhanden; Server 2016 braucht ein Update).
2. **PawnIO-Treiber** – ohne ihn fehlen CPU-Temperaturen, Mainboard/SuperIO (Lüfter, Spannungen) und RAM-Sensoren.
   Laufwerke (SMART/NVMe), CPU-Last und RAM-Auslastung gehen auch ohne.
   ```
   winget install namazso.PawnIO
   ```
   oder Installer von https://pawnio.eu.

## Fertige Dateien herunterladen

Ohne selbst zu bauen:
- **[Releases](../../releases)**: `OpenHardwareMonitorCLI-LHM-<version>.zip` mit EXE, DLL, Beispiel-Config,
  `BUILD-INFO.txt` und Installationsskript.
- **[Actions](../../actions/workflows/build.yml)**: Jeder Build (bei jedem Push und jeden Montag gegen den aktuellen
  LibreHardwareMonitor-Stand) stellt das Artefakt `OpenHardwareMonitorCLI-LHM` bereit (GitHub-Login nötig).

## Bauen

Voraussetzung: **.NET 10 SDK** (`winget install Microsoft.DotNet.SDK.10`), empfohlen zusätzlich **git**
(`winget install Git.Git`). Ohne git lädt das Skript den Quellcode als ZIP von GitHub.

Repo klonen (`git clone https://github.com/Tinnitus97/libre_hardware_monitor_checkmk.git`) oder als ZIP herunterladen.
Bei einer heruntergeladenen ZIP einmal die Download-Sperre von allen Skripten entfernen (sonst fragt PowerShell bei jedem Skript nach):
```powershell
Get-ChildItem -Recurse | Unblock-File
```

```
build.cmd                  LibreHardwareMonitor aus dem aktuellen Repo-Stand (master)
build.cmd -Ref v0.9.6      bestimmter Branch, Tag oder Commit
build.cmd -NoUpdate        vorhandenen Quellcode erneut bauen, ohne zu aktualisieren
build.cmd -FromNuGet       letzte stabile Version von nuget.org statt Quellcode
```

Das Skript holt LibreHardwareMonitor nach `external\LibreHardwareMonitor`, aktualisiert es bei jedem Lauf
und kompiliert die Bibliothek zusammen mit der CLI. Ergebnis in `dist\`:
```
OpenHardwareMonitorCLI.exe
OpenHardwareMonitorLib.dll
OpenHardwareMonitorCLI.exe.config.example
BUILD-INFO.txt                 welcher LibreHardwareMonitor-Commit verbaut wurde
```

Der Repo-Stand ist eine Entwicklungsversion und nicht als Release getestet. Wenn ein neuer Stand
Probleme macht, kannst du mit `-Ref <commit>` auf einen funktionierenden Commit zurückgehen (steht in `BUILD-INFO.txt`).

**Über GitHub Actions** (ohne lokales SDK): Der Workflow `.github/workflows/build.yml` baut auf `windows-latest`
gegen den aktuellen LibreHardwareMonitor-master, testet `--dump` und die echte WMI-Abfrage und stellt das Ergebnis
als Artefakt `OpenHardwareMonitorCLI-LHM` bereit. Er läuft bei jedem Push und zusätzlich jeden Montag; über
„Run workflow“ lässt sich ein bestimmter LibreHardwareMonitor-Ref bauen (auch in einem Fork).

**Release erstellen:** Entweder ein Tag `v*` pushen (z. B. `git tag v1.1.0 && git push origin v1.1.0`) oder auf
GitHub unter *Releases → Draft a new release* ein neues Tag `v…` anlegen und veröffentlichen. Der Workflow baut,
testet und hängt die ZIP an das Release an.

## Installation

### Variante 1: Über die Agent-Bakery (Checkmk Enterprise/Cloud)

Wie in `doc/treasures/windows/ohm/README.md` von Checkmk beschrieben, nur mit diesen Dateien:

```bash
su - meinsite
cp OpenHardwareMonitorCLI.exe OpenHardwareMonitorLib.dll local/share/check_mk/agents/windows/
```

Dann Regel **„OpenHardwareMonitor (Windows)“** → *Deploy OpenHardwareMonitor (headless)*, Agenten backen
und verteilen. PawnIO muss separat auf den Hosts installiert werden (z. B. per Softwareverteilung/winget).

Hinweis: Der Bakery verteilt keine `.config`-Datei. Ohne sie gelten die Standardwerte
(CPU, RAM, Mainboard, Lüftersteuerung, Laufwerke; OHM-kompatible Kennungen).

### Variante 2: Manuell / ohne Bakery

Als Administrator im Repo- bzw. Release-Ordner:
```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-checkmk.ps1 -RemoveWinRing0
```
Das Skript stoppt den Agenten, entfernt optional den alten WinRing0-Treiber und das alte WMI-Schema,
kopiert die Dateien nach `C:\ProgramData\checkmk\agent\bin`, startet den Agenten und zeigt die
gefundenen Sensoren an.

Manuell geht es genauso: beide Dateien nach `C:\ProgramData\checkmk\agent\bin` kopieren und den
Dienst `CheckMkService` neu starten. Die Sektion `openhardwaremonitor` ist im Agenten standardmäßig aktiv.

Danach in Checkmk eine **Service-Erkennung** für die Hosts ausführen.

## Testen

```powershell
# Sensoren direkt im Checkmk-Format ausgeben (ohne WMI, als Administrator):
OpenHardwareMonitorCLI.exe --dump --header

# Alles, was LHM findet (inkl. GPU usw.):
OpenHardwareMonitorCLI.exe --dump --all

# Versionen und PawnIO-Status:
OpenHardwareMonitorCLI.exe --version

# Was der Agent sieht (während der Agent / die CLI läuft):
Get-CimInstance -Namespace root/OpenHardwareMonitor -ClassName Sensor |
  Select Index,Name,Parent,SensorType,Value | Sort Parent,SensorType | Format-Table

# Agent-Ausgabe prüfen:
& "C:\Program Files (x86)\checkmk\service\check_mk_agent.exe" test |
  Select-String -Context 0,15 "<<<openhardwaremonitor"
```

## Konfiguration (optional)

`OpenHardwareMonitorCLI.exe.config.example` in `OpenHardwareMonitorCLI.exe.config` umbenennen und neben die EXE legen:

| Schlüssel | Bedeutung | Standard |
|---|---|---|
| `Enable` | zusätzliche Gruppen: `gpu, network, psu, battery, powermonitor, all` | – |
| `Disable` | Gruppen abschalten: `cpu, memory, motherboard, controller, storage` | – |
| `IntervalMs` | Update-Intervall in ms (min. 250) | 1000 |
| `CompatIdentifiers` | OHM-kompatible Kennungen | true |
| `LogFile` | Logdatei (relativ zur EXE), z. B. `OpenHardwareMonitorCLI.log` | – |
| `Verbose` | ausführliches Log | false |

Dieselben Einstellungen gibt es als Kommandozeilenoptionen (`--help`).

## Geprüft gegen den Checkmk-Code

Gegen den aktuellen Stand von https://github.com/Checkmk/checkmk geprüft:

- **Windows-Agent** (`agents/wnx`): startet `bin\OpenHardwareMonitorCLI.exe` ohne Argumente, wenn der Agent mit
  Adminrechten läuft und die Sektion `openhardwaremonitor` aktiv ist. Abfrage
  `SELECT Index,Name,Parent,SensorType,Value FROM Sensor` in `Root\OpenHardwareMonitor`, Werte per `std::to_wstring`,
  Spalte `WMIStatus` wird angehängt. Nach zu vielen Fehlern beendet der Agent die CLI, löscht den WMI-Namespace und
  startet neu; die CLI registriert ihr Schema dabei automatisch wieder.
- **Bakery** (`win_openhardwaremonitor`): verteilt genau `OpenHardwareMonitorCLI.exe` und `OpenHardwareMonitorLib.dll`.
- **Check-Plugins** (`cmk/plugins/openhardwaremonitor`): Parser, Service-Erkennung und alle fünf Checks
  (Clock, Temperature, Fan, Power, SMART) wurden mit dem originalen Checkmk-Code gegen echte Sensordaten
  eines Ryzen-Systems ausgeführt; die Checkmk-eigenen Unit-Tests laufen ebenfalls.

## Hinweise zu den Checkmk-Grenzwerten

Die Checkmk-Temperaturprüfung hat feste Standardgrenzen je Gerätetyp: **CPU 60/70 °C**, **Laufwerke 40/50 °C**,
alles andere 70/80 °C (Warnung/Kritisch). Moderne Ryzen-CPUs (Tctl) erreichen unter Last regelmäßig 80–95 °C, NVMe-SSDs
laufen oft mit 50–70 °C. Diese Services daher über die Regel **„Temperature“** passend einstellen.

## Migration von der alten OHM-CLI

- Service-Namen bleiben dank der Kompatibilitäts-Kennungen in der Regel gleich. Sensoren, die LHM
  anders benennt oder neu liefert, tauchen bei der Service-Erkennung als neue/verschwundene Services auf.
- Das alte WMI-Schema sollte einmal gelöscht werden (macht das Installationsskript; der Agent tut es
  auch selbst nach mehreren Fehlern):
  `Get-CimInstance -Namespace root -ClassName __Namespace -Filter "Name='OpenHardwareMonitor'" | Remove-CimInstance`
- Den alten WinRing0-Treiberdienst (`winring0_1_2_0`) entfernen – genau wegen ihm wurde OHM aus Checkmk entfernt.

## Projektstruktur

```
build.cmd / build.ps1               Build inkl. Download/Update des LibreHardwareMonitor-Quellcodes
src/OpenHardwareMonitorCLI.csproj   SDK-Projekt (net472), LHM als Projektreferenz (oder NuGet)
src/Program.cs                      Einstiegspunkt, Modi (Provider, --dump, --report)
src/DataProvider.cs                 LHM Computer + Update-Timer
src/WMI/WmiProvider.cs              WMI-Veröffentlichung (wie Original)
src/WMI/WmiObjects.cs               WMI-Klassen Hardware / Sensor
src/IdentifierMapper.cs             LHM → OHM Kennungen
src/EmbeddedAssemblyResolver.cs     lädt eingebettete Abhängigkeiten + OpenHardwareMonitorLib.dll
src/Options.cs, App.config          Einstellungen
tools/install-checkmk.ps1           Installation in einen lokalen Checkmk-Agenten
.github/workflows/build.yml         CI-Build inkl. WMI-Test
```

## Lizenz

Mozilla Public License 2.0 – wie LibreHardwareMonitor und OpenHardwareMonitor.
