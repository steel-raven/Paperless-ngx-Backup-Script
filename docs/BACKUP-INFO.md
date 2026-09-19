# Versionsübersicht einer Sicherung

## Wozu dient sie?

Nach einer erfolgreichen Sicherung liegt neben `export/` und `postgres-dump.sql` eine Datei **`Sicherungsinfo.txt`**. Sie zeigt, mit welchen Programmversionen die Sicherung erstellt wurde. Du brauchst dafür nichts einzustellen.

Das hilft zum Beispiel, wenn dein NAS ersetzt werden muss: Du kannst nachsehen, welche Paperless-Version zur Sicherung gehört, statt zunächst mit der gerade neuesten Version einen Import zu versuchen. Auch bei Supportfragen sind diese Angaben hilfreich.

Die Endung `.txt` funktioniert unter Linux und UGOS genauso wie unter Windows. Die Datei enthält einfachen UTF-8-Text mit Linux-Zeilenumbrüchen (LF). Sie ist kein auszuführendes Skript. Du kannst sie mit einem Texteditor oder über das NAS-Terminal lesen:

```bash
cat "/volume1/Meine Sicherungen/Paperless/Sicherungsinfo.txt"
```

Ersetze den Beispielpfad durch deinen Sicherungsordner. Bei eingeschalteten Versionsständen liegt die Datei im jeweiligen Ordner, zum Beispiel `2026-09-19T12-34-56/Sicherungsinfo.txt`. Ohne Versionsstände wird die Übersicht bei jedem erfolgreichen Lauf neu erstellt.

## Was steht darin?

Ein gekürztes Beispiel mit **frei gewählten Beispielversionen**:

```text
Sicherungsbeginn: 2026-09-19T12:34:56+0200
Datenübertragung abgeschlossen: 2026-09-19T12:38:10+0200
Skriptversion: 1.0-700
Paperless-ngx-Version: 2.20.0
PostgreSQL-Serverversion (aus Dump): 16.4 (Debian 16.4-1)
pg_dump-Version (aus Dump): 17.6

Paperless-ngx-Image: ghcr.io/paperless-ngx/paperless-ngx:latest
PostgreSQL-Image: postgres:16
```

- **Zeitangaben:** Beginn der Sicherung und Abschluss der Datenübertragung. `+0200` bedeutet zwei Stunden vor UTC; verwendet wird die Zeitzone des NAS. Besitzrechte und Bereinigung werden anschließend bearbeitet.
- **Skriptversion:** Die Versionsangabe aus dem ausgeführten Skript. Sie identifiziert keine individuellen Änderungen am Skript.
- **Paperless-ngx-Version:** Aus der Versionsdatei im verwendeten Paperless-Container gelesen, ohne die Anwendung zu initialisieren. Dafür wird dessen vorhandenes Python verwendet; auf dem NAS-Host wird kein Python benötigt oder installiert.
- **PostgreSQL-Serverversion:** Die Version der Datenbank, aus der der gesicherte Dump erstellt wurde.
- **pg_dump-Version:** Die Version des Exportwerkzeugs. Sie kann sich von der Serverversion unterscheiden. Beide Angaben werden aus dem Kopf der gesicherten SQL-Datei gelesen, ohne zusätzliche Datenbankverbindung.
- **Docker-Images:** Die im jeweiligen Container hinterlegten Image-Namen. Ein Tag wie `latest` oder `16` kann später auf ein anderes Image zeigen und ist daher keine genaue Versionsangabe.

Darunter werden `export/`, `postgres-dump.sql` und die tatsächlich kopierten Konfigurationsdateien aufgelistet. Inhalte der Konfigurationsdateien, Passwörter, Docker-Umgebungsvariablen und SQL-Daten werden nicht in die Übersicht übernommen. Die Versionsabfragen benötigen keine Internetverbindung und verändern die Container nicht.

## Was passiert bei Fehlern?

