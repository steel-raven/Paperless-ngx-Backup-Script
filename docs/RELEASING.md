# Releases dieses Forks pflegen

Veröffentlichungsziel ist ausschließlich `steel-raven/Paperless-ngx-Backup-Script`. Das Original von Tommes/toafez bleibt über den Remote `upstream` nachvollziehbar. Die vorhandenen Upstream-PR-Branches bleiben für eine mögliche Übernahme erhalten.

## Vorbereitung

1. Änderungen auf einem eigenen Branch auf Basis des aktuellen Forks vorbereiten. Skriptversion, Regressionserwartungen, README, Beispiele, CHANGELOG und Releasebeschreibung gemeinsam aktualisieren.
2. Versionsschema beibehalten: stabile Skriptversion `X.Y.Z`, Vorabversion `X.Y.Z~rcN`. Git-Tags heißen `vX.Y.Z` beziehungsweise `vX.Y.Z-rcN`. Dadurch sortiert `dpkg` die Vorabversion vor der stabilen Version.
3. Bash-Syntax, `git diff --check` und die Regressionstests prüfen. Der Linux-Lauf auf GitHub muss einschließlich Symlink-Fällen erfolgreich sein. Reale Plattform-/Wiederherstellungstests mit Versionsständen getrennt dokumentieren.
4. Nur die beabsichtigten Dateien versionieren. Lokale Prüfnotizen, Testartefakte, Konfigurationen und Zugangsdaten nicht veröffentlichen. Copyright-Angaben und vollständigen MIT-Lizenztext erhalten, auch im einzeln herunterladbaren Skript.

## Veröffentlichung

- Den geprüften Commit ohne Umschreiben bestehender Historie in den `main`-Branch des Forks übernehmen.
- Den Release-Tag exakt auf diesen Commit setzen. Releasebeschreibung aus `docs/releases/` verwenden.
- **Vorabversionen ausdrücklich als Pre-release kennzeichnen und nicht als Latest setzen.** Eine stabile Freigabe erfordert zuvor die Prüfungen in [VALIDATION.md](VALIDATION.md).
- Das unveränderte Skript aus dem getaggten Commit unter dem Assetnamen **`Paperless-ngx-Backup-Script.sh`** anhängen, ebenso `LICENSE`. GitHub stellt zusätzlich Quellcodearchive mit Dokumentation und Tests bereit.
- Bei einem stabilen Release den Latest-Status korrekt setzen und den Assetnamen beibehalten: Die Updateprüfung liest `releases/latest/download/Paperless-ngx-Backup-Script.sh`. Ein fehlender Anhang führt zu einem übersprungenen Updatecheck.
- Release, Tag, Commit, Vorabstatus und herunterladbare Dateien anschließend prüfen. Veröffentlichte Tags und Anhänge nicht still durch andere Inhalte ersetzen; Korrekturen erhalten eine neue Version.

## Kommunikation

Releasebeschreibung und README nennen Nutzen, Umstieg und tatsächlich geprüfte Plattformen. Simulierte Docker-/Dateifehler nicht als erfolgreichen echten NAS-Restore darstellen. Fragen und Fehlerberichte zu diesem Fork werden in dessen Issues betreut. Eine Ankündigung im Forum erfolgt getrennt nach Freigabe des Beitragstexts.
