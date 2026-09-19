# Sicherung auf USB-Platte oder Netzwerkfreigabe

**Wenn du auf eine USB-Platte oder eine Netzwerkfreigabe sicherst, solltest du den optionalen Schutz des Sicherungsziels einschalten.** Das Skript prüft dann, ob am vorgesehenen Ort das erwartete Medium verfügbar ist. Die Funktion ist zunächst ausgeschaltet und muss einmal eingerichtet werden.

Warum ist das nötig? Unter Linux wird ein Laufwerk in einen Ordner eingebunden. Dieser Ordner kann auch dann noch existieren, wenn die USB-Platte fehlt. Ohne zusätzliche Prüfung könnte das Backup dort auf dem internen NAS-Speicher landen. Das würde nach einer Sicherung aussehen, obwohl auf der USB-Platte nichts angekommen ist.

Die Funktion verbindet keine Laufwerke und richtet keine Freigaben ein. Das Ziel muss bereits auf dem NAS beziehungsweise Linux-Rechner verfügbar sein, auf dem das Skript läuft.

## Wann sollte ich den Schutz verwenden?

| Dein Sicherungsziel | Empfehlung |
| --- | --- |
| USB-Festplatte oder USB-Stick am NAS | Schutz einschalten. Das Skript soll abbrechen, wenn das erwartete Medium fehlt. |
| Eingebundene Freigabe eines anderen NAS oder Servers, etwa SMB oder NFS | Schutz einschalten. Die Freigabe muss auf dem Rechner eingebunden sein, der das Skript ausführt. |
| Normaler Ordner auf einem dauerhaft verfügbaren internen NAS-Volume | Die neuen Angaben können leer bleiben. Für ein gesondert eingebundenes Volume kann der Schutz ebenfalls sinnvoll sein. |
| Ein Windows-Laufwerk wie `Z:` oder eine nur am PC angeschlossene USB-Platte | Das ist noch kein Sicherungsziel auf dem NAS. Das Ziel muss zuerst vom NAS aus über einen Linux-Pfad erreichbar und eingebunden sein. |

Diese Anleitung betrifft **den Zielort des fertigen Backups**. Der Docker-Exportordner, in den Paperless seine Daten zunächst exportiert, wird separat geprüft. Seine Einstellungen werden unter [Compose, Portainer und Exportpfade](COMPOSE-PORTAINER.md) erklärt.

## Was bedeuten die drei Angaben?

| Einstellung im Skript | Bedeutung | Beispiel für eine USB-Platte |
| --- | --- | --- |
| `backup_dir` | Der eigene Ordner, in dem das Skript seine Sicherungen ablegt. | `/media/USB-Backup/Paperless` |
| `backup_mountpoint` | Der Ordner, an dem das Laufwerk eingebunden ist. Dieser Ort heißt **Mountpunkt**. | `/media/USB-Backup` |
| `backup_mount_source` | Die erwartete Platte oder Freigabe. Eine USB-Platte wird über ihre Dateisystem-Kennung, die **UUID**, angegeben. | `UUID=12345678-1234-1234-1234-123456789abc` |

`Paperless` ist hier ein Unterordner auf der USB-Platte. **Sicherungsordner und Mountpunkt dürfen nicht identisch sein.** Verwende einen eigenen Unterordner für dieses Skript.

Alle Pfade und Kennungen in dieser Anleitung sind Beispiele. Auf deinem NAS können sie anders aussehen, auch bei UGREEN. Übernimm die Werte deines eigenen Systems aus den folgenden Schritten.

## USB-Platte einrichten: Schritt für Schritt

### 1. Die richtige Platte anschließen und erkennen

Schließe die gewünschte USB-Platte am NAS an. Warte, bis sie vom NAS eingebunden wurde, und prüfe im Dateimanager des NAS, ob du das richtige Laufwerk und seine Dateien siehst.

Öffne dann eine Shell auf **dem NAS selbst**, beispielsweise über eine bereits eingerichtete SSH-Verbindung. Die folgenden Befehle gehören in diese NAS-Shell. Eine PowerShell auf deinem Windows-PC oder eine Shell im Paperless-Container zeigt nicht die dafür maßgeblichen Laufwerke des NAS.

