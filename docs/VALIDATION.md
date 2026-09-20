# Prüfstand und Grenzen der Vorabversion

`1.1.0~rc1` ist eine Vorabversion für separate Testinstanzen. Sie enthält die Erweiterungen des steel-raven Forks auf Basis von Tommes/toafez' Version `1.0-700`.

## Automatisierte Prüfungen

Für die erste Vorabversion bestanden lokal unter Git for Windows alle ausführbaren Regressionstests; drei Symlink-Testgruppen wurden dort übersprungen. Der [Linux-Lauf des Veröffentlichungsbranches](https://github.com/steel-raven/Paperless-ngx-Backup-Script/actions/runs/35536956618) bestand **192 Prüfungen, ohne Fehler und ohne übersprungene Fälle**, einschließlich der Symlink-Prüfungen. Bash-Syntax und die Versionsreihenfolge wurden ebenfalls erfolgreich geprüft.

Die [GitHub-Aktion](https://github.com/steel-raven/Paperless-ngx-Backup-Script/actions/workflows/regression.yml) prüft auf Ubuntu die Bash-Syntax, die Versionsreihenfolge und die isolierten Regressionstests. Ein übersprungener Test lässt den Linux-Lauf fehlschlagen. Die Tests verwenden echte lokale Testdateien, ersetzen aber Docker, Netzwerk, `rsync`, Mountabfragen und Besitzrechtsänderungen durch Testfunktionen. Sie greifen nicht auf produktive Sicherungen zu.

Lokaler Aufruf mit Bash und GNU-Dateiwerkzeugen:

```bash
bash -n Paperless-ngx-Backup-Script.sh
bash -n tests/regression.sh
bash tests/regression.sh
```

Unter Git for Windows können Symlink-Fälle übersprungen werden; das wird ausdrücklich ausgegeben. Die Ergebnisse eines konkreten Releases stehen in dessen Releasebeschreibung. Ein erfolgreicher Linux-Regressionstest ist kein Nachweis einer erfolgreichen Sicherung und Wiederherstellung mit echtem Paperless-ngx.

## Vor einer stabilen Freigabe noch zu prüfen

In einer separaten Linux-/UGOS-Testumgebung mit entbehrlichen Testdokumenten:

1. Eine Compose-Installation mit lokalem Docker-Daemon und direkten Bind-Mounts sichern; zusätzlich die direkte Containerauswahl mit einer Portainer-Testinstallation prüfen. Verwendete Plattform-, Docker-, Paperless- und PostgreSQL-Versionen festhalten.
2. Export, Dump, YAML-/ENV-Dateien und `Sicherungsinfo.txt` auf Vollständigkeit und passende Versionen prüfen. Effektive Dateirechte einschließlich NAS-ACLs mit einem unberechtigten Testkonto kontrollieren.
3. Den Dokumentexport nach der [offiziellen Importanleitung](https://docs.paperless-ngx.com/administration/#importer) in eine leere, separate Instanz mit passender Paperless-Version importieren. Dokumente, Benutzer und Metadaten vergleichen. PostgreSQL-Dump separat als zusätzlichen Wiederherstellungsweg prüfen; Exportimport und SQL-Dump nicht ungeprüft nacheinander in dieselbe Datenbank einspielen.
4. Fehlgeschlagene Dumps, volle beziehungsweise schreibgeschützte Testziele und fehlende Container prüfen: Fehlerstatus, verständliches Protokoll, erhaltener vorheriger Dump und keine Versionsbereinigung. Zusätzlich das Kopierverhalten mit echtem `rsync` und Pfaden mit Leerzeichen prüfen.
5. Versionsbereinigung ausschließlich mit künstlichen Sicherungen testen: alter gekennzeichneter Versionsordner wird entfernt; unmarkierte Ordner, fremde Namen, Links und der aktuelle Stand bleiben erhalten. Bei einer fehlgeschlagenen Sicherung wird nichts bereinigt.
6. Für externe Ziele getrennte Testmedien verwenden: richtige Quelle, fehlendes Medium, falsche Quelle und ein schreibgeschütztes Ziel. Keine produktiven Laufwerke für Fehlersimulationen abziehen oder umhängen.

Ergebnisse mit Plattform, Versionsständen, Datum und erfolgreicher Wiederherstellung dokumentieren. Bis dahin bleibt das Release als Vorabversion gekennzeichnet.

## Bekannte Grenzen

- **Keine Laufzeitsperre:** Für dieselbe Paperless-Instanz darf nur ein Lauf gleichzeitig aktiv sein, auch bei unterschiedlichen Sicherungszielen.
- **Kein atomarer Gesamtsicherungssatz:** Der alte SQL-Dump wird bei Dumpfehlern erhalten, der Dokumentexport kann zu diesem Zeitpunkt aber bereits aktualisiert worden sein. Export und Dump entstehen nacheinander. Insbesondere bei gleichzeitigen Änderungen in Paperless entsteht dadurch kein garantierter gemeinsamer Datenbankzeitpunkt.
- **Kein allgemeiner Probelaufmodus:** Ein normaler Aufruf verändert Export und Sicherungsziel und kann alte gekennzeichnete Versionsordner löschen. Die Vorabversion deshalb zuerst getrennt testen.
- **Begrenzte Docker-Unterstützung:** Lokaler Linux-Daemon mit direktem, schreibbarem Bind-Mount für den Export; keine Freigabe für Swarm, entfernte Daemons oder benannte Docker-Volumes als Exportziel.
- **Keine vollständige automatische Konfigurationserfassung:** Externe Dateien und Secrets müssen ausdrücklich angegeben werden. Der Fork erstellt kein NAS- oder Docker-Volume-Abbild.
- **Mountschutz mit Zeitgrenzen:** Ein Wechsel zwischen Prüfung und Dateizugriff oder blockierende Netzwerkdateisysteme können nicht vollständig abgefangen werden. Details stehen in [BACKUP-TARGET.md](BACKUP-TARGET.md).
- **Rechte und Speicherplatz:** Die tatsächlichen Linux-/NAS-Rechte und ausreichender Platz müssen vor Ort geprüft werden. Der Schreibtest garantiert weder vollständige Kapazität noch passende ACLs für alle Daten.
