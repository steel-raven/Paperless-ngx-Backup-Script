# Compose, Portainer und abweichende Pfade

Diese Beispiele ergänzen die Pflichtangaben am Anfang von `Paperless-ngx-Backup-Script.sh`. Passe insbesondere Projekt, Sicherungsziel, Container, PostgreSQL-Benutzer und Datenbank an deine Installation an. Es werden weder Container angelegt noch gestartet, gestoppt oder neu bereitgestellt.

## Welche Betriebsart passt?

| `docker_mode` | Auswahl |
| --- | --- |
| `auto` (Standard) | Lokale Compose-Datei verwenden, wenn vorhanden; andernfalls die konfigurierten Containernamen. Sind beide Servicenamen leer und keine Compose-Dateien angegeben, werden ebenfalls die Containernamen verwendet. |
| `compose` | Compose-Dateien und Servicenamen verwenden. Fehlende Dateien, Fehler oder mehrere Container für einen Service führen zum Abbruch. |
| `container` | Die beiden Containernamen oder IDs direkt verwenden. Geeignet für Portainer ohne lokale Compose-Datei; das Compose-Plugin ist dafür nicht erforderlich. |

Beide Container müssen laufen, bevor der Export beginnt. Nach der Auswahl werden Export und Dump mit `docker exec` über die geprüften Container-IDs ausgeführt, ohne TTY-Option. Ein fehlerhafter Compose-Lauf wechselt nicht zu möglicherweise anderen Containern.

## UGOS beziehungsweise lokales Compose-Projekt

```bash
project_dir="/volume1/docker/paperless-ngx"
backup_dir="/volume2/Backups/Paperless"
docker_mode="compose"
project_service_name="webserver"
postgres_service_name="db"

compose_files=()
compose_project_name=""
compose_env_files=()
export_host_dir=""
export_container_dir="/usr/src/paperless/export"
additional_config_files=()
```

Bei leerem `compose_files` wird direkt in `project_dir` die erste vorhandene Datei dieser Reihenfolge gewählt: `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`. Dazu kommt die erste vorhandene Standard-Override-Datei: `compose.override.yaml`, `compose.override.yml`, `docker-compose.override.yaml`, `docker-compose.override.yml`. Dateien in übergeordneten Verzeichnissen werden nicht gesucht.

Ein leerer `export_host_dir` bedeutet `${project_dir}/export`. Dieser Ordner muss im laufenden Container direkt und schreibbar nach `/usr/src/paperless/export` eingebunden sein, zum Beispiel mit `./export:/usr/src/paperless/export`.

## Eigenes Compose-Projekt mit mehreren Dateien

```bash
docker_mode="compose"
compose_files=("compose.yaml" "overrides/production.yaml")
compose_project_name="paperless-production"
compose_env_files=("variables/base.env" "/volume1/config/paperless-production.env")
additional_config_files=("config/service-settings.conf")
```