Zeige die eingebundenen Dateisysteme an:

```bash
findmnt --kernel --list --output TARGET,SOURCE,FSTYPE,UUID
```

Dieser Befehl liest Informationen; er verändert keine Laufwerke. Die Liste kann viele Zeilen enthalten. Eine vereinfachte Beispielzeile für die gewünschte USB-Platte wäre:

```text
TARGET             SOURCE    FSTYPE UUID
/media/USB-Backup  /dev/sdb1  ext4   12345678-1234-1234-1234-123456789abc
```

`TARGET` ist der Mountpunkt. `UUID` ist die Kennung des Dateisystems auf der Platte. Der Gerätename in `SOURCE`, hier `/dev/sdb1`, kann sich beim erneuten Anschließen ändern; verwende für die USB-Platte deshalb die UUID. Hat die Platte mehrere Partitionen, wähle diejenige, auf der das Backup liegen soll.

Wenn du die passende Zeile nicht sicher zuordnen kannst oder keine UUID angezeigt wird, kläre die Zuordnung zuerst. Übernimm keine beliebige Zeile der Liste. Insbesondere ist `/` normalerweise das System-Dateisystem und kein geeigneter Mountpunkt für diese Einstellung.

### 2. Die Angaben im Skript eintragen

Öffne `Paperless-ngx-Backup-Script.sh` in einem Texteditor. Ändere die bereits vorhandenen Zeilen am Anfang des Skripts. Diese Einstellungen werden **in der Skriptdatei gespeichert**; sie sind keine Befehle zum Einhängen der Platte.

Für die Beispielzeile oben lauten sie:

```bash
backup_dir="/media/USB-Backup/Paperless"
backup_mountpoint="/media/USB-Backup"
backup_mount_source="UUID=12345678-1234-1234-1234-123456789abc"
```

Übertrage deinen Wert aus `TARGET` nach `backup_mountpoint`. Trage unter `backup_dir` denselben Pfad mit einem eigenen Unterordner ein. Übertrage die Kennung aus `UUID` nach `backup_mount_source` und setze `UUID=` davor. Die Anführungszeichen bleiben stehen; dadurch funktionieren auch Pfade mit Leerzeichen.

Der Mountpunkt muss bereits existieren. Den Backup-Unterordner kann das Skript nach erfolgreicher Prüfung anlegen. Die übrigen Angaben, etwa Projektpfad und Containernamen, müssen weiterhin zu deiner Paperless-Installation passen.

### 3. Die Zuordnung zunächst nur abfragen

Mit deinen tatsächlichen Werten kannst du die Kombination aus Mountpunkt und Quelle prüfen, bevor du ein Backup startest:

```bash
findmnt --kernel --noheadings --raw --output ID --mountpoint "/media/USB-Backup" --source "UUID=12345678-1234-1234-1234-123456789abc" --options rw
```

Dieser Befehl ist ebenfalls nur eine Abfrage. Eine einzelne Zahl, beispielsweise `417`, bedeutet: Eine passende, schreibbar eingehängte Quelle wurde gefunden. Diese Zahl ist eine interne Mount-ID und wird **nicht** ins Skript eingetragen. Eine leere Ausgabe oder eine Fehlermeldung bedeutet, dass die Zuordnung noch nicht bestätigt ist. Prüfe dann die Platte und die eingetragenen Werte.

Die Abfrage bestätigt noch nicht, dass das gesamte Backup funktionieren wird. Das Skript prüft zusätzlich den Sicherungsordner, die Schreibbarkeit und die Paperless-Container.

### 4. Die erste Sicherung manuell ausführen

