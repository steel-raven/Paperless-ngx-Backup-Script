# Paperless-ngx Backup-Script

## Worum geht es?
Mithilfe des hier vorgestellten Skripts sollen der Export und die anschließende lokale Sicherung von Datenbankinhalten, Metadaten, Benutzerprofilen, Einstellungen usw. von Paperless-ngx erleichtert werden. Hierzu werden Funktionen genutzt, die sowohl Paperless-ngx als auch PostgreSQL selbst anbieten. Mit rsync werden darüber hinaus weitere wichtige Konfigurationsdateien wie die YAML- und die ENV-Datei gesichert. **Das eigentliche Dockerverzeichnis von Paperless-ngx (z.B. /volume1/docker/Pakerless-ngx) wird dabei jedoch nicht gesichert**, da mit den oben genannten Export-Funktionen und rsync-Aufgaben bereits alle relevanten Daten für eine spätere Wiederherstellung erfasst wurden.

#### _Hinweis: Texte in Großbuchstaben, die sich innerhalb oder außerhalb eckiger Klammern befinden, dienen als Platzhalter und müssen durch eigene Angaben ersetzt werden, können aber an einigen Stellen auch nur der Information dienen. Es ist zu beachten, dass die eckigen Klammern Teil des Platzhalters sind und beim Ersetzen durch eigene Angaben ebenfalls entfernt werden müssen._

## So funktioniert das Skript genau

- **Erstellung eines Datensicherungsprotokolls**  
Nach erfolgreicher Konfigurationsprüfung wird im angegebenen Datensicherungsziel ein neues Protokoll erstellt. Es enthält den Sicherungsverlauf sowie Ausgaben und Fehler der aufgerufenen Programme und wird auch auf der Kommandozeile ausgegeben. Bei einem Abbruch werden der betroffene Schritt und der Rückgabecode ergänzt. Die SQL-Ausgabe von `pg_dump` bleibt ausschließlich in der Dump-Datei. Fehler vor dem Anlegen des Protokolls, etwa bei ungültigen Pfaden, erscheinen auf der Kommandozeile bzw. in der Ausgabe des Aufgabenplaners; ein vorhandenes Protokoll bleibt dann unverändert.

- **Prüfung auf Skript-Updates**
Vor der Sicherung wird die aktuelle Skriptversion auf GitHub abgefragt. Kann diese Prüfung nicht abgeschlossen werden, beispielsweise ohne Internetverbindung, erscheint ein Hinweis im Protokoll und die lokale Datensicherung wird fortgesetzt.

- **Ausführung der integrierten Exportfunktion von Paperless-ngx**  
Zum Exportieren vorhandener Datenbankinhalte, Metadaten, Benutzerprofile und -einstellungen etc. bietet Paperless-ngx mit dem `document_exporter` eine eigene Funktion an. Vor dem Export werden beide laufenden Container und die Zuordnung des Exportverzeichnisses geprüft. Standardmäßig wird der Hostordner `${project_dir}/export` am Containerpfad `/usr/src/paperless/export` erwartet. Beide Pfade lassen sich getrennt konfigurieren. Die exportierten Daten werden dort in einer ZIP-Datei mit der Syntax `export-YYYY-MM-DD.zip` abgelegt.

- **Sicherung des Exportverzeichnis `/export`**  
Nach Abschluss des Exports wird der Inhalt des geprüften Host-Exportordners in `${backup_dir}/export` übertragen. Dieser Name im Sicherungsziel bleibt auch bei abweichenden Quellpfaden gleich.

- **Ausführung der integrierten Exportfunktion (Dump) von PostgreSQL**  
Zum Exportieren der eigentlichen Datenbankinhalte bietet PostgreSQL mit `pg_dump` eine eigene Funktion an. Dabei werden die zu exportierenden Datenbankinhalte direkt ins lokale Datensicherungsziel übertragen und in einer Datei mit der Dateiendung `.sql` gespeichert. Vor der Ausführung dieser Funktion wird zunächst geprüft, ob der PostgreSQL Container von Paperless-ngx läuft, da der Export sonst nicht ausgeführt werden kann.

