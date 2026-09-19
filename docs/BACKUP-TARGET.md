# Vorprüfungen und externe Sicherungsziele

Das Skript prüft vor dem Export die benötigten Programme, die Konfiguration, die beiden Docker-Container und den Export-Mount. Zusätzlich testet es im Sicherungsziel das Anlegen, Schreiben, Lesen, Ersetzen und Entfernen eigener temporärer Dateien. Ein Fehler verhindert den Export und die Versionsbereinigung.

Der Schreibtest findet in einem zufällig benannten Verzeichnis `.paperless-preflight.*` unter `backup_dir` statt. Er verändert keine vorhandenen Sicherungsdateien. Das Verzeichnis wird auch nach einem abgefangenen Fehler oder Signal entfernt, soweit das Medium noch erreichbar und das Löschen möglich ist. Andernfalls erscheint ein Hinweis mit dem verbliebenen Pfad. Ein nicht abfangbarer Abbruch, beispielsweise ein Stromausfall, kann ebenfalls einen solchen Ordner zurücklassen.

Ein vorhandenes Protokoll wird erst nach diesen Vorprüfungen ersetzt. Frühere Fehler erscheinen auf der Kommandozeile beziehungsweise in der Ausgabe des Aufgabenplaners. Das ist insbesondere dann nötig, wenn das Sicherungsmedium fehlt und dort kein neues Protokoll geschrieben werden kann.

## Voraussetzungen

Erforderlich sind Bash ab Version 4, Docker, `rsync` und die üblichen GNU-Dateiwerkzeuge. Vor dem ersten externen Aufruf wird geprüft, ob `dirname`, `date`, `realpath`, `stat`, `mkdir`, `rmdir`, `tee`, `docker`, `ls`, `rsync`, `mktemp`, `mv`, `cp`, `chown` und `rm` gefunden werden. Bei aktivierter Versionsbereinigung kommen `find` und `cat` hinzu.

Die Optionen von `realpath` (`-e`, `-m`), `stat` (`-c`) und gegebenenfalls `find` (`-maxdepth`, `-mtime`) werden lesend geprüft. Der Schreibtest prüft auch das für den Dump benötigte Ersetzen mit `mv -T`. Compose wird nur im Compose-Modus benötigt; Fehler beim Auflösen der Services oder beim Zugriff auf die Container verhindern den Export.

`wget`, `grep`, `cut` und `dpkg` gehören zur optionalen Updateprüfung. Fehlt eines dieser Programme oder schlägt die Abfrage beziehungsweise der Versionsvergleich fehl, wird die Prüfung mit einem Hinweis übersprungen. Das Backup läuft weiter. Das Skript installiert keine Programme und ändert keine Docker-Berechtigungen.

## Warum reicht ein vorhandener Backup-Ordner nicht?

Ist eine USB-Platte beispielsweise unter `/media/USB` eingehängt, zeigt `/media/USB/Paperless` auf die Platte. Ohne die Platte kann derselbe Pfad auf dem internen Dateisystem liegen. Ein vorhandener Ordner oder ein erfolgreicher Schreibtest erkennt diesen Unterschied nicht.

Für solche Ziele können am Anfang des Skripts zwei zusätzliche Angaben gesetzt werden:

```bash
backup_dir="/media/USB/Paperless"
backup_mountpoint="/media/USB"
backup_mount_source="UUID=12345678-1234-1234-1234-123456789abc"
```

Die UUID ist ein Beispiel und muss durch die tatsächliche Dateisystem-UUID ersetzt werden. `backup_dir` muss unterhalb des Mountpunkts liegen; der gesamte Mountpunkt ist kein zulässiges Backup-Verzeichnis. Beide neuen Angaben müssen gemeinsam gesetzt werden. Mit beiden Werten leer bleibt der Schutz ausgeschaltet und es wird kein `findmnt` benötigt:

```bash
backup_mountpoint=""
backup_mount_source=""
```

## Die richtige Quelle feststellen

Während die gewünschte Platte oder Freigabe korrekt eingehängt ist, kann sie lesend angezeigt werden:

```bash
findmnt --kernel --mountpoint "/media/USB" --output TARGET,SOURCE,FSTYPE,UUID,OPTIONS
```