Speichere das Skript und starte es wie in der [README](../README.md#skript-manuell-ausführen) beschrieben. Beispielsweise, mit deinem tatsächlichen Skriptpfad:

```bash
sudo bash "/Pfad/zu/Paperless-ngx-Backup-Script.sh"
echo "Rückgabecode: $?"
```

**Dieser Aufruf führt eine echte Sicherung mit den eingerichteten Export- und Bereinigungsschritten aus.** Währenddessen bleibt die Platte angeschlossen. Die zweite Zeile zeigt direkt danach den Rückgabecode: `0` bedeutet, dass der Lauf erfolgreich abgeschlossen wurde; ein anderer Wert bedeutet einen Fehler.

Im Protokoll sollte für unser Beispiel stehen:

```text
 - Mountschutz des Sicherungsziels: eingeschaltet (/media/USB-Backup)
```

Prüfe nach erfolgreichem Abschluss, ob im vorgesehenen Ordner auf der USB-Platte die Sicherungsdateien beziehungsweise der neue Versionsordner liegen. Eine Wiederherstellung in einer separaten Testinstanz bleibt die Prüfung, ob du mit dieser Sicherung tatsächlich wieder arbeiten kannst. Danach lässt sich der Lauf wie bisher über den Aufgabenplaner automatisieren.

## Netzwerkfreigabe: Was ist anders?

Die Freigabe muss bereits **auf dem NAS, das das Skript ausführt**, eingebunden sein. Dass du sie im Windows-Explorer öffnen kannst, reicht dafür nicht aus. Die Verbindung einschließlich Zugangsdaten wird außerhalb dieses Skripts eingerichtet.

Benutze zur Ermittlung wieder den Befehl aus Schritt 1. Bei einer Netzwerkfreigabe ist eine leere UUID-Spalte üblich. Hier verwendest du die angezeigte Quelle aus `SOURCE` statt einer UUID. Ein SMB-Beispiel:

```text
TARGET           SOURCE                  FSTYPE UUID
/mnt/NAS-Backup  //backup-server/Backup   cifs
```

Die dazugehörigen Einstellungen wären:

```bash
backup_dir="/mnt/NAS-Backup/Paperless"
backup_mountpoint="/mnt/NAS-Backup"
backup_mount_source="//backup-server/Backup"
```

Bei NFS könnte die letzte Zeile stattdessen so aussehen:

```bash
backup_mount_source="backup-server:/exports/Backup"
```

Verwende den tatsächlich angezeigten Wert. `backup_dir` enthält den **lokalen Linux-Pfad**, über den das NAS die Freigabe erreicht. Benutzername und Passwort gehören nicht in diese drei Einstellungen. Die Prüfung aus Schritt 3 funktioniert auch für Freigaben, wenn du bei `--mountpoint` den passenden lokalen Pfad und bei `--source` den Wert aus `backup_mount_source` einsetzt.

## Was passiert im Alltag?

| Situation | Verhalten und nächster Schritt |
| --- | --- |
| Die richtige Platte oder Freigabe ist verfügbar. | Das Skript prüft das Ziel und führt die Sicherung aus. |
| Die USB-Platte fehlt oder ist nicht eingebunden. | Die Sicherung wird vor dem Anlegen von Backup-Ordner und Protokoll abgebrochen. Platte anschließen, Einbindung prüfen und den Lauf erneut starten. |
| Eine andere Platte liegt am gleichen Pfad. | Bei abweichender Quelle wird abgebrochen. Die richtige Platte anschließen oder bei einem beabsichtigten Wechsel die Konfiguration sorgfältig anpassen. |
| Das Ziel ist nur lesbar oder der Schreibtest scheitert. | Der Export wird nicht gestartet. Schreibschutz, freien Platz und Berechtigungen prüfen. |
| Das Medium wechselt während des Laufs oder verschwindet. | Die wiederholten Prüfungen brechen bei erkanntem Wechsel ab. Der Lauf gilt als fehlgeschlagen; die weiteren Sicherungs- und Bereinigungsschritte werden nicht ausgeführt. |
| Beide neuen Einstellungen sind leer. | Der besondere Mountschutz ist ausgeschaltet. Der allgemeine Schreibtest findet weiterhin statt, erkennt aber kein fehlendes oder falsches Medium. |

**Bei einem frühen Abbruch kann kein neues Protokoll auf dem fehlenden Medium entstehen.** Die Fehlermeldung steht dann in der Shell oder in der vom Aufgabenplaner erfassten Ausgabe. Ein altes, erfolgreiches Protokoll bleibt unverändert und ist kein Beleg für den aktuellen Lauf. Prüfe Datum und Rückgabecode; richte den Aufgabenplaner so ein, dass du seine Fehlerausgaben sehen kannst.

## Häufige Fragen

**Muss ich den Schutz bei einer internen Sicherung einschalten?** Nein. Die beiden neuen Zeilen können leer bleiben. Das ist die Voreinstellung. Für ein zusätzlich eingehängtes internes Volume kann die Prüfung dennoch nützlich sein.

**Ich möchte den Schutz ausschalten. Was ändere ich?** Setze beide Werte leer; der Sicherungspfad `backup_dir` bleibt auf deinem gewünschten Ziel:

```bash
backup_mountpoint=""
backup_mount_source=""
```

Bei einer USB-Platte oder Freigabe entfällt damit die Prüfung, ob das gewünschte Medium verfügbar ist. Schalte den Schutz deshalb nicht allein aus, um eine ungeklärte Fehlermeldung zu umgehen.

**Kann ich zwei USB-Platten abwechselnd verwenden?** Eine Konfiguration erwartet genau die angegebene Quelle. Für zwei Platten brauchst du jeweils passende Einstellungen; eine beliebige angeschlossene Platte wird nicht automatisch ausgewählt. Nach einer Neuformatierung kann sich auch die UUID derselben Platte ändern.

**Warum erscheint „Benötigte Programme fehlen: findmnt“?** Für den eingeschalteten Schutz wird `findmnt` aus util-linux benötigt. Prüfe die Verfügbarkeit mit der Systemdokumentation oder dem Administrator. Das Skript installiert keine Programme selbst.

**Warum scheitert die Prüfung, obwohl der Zielordner vorhanden ist?** Ein Ordner beweist noch keine Einbindung. Prüfe mit Schritt 1, ob dort die erwartete Platte oder Freigabe liegt. In `backup_mountpoint` gehört der angezeigte Mountpunkt aus `TARGET`, nicht der darunterliegende Paperless-Backup-Ordner.

**Kann ich die Platte nach dem Backup entfernen?** Warte, bis der gesamte Lauf beendet ist, und wirf sie über die dafür vorgesehene Funktion des NAS aus. Der Schutz sperrt das Laufwerk nicht gegen Entfernen.

## Für den Autor: Zweck, Einbindung und Prüfbedarf

Das Änderungspaket ergänzt zwei Dinge: allgemeine Vorprüfungen für Programme und Schreibzugriffe sowie einen ausdrücklich einschaltbaren Schutz für das Sicherungsmedium. Der konkrete Fehlerfall ist eine fehlende USB-Platte oder Freigabe, deren ehemaliger Ordner weiterhin auf dem internen Speicher existiert. Der neue Schutz verhindert bei erkannter falscher Zuordnung, dass dort ein Backup-Verzeichnis oder Protokoll angelegt wird.

Bestehende Nutzer müssen die neuen Mount-Angaben zunächst nicht ausfüllen. Beide Werte sind standardmäßig leer. Wer USB oder eine Freigabe nutzt, sollte anhand der Anleitung die richtige Quelle festlegen. Das Skript kann diese Absicht nicht zuverlässig allein aus `backup_dir` erkennen. Es hängt keine Laufwerke ein, verändert keine Mount-Einstellungen und verwendet keine Zugangsdaten zur Einrichtung einer Freigabe.

Die bestehenden Container- und Export-Mount-Prüfungen bleiben eigenständige Prüfungen. Die neue Funktion betrifft `backup_dir`. Auch eine erfolgreiche Zielprüfung bestätigt weder die Vollständigkeit des Datenbestands noch die Wiederherstellbarkeit einer Sicherung.

Für die Übernahme sind neben den automatisierten Tests echte Linux-/NAS-Prüfungen sinnvoll: USB und Netzwerkfreigabe mit korrekter Quelle, ein vorhandener Mountordner ohne Medium, eine falsche Quelle und ein schreibgeschütztes Ziel. Solche Fehlerfälle gehören auf ein separates Testsystem. Eine erfolgreiche Sicherung sollte anschließend dort wiederhergestellt werden. Die bisherigen Regressionstests simulieren Docker und Mounts; sie ersetzen diese Prüfung nicht.

## Technische Einzelheiten und Grenzen

Der allgemeine Schreibtest verwendet eigene Dateien in einem zufällig benannten Verzeichnis `.paperless-preflight.*` unter `backup_dir`. Er prüft Anlegen, Schreiben, Lesen, Ersetzen mit `mv -T` und Entfernen, bevor das bisherige Protokoll ersetzt wird. Nach einem abgefangenen Fehler oder Signal wird aufgeräumt, soweit das Medium noch erreichbar und das Löschen möglich ist. Andernfalls wird der verbliebene Pfad gemeldet. Ein Stromausfall kann ebenfalls Testdateien zurücklassen.

Erforderlich sind Bash ab Version 4, Docker, `rsync` und die üblichen GNU-Dateiwerkzeuge. Vor dem ersten externen Aufruf wird geprüft, ob `dirname`, `date`, `realpath`, `stat`, `mkdir`, `rmdir`, `tee`, `docker`, `ls`, `rsync`, `mktemp`, `mv`, `cp`, `chown` und `rm` gefunden werden. Bei aktivierter Versionsbereinigung kommen `find` und `cat` hinzu. Die Optionen von `realpath` (`-e`, `-m`), `stat` (`-c`) und gegebenenfalls `find` (`-maxdepth`, `-mtime`) werden lesend geprüft. Compose wird nur im Compose-Modus benötigt.

`wget`, `grep`, `cut` und `dpkg` gehören zur optionalen Updateprüfung. Fehlt eines dieser Programme oder schlägt die Abfrage beziehungsweise der Versionsvergleich fehl, wird die Prüfung mit einem Hinweis übersprungen. Das Backup läuft weiter.

Bei aktivem Mountschutz verlangt `findmnt` aus der aktuellen Mount-Tabelle des Kernels am angegebenen Mountpunkt genau eine passende, schreibbar eingehängte Quelle. Der nächste vorhandene Elternordner eines neuen Backup-Verzeichnisses muss auf demselben Mount liegen. Dadurch werden auch zusätzliche Mounts im Backup-Pfad erkannt. Das Skript wertet nur numerische Mount-IDs aus und führt keine Befehle aus den abgefragten Werten aus. Die Auswahlmöglichkeiten sind in der [findmnt-Dokumentation](https://github.com/util-linux/util-linux/blob/master/misc-utils/findmnt.8.adoc) beschrieben.

Die erste Mount-ID wird für den Lauf festgehalten. Die Prüfung wird vor wichtigen weiteren Schritten wiederholt: Export, Übertragung, Dump und dessen Veröffentlichung, Konfigurationskopien, Rechteanpassung, Versionsbereinigung und jede dortige Löschung. Eine zwischenzeitlich andere Mount-ID führt auch bei gleicher Quelle zum Abbruch. Nach erkanntem Mountverlust wird eine temporäre Dump-Datei nicht über den möglicherweise inzwischen anders belegten Pfad gelöscht.

Die Kontrolle erfolgt zu bestimmten Zeitpunkten. Sie verhindert nicht jeden Wechsel zwischen Prüfung und Schreibzugriff und kann das Abziehen während eines laufenden Befehls nicht verhindern. Eine unterbrochene Netzwerkverbindung kann trotz vorhandenem Mount-Eintrag Dateizugriffe blockieren; deren Zeitverhalten hängt von Betriebssystem und Mount-Einstellungen ab. Der Schreibtest garantiert weder genügend Platz für das gesamte Backup noch passende Rechte für jede vorhandene Datei. Fehler späterer Sicherungsschritte bleiben deshalb Fehler des gesamten Laufs.