Der Dump wird zunächst in eine temporäre Datei im selben Sicherungsverzeichnis geschrieben. Nur wenn `pg_dump` erfolgreich endet und die Datei nicht leer ist, ersetzt sie atomar `postgres-dump.sql`. Bei einem Fehler, einem leeren Ergebnis oder einem abgefangenen Abbruchsignal bleibt der bisherige Dump erhalten; die temporäre Datei wird entfernt. Diese Prüfung ersetzt keinen Wiederherstellungstest und macht nicht den gesamten Sicherungssatz atomar: Das Exportverzeichnis wird weiterhin vorher aktualisiert.
 
- **Sicherung des YAML- bzw. Docker-Compose-Datei**  
Alle Dateien mit der Endung `.yaml` oder `.yml` direkt im Docker-Projekt-Verzeichnis werden unter ihrem ursprünglichen Namen gesichert. Dazu gehören beispielsweise `compose.yaml`, `docker-compose.yml` und `compose.override.yaml`, ebenso versteckte Dateien. Groß- und Kleinschreibung der Endung spielt keine Rolle.

- **Sicherung des ENV- bzw. Environment-Datei**  
Direkt im Docker-Projekt-Verzeichnis werden `.env`, `.env.*`, `*.env` und `*.env.*` unter ihrem ursprünglichen Namen gesichert, beispielsweise `.env.production`, `docker-compose.env` und `paperless.env.local`. Auch versteckte Dateien und andere Groß-/Kleinschreibungen werden berücksichtigt. Ausdrücklich verwendete `compose_files`, `compose_env_files` und `additional_config_files` werden unabhängig von Speicherort und Dateiendung ebenfalls gesichert. Zwei unterschiedliche Quelldateien mit gleichem Dateinamen führen vor dem Sicherungslauf zum Abbruch. Verweise wie `env_file`, `include` oder externe Secrets werden nicht automatisch verfolgt; benötigte lokale Dateien müssen in `additional_config_files` angegeben werden.

- **Anpassen der Ordner- und Dateirechte im Sicherungsziel**  
Abschließend werden die Ordner- und Dateirechte im Datensicherungsziel noch an die angegebenen Benutzer- und Gruppenrechte des Paperless-ngx-Verzeichnisses angepasst.

- **Erstellen von Versionen (Bei Bedarf)**  
Wird eine Datensicherung mit Versionsständen verwendet, werden im Datensicherungsziel neue Versionsordner im Format "YYYY-MM-DDTHH-MM-SS" angelegt. Ein bereits vorhandener Ordner gleichen Namens führt zum Abbruch, damit fremde oder frühere Daten nicht übernommen werden.

Nach erfolgreichem Dokumentexport, Datenbank-Dump, Kopieren der gefundenen Konfigurationsdateien und Anpassen der Besitzrechte wird der neue Versionsordner mit der Datei `.paperless-ngx-backup` gekennzeichnet. Die automatische Bereinigung erfasst ausschließlich direkte Unterordner mit dem genannten Zeitstempelformat und der passenden Kennzeichnung. Der aktuelle Versionsordner, symbolische Links und unmarkierte Ordner bleiben erhalten. Ist die aktuelle Sicherung unvollständig, findet keine Bereinigung statt.

**Vorhandene Sicherungen aus älteren Skriptversionen werden nicht automatisch nachträglich gekennzeichnet oder gelöscht.** Sie können nach eigener Prüfung manuell bereinigt werden. Kennzeichnungsdateien dürfen nicht in fremde Ordner kopiert werden. Wie bisher richtet sich das Alter nach der Änderungszeit des Versionsordners (`find -mtime +N`, volle 24-Stunden-Zeiträume), nicht nach seinem Namen.