Kann eine zusätzliche Versionsangabe nicht gelesen werden, steht dort **`nicht ermittelbar`**. Im Protokoll erscheint ein Hinweis. Ein ansonsten erfolgreiches Backup wird dadurch nicht verhindert. Das kann beispielsweise bei einem anders aufgebauten Paperless-Image vorkommen.

Kann die Übersicht selbst nicht erstellt oder gespeichert werden, endet der Lauf mit einem Fehlerstatus; alte Versionsstände werden dann nicht bereinigt. Die Übersicht wird zunächst in eine temporäre Datei geschrieben, erhält die gleichen Besitzrechte wie die übrige Sicherung und wird erst danach an ihren endgültigen Platz verschoben.

Ohne Versionsstände entfernt das Skript die bisherige Übersicht unmittelbar vor der möglichen Änderung der Sicherungsdaten. Schlägt der neue Lauf fehl, bleibt dadurch keine alte Versionsangabe neben einem möglicherweise teilweise aktualisierten Backup stehen. Scheitert bereits eine Vorprüfung, bevor Daten verändert werden, kann die frühere Übersicht unverändert erhalten bleiben. Vorhandene Links, Hardlinks oder Verzeichnisse namens `Sicherungsinfo.txt` werden vor dem Export abgewiesen. Eine vorhandene reguläre Datei muss an ihrer Titelzeile als frühere Übersicht erkennbar sein; andernfalls wird ebenfalls abgebrochen. Dieser Name ist außerdem für Protokolle und zusätzliche Konfigurationsdateien reserviert.

Der Gesamtstatus steht weiterhin im Sicherungsprotokoll und im Rückgabecode. Bei abgefangenen Fehlern wird eine schon veröffentlichte Übersicht wieder entfernt, sofern das Sicherungsmedium noch verfügbar ist. Nach Stromausfall, einem nicht abfangbaren Prozessabbruch oder Verlust des Mediums kann diese Aufräumarbeit nicht garantiert werden. Allein das Vorhandensein der Datei ist deshalb kein Erfolgsnachweis.

## Was bringt sie bei einer Wiederherstellung?

Nutze die Paperless-Version als Ausgangspunkt für den Dokumentimport. Beachte die [offizielle Anleitung zum document_importer](https://docs.paperless-ngx.com/administration/#importer). Der Paperless-Export und der zusätzliche PostgreSQL-Dump sind unterschiedliche Wiederherstellungswege; sie werden nicht einfach nacheinander eingespielt.

Die Übersicht ist eine Hilfe zur Zuordnung der Sicherung. **Sie prüft keine Dateiinhalte und ersetzt keinen Wiederherstellungstest.** Prüfsummen werden nicht erzeugt. Bewahre mehrere Sicherungsstände auf, wenn du auch nach einem fehlgeschlagenen Folgelauf auf einen früheren Stand zurückgreifen möchtest.

## Technischer Umfang für den Projektbetreuer

Die Änderung ergänzt eine Informationsdatei ohne neue Benutzereinstellungen oder zusätzliche Pflichtprogramme auf dem Host. Die Abfragen verwenden dieselben bereits ermittelten Container-IDs wie Export und Dump. Es werden nur die Paperless-Versionsangabe, das Docker-Feld `Config.Image` und die beiden Versionszeilen aus einem begrenzten Ausschnitt des Dump-Kopfs gelesen. Unbekannte Werte bleiben ausdrücklich unbekannt; aus Image-Tags wird keine Programmversion abgeleitet.

Die Dateierstellung ist vor der automatischen Versionsbereinigung eingeordnet und verwendet die vorhandenen Mountprüfungen. Die Übersicht macht den gesamten Sicherungssatz nicht atomar. Die Tests simulieren Docker, Dateifehler und Mountwechsel; ein Test auf einem echten Linux-/UGOS-System mit Wiederherstellung bleibt erforderlich.