Relative Dateipfade beziehen sich auf `project_dir`, auch wenn du das Skript von einem anderen Verzeichnis aus startest. Die Listen bleiben in der angegebenen Reihenfolge erhalten. `project_dir` wird als `--project-directory` übergeben und muss dem Basisverzeichnis deiner Bereitstellung entsprechen. Ein ausdrücklich gewählter Projektname muss zum bereits laufenden Stack passen. Docker beschreibt diese Optionen und die Zusammenführung mehrerer Dateien in der [Compose-CLI-Dokumentation](https://docs.docker.com/reference/cli/docker/compose/).

Ohne `compose_env_files` wird nur die `.env` direkt in `project_dir` verwendet, falls vorhanden; andernfalls wird `/dev/null` als leere Variablendatei übergeben. Geerbte Shell-Werte für `COMPOSE_FILE`, `COMPOSE_PROJECT_NAME` und `COMPOSE_ENV_FILES` werden beim Compose-Aufruf entfernt. Ein Projektname aus der ausgewählten Compose-Datei oder `.env` bleibt möglich; `compose_project_name` hat als ausdrückliche Angabe Vorrang.

`compose_env_files` enthält Dateien zur Variablenersetzung durch Compose. Das ist etwas anderes als `env_file` innerhalb eines Services. Dateien aus solchen Verweisen sowie aus `include` oder Secret-Dateipfaden werden nicht automatisch zur Sicherung hinzugefügt. Trage die benötigten lokalen Dateien zusätzlich in `additional_config_files` ein. Die Unterscheidung erläutert die [Docker-Dokumentation zur Variablenersetzung](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/).

## Portainer ohne lokale Compose-Datei

```bash
project_dir="/volume1/docker/paperlessngx"
backup_dir="/volume2/Backups/Paperless"
docker_mode="container"
project_container_name="paperlessngx"
postgres_container_name="paperlessngx-db"

compose_files=()
compose_project_name=""
compose_env_files=()
additional_config_files=(
    "/volume1/config/portainer-paperless-stack.yaml"
    "/volume1/config/portainer-paperless-variables.env"
)
```

Die Dateien unter `/volume1/config/` müssen tatsächlich vorhanden und aktuell sein. Speichere dort selbst die Stack-Definition und gegebenenfalls die für die Wiederherstellung nötigen separaten Variablen. Bei einem über den Web-Editor angelegten Stack findest du die Definition im Editor; bei Git-Stacks ist das Repository maßgeblich. Siehe [Portainer: Stack ansehen und bearbeiten](https://docs.portainer.io/user/docker/stacks/edit).

Das Skript liest weder die Portainer-Datenbank noch dessen interne Stack-Verzeichnisse aus und rekonstruiert keine Stack-Datei aus Container-Umgebungsvariablen. Es benötigt keinen Portainer-API-Schlüssel. Ohne lokale Konfigurationsdateien sind Export und Dump weiterhin möglich; das Protokoll weist auf die fehlende Konfigurationssicherung hin.

## Exportordner liegt anderswo

Wenn dein laufender Container beispielsweise diese Einbindung verwendet:

```yaml
volumes:
  - "/volume1/Exports/Paperless:/backup-export"
```

lauten die passenden Angaben:

```bash
export_host_dir="/volume1/Exports/Paperless"
export_container_dir="/backup-export"
```

Der erste Pfad liegt auf dem Docker-Host, der zweite im Container. Das Skript liest die Mount-Metadaten des ausgewählten Containers und vergleicht die aufgelösten Hostpfade. Der Hostordner muss schon existieren. Ein fehlender oder falscher Mount, ein nur lesbarer Mount oder ein weiterer Mount unterhalb des Container-Exportpfads führt vor `document_exporter -d` zum Abbruch. Enthält der Exportordner Hostdaten eines weiteren Bind-Mounts, wird ebenfalls abgebrochen.

Verwende einen eigenen Ordner ausschließlich für Exporte. Die bekannten Paperless-Verzeichnisse `data`, `media` und `consume` sowie deren Unterordner sind keine Exportziele. Der Exporter kann mit `-d` alte Dateien entfernen; die [Paperless-Dokumentation zum Exporter](https://docs.paperless-ngx.com/administration/#exporter) erläutert dieses Verhalten.

Das Backup enthält weiterhin `export/`, `postgres-dump.sql` und die ausgewählten Konfigurationsdateien. Ein anderer Name des Host-Exportordners verändert diese Struktur nicht.

## Welche Konfigurationsdateien landen im Backup?

Zusätzlich zu den üblichen YAML-/ENV-Dateien direkt im Projektverzeichnis werden alle ausgewählten Compose-, Compose-Variablen- und zusätzlichen Konfigurationsdateien kopiert, auch aus Unterverzeichnissen und mit anderen Dateiendungen. Ihre ursprünglichen Dateinamen bleiben erhalten. Dieselbe Datei mit gleichem Namen wird nur einmal kopiert.

Weil die Dateien im Sicherungsziel nebeneinander liegen, sind gleiche Dateinamen aus unterschiedlichen Quellen nicht erlaubt. Beispielsweise müssen zwei verschiedene Dateien namens `.env` vorab eindeutige Namen erhalten und passend konfiguriert werden. Das Skript meldet solche Kollisionen vor dem Sicherungslauf. Konfigurationsquellen im Exportordner werden ebenfalls abgewiesen, weil der Exporter sie löschen könnte. Das Skript gibt keine Dateiinhalte im Protokoll aus und führt Konfigurationsdateien nicht als Shellcode aus. Beim Wiederherstellen musst du die Dateien wieder den ursprünglichen Verzeichnissen und Compose-Optionen zuordnen.

## Unterstützter Rahmen und Prüfung

Die Mount-Prüfung ist für einen lokalen Linux-Docker-Host mit Unix-Socket und einem direkten, schreibbaren Bind-Mount des Exportordners ausgelegt. Ein Docker-Volume, ein nur über einen übergeordneten Mount erreichbarer Exportordner, Docker Swarm oder ein entfernter Docker-Daemon werden hier nicht unterstützt. Hostpfade gehören zum Rechner des Docker-Daemons; siehe [Docker: Bind-Mounts](https://docs.docker.com/engine/storage/bind-mounts/).

Die lokalen Regressionstests simulieren Docker und prüfen Auswahl, Argumente, Dateikopien, Fehlerfälle und Schutz vor einem Export mit falscher Mount-Zuordnung. Sie ersetzen keinen Lauf mit echtem Docker, Compose und `rsync` auf Linux. Prüfe die gewählte Konfiguration zunächst mit einer separaten Testinstanz einschließlich Wiederherstellung.
