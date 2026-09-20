# Umstieg auf den steel-raven Fork

Diese Anleitung gilt für die erste Vorabversion `1.1.0~rc1` (Release `v1.1.0-rc1`) und für spätere Updates. Grundlage ist Tommes/toafez' Originalversion `1.0-700`. Eine Übernahme unserer Änderungen in das Original ist für diesen Fork nicht erforderlich.

## 1. Einstellungen erhalten und getrennt testen

Bewahre das bisherige Skript einschließlich deiner Einstellungen unverändert auf. Lade das neue Skript nach der [Installationsanleitung](../README.md#installationshinweise) in einen neuen, leeren Ordner. Ein erneuter Download überschreibt sonst die benutzerspezifischen Angaben in einer gleichnamigen Datei.

Die Vorabversion zuerst mit einer separaten Paperless-Testinstanz und einem eigenen Sicherungsziel prüfen. Auch bei getrennten Sicherungszielen darf sie nicht gleichzeitig mit einer anderen Sicherung derselben Paperless-Instanz laufen: Beide würden deren Exportverzeichnis verändern. Das Skript besitzt noch keine Laufzeitsperre und keinen allgemeinen Probelaufmodus.

## 2. Bisherige Werte übertragen

Kopiere die Werte der folgenden Einstellungen in die entsprechenden Zeilen des neuen Skripts, nicht den gesamten alten Skriptkopf:

- `backup_dir`, `project_dir` und `logfile_name`
- Service- und Containernamen für Paperless-ngx und PostgreSQL
- `postgresql_user` und `postgresql_db`
- `version_history`

`backup_dir` und `project_dir` müssen absolute, getrennte Pfade sein. Sie dürfen nicht ineinander liegen. `version_history` akzeptiert nur `0` oder eine positive ganze Zahl ohne führende Null. Der Protokollname muss ein einfacher Dateiname ohne Verzeichnispfad sein. Neue Einstellungen nicht pauschal mit alten Werten überschreiben.

## 3. Docker-Zuordnung und zusätzliche Dateien prüfen

- **Lokales Compose-Projekt:** `docker_mode="compose"` wählen und bei Bedarf `compose_files`, `compose_env_files` und `compose_project_name` ausfüllen.
- **Portainer beziehungsweise direkte Containerauswahl:** `docker_mode="container"` wählen und beide tatsächlichen Containernamen angeben. Der Fork liest keine Stack-Dateien aus der Portainer-Datenbank. Benötigte Stack-Dateien separat speichern und in `additional_config_files` aufnehmen.
- **Exportverzeichnis:** `export_host_dir` und `export_container_dir` müssen dieselben Daten über einen direkten, schreibbaren Bind-Mount erreichen. Ein benanntes Docker-Volume wird als Exportziel derzeit nicht unterstützt.

Die [Compose-/Portainer-Anleitung](COMPOSE-PORTAINER.md) enthält Beispiele. Im Projektordner werden mehr YAML-/ENV-Varianten als im Original erfasst, darunter `.env`, `.env.production` und `.yml`. Externe Referenzen, Secrets und `env_file`-Verweise werden nicht automatisch vollständig aufgelöst. Solche lokalen Dateien bei Bedarf ausdrücklich angeben. Unterschiedliche Quelldateien gleichen Namens werden abgewiesen, damit keine davon still überschrieben wird.

## 4. Vorhandene Sicherungen und externe Ziele

Neue Versionsordner erhalten nach erfolgreicher Sicherung `.paperless-ngx-backup` mit passendem Inhalt. Nur solche direkten Ordner mit Zeitstempelnamen werden automatisch bereinigt. **Unmarkierte Sicherungen des Originals bleiben erhalten.** Sie werden weder nachträglich gekennzeichnet noch automatisch gelöscht. Plane dafür Speicherplatz ein und bereinige alte Bestände nur nach eigener Prüfung. Kopiere Kennzeichnungsdateien nicht in fremde Ordner.

Der Dateiaufbau mit `export/`, `postgres-dump.sql` und Konfigurationsdateien bleibt grundsätzlich erhalten; `Sicherungsinfo.txt` kommt hinzu. Bestehende Dateien dieses Namens werden nur als frühere Übersicht akzeptiert, wenn ihre Titelzeile passt. Andernfalls bricht der Fork vor dem Export ab, um fremde Daten zu erhalten.

Für USB-Platten und eingebundene SMB-/NFS-Freigaben den [Schutz des Sicherungsziels](BACKUP-TARGET.md) mit `backup_mountpoint` und `backup_mount_source` konfigurieren. Er richtet selbst keine Verbindung oder Einbindung ein.

## 5. Ergebnis prüfen, danach Aufgabenplaner umstellen

Prüfe mit der separaten Testinstanz das Sicherungsprotokoll, den Rückgabecode, die gesicherten Dateien und die Wiederherstellung gemäß [Prüfplan](VALIDATION.md). Unvollständige Sicherungen liefern jetzt einen Fehlerstatus, auch wenn das Original in diesem Fall noch Erfolg gemeldet hat. Fehlende optionale Updatewerkzeuge oder nicht ermittelbare Zusatzversionen sind dagegen Hinweise.

Vor einem späteren produktiven Wechsel den bisherigen Sicherungsjob anhalten und sicherstellen, dass kein Lauf mehr aktiv ist. Erst nach dem manuellen Test den Aufgabenplaner auf den geprüften Skriptpfad umstellen. Das alte Skript als Referenz behalten, aber keinen zweiten aktiven Job für dieselbe Instanz anlegen. Ein Rückwechsel auf das Original bringt dessen frühere Lösch- und Fehlerbehandlung zurück; insbesondere fremde Unterordner im Sicherungsziel wären damit wieder gefährdet.

## Updates dieses Forks

Downloads kommen ausschließlich aus den [Releases von steel-raven](https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases). Die integrierte Prüfung liest die Versionszeile des Skript-Anhangs des neuesten stabilen Releases. Sie ersetzt oder startet keine Skriptdatei. Solange nur Vorabversionen existieren, ist ein übersprungener Updatecheck erwartbar; neue Vorabversionen werden manuell auf der Releases-Seite ausgewählt.

Im Skript heißen Vorabversionen beispielsweise `1.1.0~rc1`, im Git-Tag `v1.1.0-rc1`. Das `~` sorgt beim vorhandenen Versionsvergleich mit `dpkg` dafür, dass die spätere stabile Version `1.1.0` als neuer erkannt wird. Bei jedem Update die eigenen Einstellungen erneut sorgfältig übertragen.
