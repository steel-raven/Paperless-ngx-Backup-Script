# Paperless-ngx Backup-Script – steel-raven Fork

Eigenständig gepflegte Weiterentwicklung des [Originalskripts von Tommes/toafez](https://github.com/toafez/Paperless-ngx-Backup-Script), auf Basis der Version `1.0-700`. Vielen Dank an Tommes für die ursprüngliche Arbeit und die Veröffentlichung unter der MIT-Lizenz. Dieser Fork wird von **steel-raven** betreut; Fragen zu seinen Erweiterungen gehören in dieses Repository.

**Transparenz zur Entwicklung**

Bei der Weiterentwicklung dieses Forks nutze ich OpenAI Codex als KI-Unterstützung. Das betrifft die Analyse und Bearbeitung des Codes, die Erstellung automatisierter Tests sowie die Dokumentation. Veröffentlichung und Pflege des Forks erfolgen durch mich unter dem GitHub-Namen steel-raven.

Die KI-Unterstützung ersetzt keine praktischen Sicherungs- und Wiederherstellungstests. Welche Prüfungen bereits durchgeführt wurden und welche noch ausstehen, ist in der [Projektdokumentation](docs/VALIDATION.md) beschrieben.

**Aktueller Stand: `1.1.0~rc1` / [Vorabversion v1.1.0-rc1](https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases/tag/v1.1.0-rc1).** Die erste Veröffentlichung richtet sich an separate Testinstanzen. Eine vollständige Sicherung und Wiederherstellung mit echtem Docker und `rsync` unter Linux/UGOS steht noch aus. Bitte die [bekannten Grenzen und den Prüfplan](docs/VALIDATION.md) beachten.

Die Erweiterungen umfassen den Erhalt vorheriger Datenbank-Dumps bei Fehlern, aussagekräftige Fehlerstatus und Protokolle, eine auf gekennzeichnete Versionsordner begrenzte Bereinigung, explizite Compose-/Container-Auswahl, Prüfungen der Export- und Sicherungsziele sowie `Sicherungsinfo.txt` je Sicherung.

- [Releases und Downloads](https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases)
- [Umstieg vom Original und spätere Updates](docs/MIGRATION.md)
- [Fehler melden oder Fragen stellen](https://github.com/steel-raven/Paperless-ngx-Backup-Script/issues)

## Worum geht es?
Das Skript sichert den Dokumentexport von Paperless-ngx, einen zusätzlichen PostgreSQL-Dump und die gefundenen beziehungsweise ausdrücklich ausgewählten Konfigurationsdateien. Dafür nutzt es die Exportwerkzeuge von Paperless-ngx und PostgreSQL sowie `rsync` und lokale Dateiwerkzeuge. **Es erstellt kein vollständiges Abbild des Docker-Projekts oder des NAS.** Externe Stack-Dateien, eingebundene Secrets und weitere Dateien müssen bei Bedarf ausdrücklich angegeben werden. Ob die Sicherung für die eigene Installation vollständig ist, muss durch eine Wiederherstellung in einer separaten Testinstanz geprüft werden.

#### _Hinweis: Texte in Großbuchstaben, die sich innerhalb oder außerhalb eckiger Klammern befinden, dienen als Platzhalter und müssen durch eigene Angaben ersetzt werden, können aber an einigen Stellen auch nur der Information dienen. Es ist zu beachten, dass die eckigen Klammern Teil des Platzhalters sind und beim Ersetzen durch eigene Angaben ebenfalls entfernt werden müssen._

## So funktioniert das Skript genau

- **Erstellung eines Datensicherungsprotokolls**  
Nach erfolgreicher Konfigurationsprüfung wird im angegebenen Datensicherungsziel ein neues Protokoll erstellt. Es enthält den Sicherungsverlauf sowie Ausgaben und Fehler der aufgerufenen Programme und wird auch auf der Kommandozeile ausgegeben. Bei einem Abbruch werden der betroffene Schritt und der Rückgabecode ergänzt. Die SQL-Ausgabe von `pg_dump` bleibt ausschließlich in der Dump-Datei. Fehler vor dem Anlegen des Protokolls, etwa bei ungültigen Pfaden, erscheinen auf der Kommandozeile bzw. in der Ausgabe des Aufgabenplaners; ein vorhandenes Protokoll bleibt dann unverändert.

- **Prüfung auf Skript-Updates**
Vor der Sicherung wird die Skriptversion des neuesten **stabilen Releases dieses Forks** auf GitHub abgefragt. Entwicklungsbranches und Vorabversionen werden nicht als Updatequelle verwendet. Solange noch kein stabiles Release existiert oder die Prüfung beispielsweise wegen fehlender Internetverbindung oder eines Zertifikatsfehlers scheitert, erscheint ein Hinweis und die lokale Sicherung wird fortgesetzt. Vorabversionen findest du auf der Releases-Seite. Das Skript lädt niemals selbst ein Update zur Installation und führt den für den Versionsvergleich gelesenen Text nicht aus.

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

- **Versionsübersicht zur Sicherung**
Jeder erfolgreiche Sicherungslauf erzeugt automatisch `Sicherungsinfo.txt` neben Export und Datenbank-Dump, bei Versionsständen im jeweiligen Versionsordner. Darin stehen Zeitpunkt, Skript- und Paperless-Version, PostgreSQL-Server- und `pg_dump`-Version, verwendete Docker-Images und die gesicherten Bestandteile. Die Datei ist einfacher UTF-8-Text mit Linux-Zeilenumbrüchen und lässt sich auf Linux/UGOS mit einem Texteditor oder `cat` lesen. Es sind keine zusätzlichen Einstellungen erforderlich. Nicht ermittelbare Versionsangaben werden mit einem Hinweis gekennzeichnet; Prüfsummen werden nicht erzeugt. Nutzen, Fehlerverhalten und Beispiele erläutert die [Anleitung zur Versionsübersicht](docs/BACKUP-INFO.md).

- **Anpassen der Ordner- und Dateirechte im Sicherungsziel**  
Abschließend werden die Ordner- und Dateirechte im Datensicherungsziel noch an die angegebenen Benutzer- und Gruppenrechte des Paperless-ngx-Verzeichnisses angepasst.

- **Erstellen von Versionen (Bei Bedarf)**  
Wird eine Datensicherung mit Versionsständen verwendet, werden im Datensicherungsziel neue Versionsordner im Format "YYYY-MM-DDTHH-MM-SS" angelegt. Ein bereits vorhandener Ordner gleichen Namens führt zum Abbruch, damit fremde oder frühere Daten nicht übernommen werden.

Nach erfolgreichem Dokumentexport, Datenbank-Dump, Kopieren der gefundenen Konfigurationsdateien, Anpassen der Besitzrechte und Speichern der Versionsübersicht wird der neue Versionsordner mit der Datei `.paperless-ngx-backup` gekennzeichnet. Die automatische Bereinigung erfasst ausschließlich direkte Unterordner mit dem genannten Zeitstempelformat und der passenden Kennzeichnung. Der aktuelle Versionsordner, symbolische Links und unmarkierte Ordner bleiben erhalten. Ist die aktuelle Sicherung unvollständig, findet keine Bereinigung statt.

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

**Sicherst du auf eine USB-Platte oder eine Netzwerkfreigabe, solltest du zusätzlich den optionalen Schutz des Sicherungsziels einschalten.** Fehlt das Medium, kann sein bisheriger Ordner trotzdem existieren. Ohne diese Prüfung könnte das Backup dort auf dem internen NAS-Speicher landen.

| Sicherungsziel | Einstellung |
| --- | --- |
| USB-Platte oder auf dem NAS eingebundene SMB-/NFS-Freigabe | Schutz empfohlen: `backup_mountpoint` und `backup_mount_source` anhand der Anleitung ausfüllen. |
| Normaler Ordner auf einem dauerhaft verfügbaren internen NAS-Volume | Beide neuen Angaben können leer bleiben; der Schutz ist dann ausgeschaltet. |

`backup_mountpoint` bezeichnet den Ordner, an dem das Laufwerk eingebunden ist. `backup_mount_source` benennt die erwartete Platte oder Freigabe. `backup_dir` bleibt dein eigener Sicherungsordner darunter. Die Werte gehören in die vorhandenen Zeilen am Anfang des Skripts. Bei eingeschaltetem Schutz wird zusätzlich `findmnt` aus util-linux benötigt; ein erkanntes fehlendes oder falsches Medium führt zum Abbruch.

Die [Schritt-für-Schritt-Anleitung für USB-Platten und Netzwerkfreigaben](docs/BACKUP-TARGET.md) zeigt, wie du die richtigen Werte auf deinem NAS ermittelst, sie ins Skript überträgst und die erste Sicherung kontrollierst. Sie erklärt auch Fehlermeldungen und das Wechseln von USB-Platten. Diese Funktion prüft den Zielort des fertigen Backups; die Docker-Prüfung des Exportordners ist davon unabhängig.

## Compose, Portainer und Exportpfade

Mit `docker_mode="auto"` wird eine Compose-Datei direkt im Projektverzeichnis verwendet, falls eine vorhanden ist; ansonsten werden die angegebenen Containernamen angesprochen. `docker_mode="compose"` und `docker_mode="container"` legen die Auswahl ausdrücklich fest. Sobald Compose gewählt ist, führen Fehler oder eine mehrdeutige Containerauswahl zum Abbruch statt zu einem Wechsel auf andere Container. Leere Servicenamen auf beiden Seiten wählen im Auto-Modus weiterhin die Containernamen, sofern keine Compose-Dateien ausdrücklich angegeben wurden.

Vor `document_exporter -d` muss `export_container_dir` direkt über einen schreibbaren Bind-Mount mit `export_host_dir` verbunden sein. Nicht passende, verschachtelte oder nur lesbare Export-Mounts werden abgewiesen. Diese Ausführung setzt einen lokalen Linux-Docker-Daemon voraus; entfernte Docker-Daemons, Swarm und Docker-Volumes als Exportziel sind nicht abgedeckt. Standardinstallationen mit dem Bind-Mount `./export:/usr/src/paperless/export` können ihre bisherigen Exportpfade weiterverwenden.

Die neue Prüfung ist bewusst strenger: Früher konnte ein falsch zugeordneter oder veralteter Hostordner kopiert werden, während der Export anderswo landete. Nun muss die Zuordnung vor dem Export stimmen. Konkrete Beispiele für UGOS/Compose, Portainer, externe Konfigurationsdateien und eigene Exportpfade stehen in [Compose-/Portainer-Konfiguration](docs/COMPOSE-PORTAINER.md).

## Installationshinweise
Lade die Datei aus einem Release dieses Forks in einen **neuen, leeren Ordner**, beispielsweise unter deinem Benutzer-Home-Verzeichnis. Überschreibe kein bereits konfiguriertes Skript. Beim Umstieg vom Original zuerst die [Umstiegsanleitung](docs/MIGRATION.md) lesen.

Projekt-, Skript- und Sicherungsverzeichnisse dürfen Leerzeichen enthalten. Pfade beim manuellen Aufruf und in Cron-Einträgen ebenfalls in Anführungszeichen setzen, zum Beispiel `sudo "/volume1/Meine Skripte/Paperless-ngx-Backup-Script.sh"`.

**Download der Shell-Skript-Datei Paperless-ngx-Backup-Script.sh**

	curl --fail --location --output Paperless-ngx-Backup-Script.sh https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases/download/v1.1.0-rc1/Paperless-ngx-Backup-Script.sh
	

Öffne die Datei in einem Texteditor und passe die Einstellungen am Anfang an. Lies dazu die Abschnitte zu Konfiguration, Docker und Sicherungszielen. Erteile der Datei danach im selben Verzeichnis Ausführungsrechte:

	chmod +x Paperless-ngx-Backup-Script.sh

## Skript manuell ausführen
Die Shell-Skript-Datei `Paperless-ngx-Backup-Script.sh` wird auf dem Linux-/NAS-Host ausgeführt, auf dem Docker läuft. Die beschriebenen Aufrufe verwenden Root-Berechtigungen für Docker und die Anpassung der Besitzrechte. **Die Vorabversion zunächst ausschließlich mit separater Paperless-Testinstanz und eigenem Sicherungsziel ausführen.** Der Aufruf erstellt eine Sicherung und kann alte gekennzeichnete Versionen bereinigen; es gibt keinen allgemeinen Probelaufmodus.

Der Aufruf selbst erfolgt am besten, indem man den absoluten Pfad, d.h. den Verzeichnispfad, in dem sich die Shell-Skript-Datei `Paperless-ngx-Backup-Script.sh` befindet, voranstellt, wobei auch der relative Pfad genügt, wenn man sich selbst im selben Verzeichnis wie das Shell-Skript befindet. 

Aufruf mit dem absoluten Pfad:

	sudo "/PFAD/ZUM/SKRIPT/Paperless-ngx-Backup-Script.sh"

Aufruf mit dem relativen Pfad:

	sudo ./Paperless-ngx-Backup-Script.sh


## Skript automatisiert über einen Cron-Job ausführen

Erst nach erfolgreichem manuellem Sicherungs- und Wiederherstellungstest einrichten. Das Skript besitzt noch keine Laufzeitsperre: Es darf für dieselbe Paperless-Instanz nur ein Sicherungslauf gleichzeitig aktiv sein. Manuelle Starts während einer laufenden Aufgabe vermeiden und Intervalle mit ausreichendem Abstand wählen.

Erstelle einen systemweiten Cron-Job, der später mit Root-Berechtigungen ausgeführt wird. Führe dazu den folgenden Befehl aus:

```
sudo crontab -e
```
	
Nach dem Aufruf und der eventuellen Aufforderung, einen bevorzugten Editor zum Bearbeiten der crontab auszuwählen – ich empfehle an dieser Stelle den Editor `nano` – wird an geeigneter Stelle, bestenfalls ganz am Ende des Dokuments, folgender Befehl in abgewandelter Form bzw. nach eigenen Anforderungen eingegeben:

Syntax: 
```
* * * * * bash "/PFAD/ZUM/SKRIPT/Paperless-ngx-Backup-Script.sh"
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
0 6 * * 1,5 bash "/PFAD/ZUM/SKRIPT/Paperless-ngx-Backup-Script.sh"
```

## Beispielausgabe
Nachfolgend ist eine beispielhafte Protokollausgabe auf der Kommandozeile zu sehen, die entsteht, nachdem das Skript ausgeführt wurde. 
```
---------------------------------------------------------------------------------------------------------
Paperless-ngx Datensicherungsprotokoll vom 20.09.2026 um 21:00:00 Uhr
 - Skript: steel-raven Fork 1.1.0~rc1 (https://github.com/steel-raven/Paperless-ngx-Backup-Script)
 - Datensicherungsziel: /volume2/Datensicherung/Paperless-ngx/2026-09-20T21-00-00
 - Mountschutz des Sicherungsziels: ausgeschaltet
---------------------------------------------------------------------------------------------------------

Die integrierte Exportfunktion von Paperless-ngx wird ausgeführt. Bitte warten...
100%|██████████| 2119/2119 [00:02<00:00, 740.58it/s]
 - Das Paperless-NGX-Exportverzeichnis [ /export ] wurde gesichert.
 - Der Dump der PostgreSQL-Datenbank wurde in der Datei [ postgres-dump.sql ] gesichert.
 - Die YAML-Datei [ docker-compose.yaml ] wurde gesichert.
 - Die Ordner- und Dateirechte im Datensicherungsziel wurden auf [ tommes:admin ] gesetzt.
 - Die Versionsübersicht wurde in [ Sicherungsinfo.txt ] gesichert.
 - Versionsstand [ 2026-07-01T21-00-00 ], älter als [ 30 ] Tag(e), wurde gelöscht.

---------------------------------------------------------------------------------------------------------
```

## Versionsgeschichte
- Details zur Versionsgeschichte findest du in der Datei [CHANGELOG](CHANGELOG)

## Regressionstests
Die Tests prüfen Dateinamen, Pfade mit Leerzeichen, fehlgeschlagene Update-Abfragen, Konfigurationsfehler, den Erhalt vorheriger Dumps, Fehlercodes und gespeicherte Diagnosen sowie die Grenzen der Versionsbereinigung in temporären Testverzeichnissen. Hinzu kommen Compose-/Container-Auswahl, externe Konfigurationen, abweichende Exportpfade, fehlende Programme, Schreibtestfehler sowie fehlende, falsche oder während der Sicherung gewechselte Mounts. Für die Versionsübersicht werden Inhalte, fehlende Versionsangaben, Schreibfehler, Namenskonflikte und fehlgeschlagene Folgeläufe geprüft:

```bash
bash tests/regression.sh
```

Docker, Netzwerkzugriffe und Änderungen von Besitzrechten werden simuliert. Dafür sind weder eine laufende Paperless-ngx-Installation noch Root-Rechte erforderlich. Die Tests ersetzen keinen vollständigen Sicherungs- und Wiederherstellungstest auf dem NAS. Tests für symbolische Links werden ausdrücklich als übersprungen gemeldet, falls in der Testumgebung keine solchen Links angelegt werden können.

## Hilfe und Diskussion
- Fehlerberichte und Fragen zu diesem Fork: [GitHub Issues bei steel-raven](https://github.com/steel-raven/Paperless-ngx-Backup-Script/issues). Bitte Skriptversion, Plattform, Installationsart und die bereinigte Fehlermeldung angeben. Keine Passwörter, vollständigen ENV-Dateien oder Datenbank-Dumps veröffentlichen.
- Ursprung und bisherige Diskussion: [Tommes' Thema im UGREEN-Forum](https://ugreen-forum.de/forum/thread/2184-paperless-ngx-backup-script/). Für die Betreuung dieser Weiterentwicklung ist steel-raven zuständig.

## Lizenz
Das Original und die Erweiterungen stehen unter der [MIT-Lizenz](LICENSE). Die Copyright-Angabe von Tommes bleibt erhalten; die Beiträge zu diesem Fork sind zusätzlich gekennzeichnet.