Ein vollständiger Lauf endet mit Rückgabecode `0`. Fehlende oder gestoppte Container, leere Export-/Dump-Ergebnisse und fehlgeschlagene erforderliche Arbeitsschritte ergeben einen Fehlerstatus. Bei einem unmittelbar abbrechenden externen Befehl wird dessen Rückgabecode weitergegeben, bei einer unvollständigen Sicherung der Code `1`. Eine übersprungene Updateprüfung und nicht vorhandene YAML-/ENV-Dateien bleiben Hinweise und erzeugen für sich allein keinen Fehlerstatus.

## Konfiguration prüfen

Vor der ersten Ausführung müssen die Angaben am Anfang des Skripts angepasst werden. Die Prüfung erfolgt vor dem Erstellen von Verzeichnissen, Überschreiben des Protokolls oder Starten des Exports:

- `project_dir` und `backup_dir` müssen absolute Pfade sein; die voreingestellten Platzhalter sind zu ersetzen. Das Projektverzeichnis muss existieren. Das Sicherungsziel muss ein eigenes Unterverzeichnis sein. Dateisystem-/oberste Wurzelverzeichnisse und kritische Systemverzeichnisse werden abgewiesen.
- Projekt und Sicherungsziel dürfen weder identisch noch ineinander verschachtelt sein. Beim Vergleich werden `..` und vorhandene symbolische Links aufgelöst.
- `version_history` erlaubt `0` oder eine positive ganze Zahl ohne führende Nullen, beispielsweise `30`. Werte wie `30 Tage`, `-1` oder eine leere Angabe werden abgelehnt.
- `logfile_name` muss ein einfacher Dateiname ohne Pfadbestandteile sein. Reservierte Sicherungsnamen und YAML-/ENV-Dateinamen sind ausgeschlossen. Eine vorhandene Protokolldatei darf kein symbolischer Link, Verzeichnis, Hardlink oder das Skript selbst sein.
- Für Paperless-ngx und PostgreSQL muss jeweils mindestens ein gültiger Service- oder Containername angegeben sein. PostgreSQL-Benutzer und Datenbankname dürfen nicht leer sein.

Das Skript verwendet Bash und GNU-Coreutils, für diese Prüfungen und den Dump insbesondere `realpath` mit `-e`/`-m`, `mktemp` und `mv -T`.

## Vorprüfungen und externe Sicherungsziele

Fehlende Pflichtprogramme werden vor dem ersten externen Aufruf gemeldet. Vor dem Export wird außerdem mit eigenen temporären Dateien geprüft, ob sich im Sicherungsziel Dateien anlegen, schreiben, lesen, ersetzen und entfernen lassen. Bei einem Fehler bleiben vorhandene Sicherungsdateien und das bisherige Protokoll unverändert. Fehlende Werkzeuge für die optionale Updateprüfung verhindern das Backup nicht.

Für USB-Platten und Netzwerkfreigaben können `backup_mountpoint` und `backup_mount_source` gemeinsam gesetzt werden. Das Skript verlangt dann am angegebenen Mountpunkt die erwartete Quelle, beispielsweise eine Dateisystem-UUID oder eine SMB-/NFS-Freigabe. Die Prüfung erfolgt vor dem Anlegen des Backup-Ordners und wird vor wichtigen Schreib- und Löschschritten wiederholt. Mit beiden Angaben leer bleibt der Schutz ausgeschaltet. Bei eingeschaltetem Schutz wird zusätzlich `findmnt` aus util-linux benötigt.

Ein vorhandener Ordner allein beweist nicht, dass das gewünschte Medium eingehängt ist. Die Prüfung des Sicherungsmediums ergänzt die separate Docker-Mount-Prüfung des Exportordners. Beispiele, Voraussetzungen und Grenzen stehen unter [Vorprüfungen und externe Sicherungsziele](docs/BACKUP-TARGET.md).

## Compose, Portainer und Exportpfade