Vergleiche die Ausgabe mit dem gewünschten Datenträger. Bei USB-Platten eignet sich `UUID=...` besser als ein wechselnder Gerätename wie `/dev/sdb1`. Bei SMB- oder NFS-Freigaben wird die angezeigte Quelle verwendet, beispielsweise:

```bash
backup_dir="/mnt/NAS Backup/Paperless"
backup_mountpoint="/mnt/NAS Backup"
backup_mount_source="//backup-server/Backup"
# Bei NFS beispielsweise: backup_mount_source="backup-server:/exports/Backup"
```

Leerzeichen in Pfaden oder Freigaben sind erlaubt; die Werte müssen wie im Beispiel in Anführungszeichen stehen. Zugangsdaten gehören nicht in diese Angaben. Die Freigabe muss bereits vom System eingehängt sein. Das Skript ruft weder `mount` noch `umount` auf.

## Was wird geprüft?

Bei eingeschaltetem Schutz wird `findmnt` aus util-linux benötigt. Das Skript fragt die aktuelle Mount-Tabelle des Kernels ab und verlangt am angegebenen Mountpunkt genau eine passende, schreibbar eingehängte Quelle. Es wertet nur numerische Mount-IDs aus; Dateinamen und Freigabeangaben werden als einzelne Argumente übergeben. Die Unterschiede zwischen `--mountpoint`, `--target` und der Auswahl mit `--source` beschreibt die [findmnt-Dokumentation](https://github.com/util-linux/util-linux/blob/master/misc-utils/findmnt.8.adoc).

Der nächste vorhandene Elternordner eines noch nicht angelegten Backup-Verzeichnisses muss auf demselben Mount liegen. Dadurch werden fehlende Medien, falsche Quellen und zusätzliche Mounts innerhalb des Backup-Pfads erkannt, bevor ein Backup-Verzeichnis oder Protokoll angelegt wird. Eine fehlgeschlagene oder mehrdeutige Abfrage führt ebenfalls zum Abbruch.

Die erste Mount-ID wird für den Lauf festgehalten. Die Prüfung wird vor wichtigen weiteren Schritten wiederholt, insbesondere vor dem Export, der Exportübertragung, dem Dump und dessen Veröffentlichung, den Konfigurationskopien, der Rechteanpassung sowie der Versionsbereinigung und jeder dortigen Löschung. Ein neu eingehängtes Medium mit anderer Mount-ID wird auch dann abgewiesen, wenn seine Quelle gleich lautet. Nach erkanntem Mountverlust wird eine noch vorhandene temporäre Dump-Datei nicht über den möglicherweise inzwischen anders belegten Pfad gelöscht.

## Grenzen und Tests

Dies ist eine Prüfung an bestimmten Zeitpunkten, keine Sperre des Datenträgers. Sie verhindert weder das Abziehen während eines laufenden Befehls noch jeden Wechsel zwischen Prüfung und Schreibzugriff. Eine unterbrochene Netzwerkverbindung kann trotz vorhandenen Mount-Eintrags einen Dateizugriff blockieren; dessen Zeitverhalten hängt von Betriebssystem und Mount-Einstellungen ab. Der Schreibtest garantiert außerdem weder ausreichend freien Platz für das gesamte Backup noch passende Rechte für jede bereits vorhandene Datei. Fehler der anschließenden Sicherungsschritte bleiben deshalb weiterhin Fehler des gesamten Laufs.

Die automatisierten Regressionstests simulieren fehlende Programme, Schreib- und Umbenennungsfehler, fehlende oder falsche Medien, schreibgeschützte Mounts und Mountwechsel während der Sicherung. Sie prüfen außerdem, dass vorhandene Protokolle und alte Sicherungsstände bei frühen Fehlern erhalten bleiben. Echte Mounts und Docker-Aufrufe werden dabei nicht ausgeführt.

Vor produktiver Nutzung sollte auf einem separaten Linux-Testsystem geprüft werden: korrektes Medium, nicht eingehängtes Medium bei weiterhin vorhandenem Mountordner, falsche Platte beziehungsweise Freigabe, schreibgeschütztes Ziel und anschließende Wiederherstellung einer erfolgreichen Sicherung. Produktive Datenträger sollten für solche Fehlerfalltests nicht während einer Sicherung entfernt werden.