Mit `docker_mode="auto"` wird eine Compose-Datei direkt im Projektverzeichnis verwendet, falls eine vorhanden ist; ansonsten werden die angegebenen Containernamen angesprochen. `docker_mode="compose"` und `docker_mode="container"` legen die Auswahl ausdrücklich fest. Sobald Compose gewählt ist, führen Fehler oder eine mehrdeutige Containerauswahl zum Abbruch statt zu einem Wechsel auf andere Container. Leere Servicenamen auf beiden Seiten wählen im Auto-Modus weiterhin die Containernamen, sofern keine Compose-Dateien ausdrücklich angegeben wurden.

Vor `document_exporter -d` muss `export_container_dir` direkt über einen schreibbaren Bind-Mount mit `export_host_dir` verbunden sein. Nicht passende, verschachtelte oder nur lesbare Export-Mounts werden abgewiesen. Diese Ausführung setzt einen lokalen Linux-Docker-Daemon voraus; entfernte Docker-Daemons, Swarm und Docker-Volumes als Exportziel sind nicht abgedeckt. Standardinstallationen mit dem Bind-Mount `./export:/usr/src/paperless/export` können ihre bisherigen Exportpfade weiterverwenden.

Die neue Prüfung ist bewusst strenger: Früher konnte ein falsch zugeordneter oder veralteter Hostordner kopiert werden, während der Export anderswo landete. Nun muss die Zuordnung vor dem Export stimmen. Konkrete Beispiele für UGOS/Compose, Portainer, externe Konfigurationsdateien und eigene Exportpfade stehen in [Compose-/Portainer-Konfiguration](docs/COMPOSE-PORTAINER.md).

## Installationshinweise
Mit Hilfe des Kommandozeilenprogramms `curl` kann die Shell-Skript-Datei **Paperless-ngx-Backup-Script.sh** einfach über ein Terminalprogramm deiner Wahl heruntergeladen werden. Als Speicherort bietet sich das eigene Benutzer-Home-Verzeichnis an, es kann jedoch auch jedes andere erreichbare Verzeichnis verwendet werden. Wechsle in das von dir gewählte Verzeichnis. Führe dann den folgenden Befehl aus. Damit wird die Skriptdatei in das ausgewählte Verzeichnis heruntergeladen.

Projekt-, Skript- und Sicherungsverzeichnisse dürfen Leerzeichen enthalten. Pfade beim manuellen Aufruf und in Cron-Einträgen ebenfalls in Anführungszeichen setzen, zum Beispiel `sudo "/volume1/Meine Skripte/Paperless-ngx-Backup-Script.sh"`.

**Download der Shell-Skript-Datei Paperless-ngx-Backup-Script.sh**

	curl -L -O https://raw.githubusercontent.com/toafez/Paperless-ngx-Backup-Script/refs/heads/main/Paperless-ngx-Backup-Script.sh
	

Führe anschließend im selben Verzeichnis den folgenden Befehl aus, um der Shell-Skript-Datei **Paperless-ngx-Backup-Script.sh** Ausführungsrechte zu erteilen.

	chmod +x Paperless-ngx-Backup-Script.sh

## Skript manuell ausführen
Die Shell-Skript-Datei `Paperless-ngx-Backup-Script.sh` sollte **immer** mit Root-Berechtigungen (d. h. mit vorangestelltem sudo-Befehl) oder als Root selbst ausgeführt werden ausgeführt werden.

Der Aufruf selbst erfolgt am besten, indem man den absoluten Pfad, d.h. den Verzeichnispfad, in dem sich die Shell-Skript-Datei `Paperless-ngx-Backup-Script.sh` befindet, voranstellt, wobei auch der relative Pfad genügt, wenn man sich selbst im selben Verzeichnis wie das Shell-Skript befindet. 

Aufruf mit dem absoluten Pfad:

	sudo /PFAD/ZUM/SKRIPT/Paperless-ngx-Backup-Script.sh

Aufruf mit dem relativen Pfad:

	sudo ./Paperless-ngx-Backup-Script.sh


## Skript automatisiert über einen Cron-Job ausführen

Erstelle einen systemweiten Cron-Job, der später mit Root-Berechtigungen ausgeführt wird. Führe dazu den folgenden Befehl aus:

```
sudo crontab -e
```
	
Nach dem Aufruf und der eventuellen Aufforderung, einen bevorzugten Editor zum Bearbeiten der crontab auszuwählen – ich empfehle an dieser Stelle den Editor `nano` – wird an geeigneter Stelle, bestenfalls ganz am Ende des Dokuments, folgender Befehl in abgewandelter Form bzw. nach eigenen Anforderungen eingegeben:

Syntax: 
```
* * * * * bash /PFAD/ZUM/SKRIPT/DATEINAME.sh
┬ ┬ ┬ ┬ ┬ ┬
│ │ │ │ │ └─ SKript/Kommando
│ │ │ │ └─── Wochentag (0-7, Sonntag ist 0 oder 7)
│ │ │ └───── Monat (1-12)
│ │ └─────── Tag (1-31)
│ └───────── Stunde (0-23)
└─────────── Minute (0-59)

Um mehrere spezifische Werte für eine Aufgabe festzulegen, können Felder wie Stunden, Minuten, Tage, Monate oder Wochentage durch Kommata getrennt werden.
```

Beispiel:
Ausführung des Skripts jeden Montag und Freitag um 6:00 Uhr
```
0 6 * * 1,5 bash /PFAD/ZUM/SKRIPT/paperless-backup.sh
```

## Beispielausgabe
Nachfolgend ist eine beispielhafte Protokollausgabe auf der Kommandozeile zu sehen, die entsteht, nachdem das Skript ausgeführt wurde. 
```
---------------------------------------------------------------------------------------------------------
Paperless-ngx Datensicherungsprotokoll vom 02.01.2026 um 21:00:00 Uhr
 - Datensicherungsziel: /volume2/Datensicherung/Paperless-ngx
---------------------------------------------------------------------------------------------------------

Die integrierte Exportfunktion von Paperless-ngx wird ausgeführt. Bitte warten...
100%|██████████| 2119/2119 [00:02<00:00, 740.58it/s]
 - Das Paperless-NGX-Exportverzeichnis [ /export ] wurde gesichert.
 - Die PostgreSQL-Datenbank wurde in der Datei [ postgres-dump.sql ] gesichert.
 - Die YAML-Datei [ docker-compose.yaml ] wurde gesichert.
 - Die Ordner- und Dateirechte im Datensicherungsziel wurden auf [ tommes:admin ] gesetzt.
 - Versionsstände, die älter als [ 30 ] Tag(e) sind, werden gelöscht.

---------------------------------------------------------------------------------------------------------
```

## Versionsgeschichte
- Details zur Versionsgeschichte findest du in der Datei [CHANGELOG](CHANGELOG)

## Regressionstests
Die Tests prüfen Dateinamen, Pfade mit Leerzeichen, fehlgeschlagene Update-Abfragen, Konfigurationsfehler, den Erhalt vorheriger Dumps, Fehlercodes und gespeicherte Diagnosen sowie die Grenzen der Versionsbereinigung in temporären Testverzeichnissen. Hinzu kommen Compose-/Container-Auswahl, externe Konfigurationen, abweichende Exportpfade, fehlende Programme, Schreibtestfehler sowie fehlende, falsche oder während der Sicherung gewechselte Mounts:

```bash
bash tests/regression.sh
```

Docker, Netzwerkzugriffe und Änderungen von Besitzrechten werden simuliert. Dafür sind weder eine laufende Paperless-ngx-Installation noch Root-Rechte erforderlich. Die Tests ersetzen keinen vollständigen Sicherungs- und Wiederherstellungstest auf dem NAS. Tests für symbolische Links werden ausdrücklich als übersprungen gemeldet, falls in der Testumgebung keine solchen Links angelegt werden können.

## Hilfe und Diskussion
- Hilfe und Diskussionen gerne über das UGREEN Forum - DACH Community [Paperless-ngx Backup-Script](https://ugreen-forum.de/forum/thread/2184-paperless-ngx-backup-script/)

## Lizenz
- MIT License [LICENSE](LICENSE)
