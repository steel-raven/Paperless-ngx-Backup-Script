#!/bin/bash
# Filename: Paperless-ngx-Backup-Script.sh - coded in utf-8
version="1.0-700"


#             Backupskript für Paperless-ngx
#    Copyright (C) 2026 by tommes (toafez) | MIT License


# --------------------------------------------------------------
# Verbindliche, benutzerspezifische Angaben
# --------------------------------------------------------------

# Pfad zum lokalen Datensicherungsziel
backup_dir="/Absoluter/Pfad/zum/Datensicherungsziel"

# Dateiname des Sicherungsprotokolls
logfile_name="Protokoll_der_letzten_Sicherung.log"

# Pfad des zu sichernden Docker-Projekts
project_dir="/Absoluter/Pfad/zum/Paperless-ngx-Verzeichnis"

# Dienst- bzw. Servicename des Docker-Projekts
project_service_name="webserver"

# Containername oder ID des Docker-Projekts
project_container_name="Paperless-ngx"

# Dienst- bzw. Servicename der PostgreSQL-Datenbank
postgres_service_name="db"

# Containername oder ID der PostgreSQL-Datenbank
postgres_container_name="Paperless-ngx-PostgreSQL"

# Benutzername für die PostgreSQL-Datenbank
postgresql_user="paperless"

# Name der PostgreSQL-Datenbank
postgresql_db="paperless"

# Angabe einer Zeit in Tagen, wie lange Versionsordner behalten
# werden sollen, bevor sie gelöscht werden. Der Wert 0 bedeutet,
# dass keine Versionsordner erstellt werden.
version_history="0"

# Docker-Zugriff: auto (lokale Compose-Datei, sonst Container), compose oder container
docker_mode="auto"

# Optionale Compose-Dateien in ihrer Reihenfolge; relative Pfade gelten ab project_dir.
# Leer: compose.yaml/.yml oder docker-compose.yaml/.yml samt Standard-Override suchen.
compose_files=()
compose_project_name=""

# Optionale Dateien für Compose-Variablen (--env-file), nicht für service.env_file.
# Leer: ausschließlich die .env im Projektverzeichnis verwenden, falls vorhanden.
compose_env_files=()

# Exportpfade auf dem Host und im Container; leerer Hostpfad bedeutet project_dir/export.
# Der Containerpfad muss direkt auf diesen lokalen Hostordner gemountet sein (bind, rw).
export_host_dir=""
export_container_dir="/usr/src/paperless/export"

# Weitere lokale Konfigurationsdateien, z. B. aus Portainer gespeicherte Stack-Dateien.
# Sie werden zusätzlich unter ihrem Dateinamen gesichert; Namenskonflikte führen zum Abbruch.
additional_config_files=()


# --------------------------------------------------------------
# Rock ’n’ Roll...
# --------------------------------------------------------------

# Skript sofort beenden wenn Fehlerstatus ungleich null ist
set -e

# Rückgabewert auf den ersten fehlerhaften Befehl innerhalb der Pipeline setzen
set -o pipefail

# Funktion: Aktuelles Datum
datestamp() { date +"%d.%m.%Y"; }

# Funktion: Aktuelle Uhrzeit
timestamp() { date +"%H:%M:%S"; }

# Funktion: Aktuelles Datum und Uhrzeit für die Bezeichnung der Versionsordner
datetime_dir() { date +"%Y-%m-%dT%H-%M-%S"; }

# Absoluten Pfad des Shell-Skripts ermitteln
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Konfiguration prüfen, bevor Verzeichnisse oder Protokolle verändert werden.
config_error() { printf 'Konfigurationsfehler: %s\n' "$*" >&2; exit 1; }
[[ "${version_history}" =~ ^(0|[1-9][0-9]*)$ ]] || config_error 'version_history muss 0 oder eine positive ganze Zahl sein.'
case "${logfile_name}" in
    ''|.|..|*/*|*\\*|*[[:cntrl:]]*) config_error 'logfile_name muss ein einfacher Dateiname ohne Pfadbestandteile sein.' ;;
esac
case "${logfile_name,,}" in
    export|postgres-dump.sql|.paperless-ngx-backup|*.yaml|*.yml|.env|.env.*|*.env|*.env.*)
        config_error 'logfile_name kollidiert mit einer Sicherungsdatei.' ;;
esac
for configured_path in "${project_dir}" "${backup_dir}"; do
    [[ "${configured_path}" == /* && "${configured_path}" != *[[:cntrl:]]* ]] || config_error 'Projekt- und Sicherungspfad müssen absolute Pfade sein.'
    [[ "${configured_path}" != /Absoluter/Pfad/* ]] || config_error 'Die Platzhalter für Projekt- und Sicherungspfad müssen ersetzt werden.'
done
[[ -d "${project_dir}" ]] || config_error 'Das Projektverzeichnis existiert nicht.'
project_dir="$(realpath -e -- "${project_dir}")"
backup_root="$(realpath -m -- "${backup_dir}")"
[[ "${project_dir}" != / ]] || config_error 'Das Dateisystem-Wurzelverzeichnis ist kein Projektverzeichnis.'
[[ "${backup_root}" == /*/* ]] || config_error 'Das Sicherungsziel muss ein eigenes Unterverzeichnis sein, kein Wurzelverzeichnis.'
case "${backup_root}" in
    /dev/*|/proc/*|/sys/*|/etc/*|/usr/*|/bin/*|/sbin/*|/lib/*|/lib64/*|/boot/*|/run/*|/var/lib|/var/log|/var/cache|/var/spool)
        config_error 'Ein Systemverzeichnis darf nicht als Sicherungsziel verwendet werden.' ;;
esac
if [[ "${backup_root}" == "${project_dir}" || "${backup_root}" == "${project_dir}/"* || "${project_dir}" == "${backup_root}/"* ]]; then
    config_error 'Projekt- und Sicherungsverzeichnis dürfen sich nicht überschneiden.'
fi
[[ ! -e "${backup_root}" || -d "${backup_root}" ]] || config_error 'Das Sicherungsziel ist kein Verzeichnis.'
for service_name in "${project_service_name}" "${postgres_service_name}"; do
    [[ -z "${service_name}" || "${service_name}" =~ ^[a-zA-Z0-9_.-]+$ ]] || config_error 'Ungültiger Docker-Servicename.'
done
for container_name in "${project_container_name}" "${postgres_container_name}"; do
    [[ -z "${container_name}" || "${container_name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || config_error 'Ungültiger Docker-Containername.'
done
[[ -n "${project_service_name}${project_container_name}" && -n "${postgres_service_name}${postgres_container_name}" ]] || config_error 'Für Paperless-ngx und PostgreSQL muss jeweils ein Service- oder Containername angegeben werden.'
[[ -n "${postgresql_user}" && -n "${postgresql_db}" ]] || config_error 'PostgreSQL-Benutzer und Datenbankname dürfen nicht leer sein.'

case "${docker_mode}" in auto|compose|container) ;; *) config_error 'docker_mode muss auto, compose oder container sein.' ;; esac
[[ -z "${compose_project_name}" || "${compose_project_name}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || config_error 'Ungültiger Compose-Projektname.'
export_host_dir="${export_host_dir:-${project_dir}/export}"
[[ "${export_host_dir}" == /* && "${export_host_dir}" != *[[:cntrl:]]* ]] || config_error 'export_host_dir muss ein absoluter Hostpfad sein.'
export_host_dir=$(realpath -m -- "${export_host_dir}")
[[ "${export_host_dir}" == /*/* ]] || config_error 'Der Export benötigt einen eigenen Host-Unterordner.'
case "${export_host_dir}" in
    /dev/*|/proc/*|/sys/*|/etc/*|/usr/*|/bin/*|/sbin/*|/lib/*|/lib64/*|/boot/*|/run/*|/var/lib|/var/log|/var/cache|/var/spool)
        config_error 'Ein Systemverzeichnis darf nicht als Exportordner verwendet werden.' ;;
esac
if [[ "${export_host_dir}" == "${project_dir}" || "${project_dir}" == "${export_host_dir}/"* ||
      "${export_host_dir}" == "${backup_root}" || "${export_host_dir}" == "${backup_root}/"* || "${backup_root}" == "${export_host_dir}/"* ]]; then
    config_error 'Exportordner, Projekt und Sicherungsziel überschneiden sich in unsicherer Weise.'
fi
export_container_dir="${export_container_dir%/}"
[[ "${export_container_dir}" == /* && "${export_container_dir}" != / && "${export_container_dir}" != *[[:cntrl:]]* ]] || config_error 'export_container_dir muss ein absoluter Container-Unterordner sein.'
case "${export_container_dir}/" in *'/../'*|*'/./'*|*'//'*) config_error 'Der Container-Exportpfad muss ohne . oder .. angegeben werden.' ;; esac
for protected_dir in data media consume; do
    if [[ "${export_host_dir}" == "${project_dir}/${protected_dir}" || "${export_host_dir}" == "${project_dir}/${protected_dir}/"* ||
          "${export_container_dir}" == "/usr/src/paperless/${protected_dir}" || "${export_container_dir}" == "/usr/src/paperless/${protected_dir}/"* ||
          "/usr/src/paperless/${protected_dir}" == "${export_container_dir}/"* ]]; then
        config_error 'Der Exportpfad darf nicht auf die Paperless-Daten-, Medien- oder Eingangsverzeichnisse zeigen.'
    fi
done

# Alle zu sichernden Dateien vorab prüfen. Keine Inhalte ausführen oder ins Protokoll schreiben.
config_files=()
normalize_config_file() {
    local file="$1" parent
    [[ -n "${file}" && "${file}" != *[[:cntrl:]]* ]] || config_error 'Ungültiger Konfigurationsdateipfad.'
    [[ "${file}" == /* ]] || file="${project_dir}/${file}"
    [[ -f "${file}" && -r "${file}" ]] || config_error "Konfigurationsdatei fehlt oder ist nicht lesbar: ${file}"
    # Das Elternverzeichnis physisch auflösen, den Dateinamen eines Links aber
    # beibehalten. Auch Pfade mit einem Verzeichnislink vor .. bleiben so korrekt.
    parent="${file%/*}"
    parent=$(realpath -e -- "${parent:-/}")
    printf '%s/%s\n' "${parent%/}" "${file##*/}"
}
add_config_file() {
    local file name existing resolved
    file=$(normalize_config_file "$1")
    name="${file##*/}"
    resolved=$(realpath -e -- "${file}")
    [[ "${resolved}" != "${backup_root}/"* ]] || config_error 'Konfigurationsquellen dürfen nicht im Sicherungsziel liegen.'
    [[ "${resolved}" != "${export_host_dir}/"* ]] || config_error 'Konfigurationsquellen dürfen nicht im Exportordner liegen; der Exporter kann dort Dateien löschen.'
    case "${name}" in export|postgres-dump.sql|.paperless-ngx-backup|"${logfile_name}") config_error "Reservierter Sicherungsname: ${name}" ;; esac
    for existing in "${config_files[@]}"; do
        if [[ "${existing##*/}" == "${name}" ]]; then
            [[ "${existing}" -ef "${file}" ]] || config_error "Mehrere Konfigurationsdateien heißen ${name}; bitte eindeutige Dateinamen verwenden."
            return 0
        fi
    done
    config_files+=("${file}")
}
for config_file in "${project_dir}"/* "${project_dir}"/.[!.]* "${project_dir}"/..?*; do
    [[ -f "${config_file}" ]] || continue
    config_name="${config_file##*/}"
    case "${config_name,,}" in *.yaml|*.yml|.env|.env.*|*.env|*.env.*) add_config_file "${config_file}" ;; esac
done

# Compose nie in übergeordneten Verzeichnissen suchen lassen. Explizite -f-Argumente
# begrenzen die Auswahl; ein fehlerhafter Compose-Aufruf wechselt nicht den Stack.
selected_compose_files=()
selected_env_files=()
if [[ "${docker_mode}" != container ]]; then
    if [[ "${#compose_files[@]}" -gt 0 ]]; then
        for config_file in "${compose_files[@]}"; do
            normalized_file=$(normalize_config_file "${config_file}")
            selected_compose_files+=("${normalized_file}")
        done
    elif [[ "${docker_mode}" == compose || -n "${project_service_name}${postgres_service_name}" ]]; then
        for config_name in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
            if [[ -f "${project_dir}/${config_name}" ]]; then
                selected_compose_files+=("${project_dir}/${config_name}")
                break
            fi
        done
        if [[ "${#selected_compose_files[@]}" -gt 0 ]]; then
            for config_name in compose.override.yaml compose.override.yml docker-compose.override.yaml docker-compose.override.yml; do
                if [[ -f "${project_dir}/${config_name}" ]]; then
                    selected_compose_files+=("${project_dir}/${config_name}")
                    break
                fi
            done
        fi
    fi
fi
effective_mode="${docker_mode}"
if [[ "${effective_mode}" == auto ]]; then
    if [[ "${#selected_compose_files[@]}" -gt 0 ]]; then effective_mode=compose; else effective_mode=container; fi
fi
compose_command=(docker compose --project-directory "${project_dir}")
if [[ "${effective_mode}" == compose ]]; then
    [[ "${#selected_compose_files[@]}" -gt 0 ]] || config_error 'Keine lokale Compose-Datei gefunden; compose_files angeben oder container verwenden.'
    [[ -n "${project_service_name}" && -n "${postgres_service_name}" ]] || config_error 'Im Compose-Modus sind beide Servicenamen erforderlich.'
    for config_file in "${selected_compose_files[@]}"; do
        add_config_file "${config_file}"
        compose_command+=(-f "${config_file}")
    done
    [[ -z "${compose_project_name}" ]] || compose_command+=(-p "${compose_project_name}")
    if [[ "${#compose_env_files[@]}" -gt 0 ]]; then
        for config_file in "${compose_env_files[@]}"; do
            normalized_file=$(normalize_config_file "${config_file}")
            selected_env_files+=("${normalized_file}")
        done
    elif [[ -f "${project_dir}/.env" ]]; then
        selected_env_files+=("${project_dir}/.env")
    fi
    if [[ "${#selected_env_files[@]}" -eq 0 ]]; then
        compose_command+=(--env-file /dev/null)
    else
        for config_file in "${selected_env_files[@]}"; do
            add_config_file "${config_file}"
            compose_command+=(--env-file "${config_file}")
        done
    fi
else
    [[ -n "${project_container_name}" && -n "${postgres_container_name}" ]] || config_error 'Im Container-Modus sind beide Containernamen oder IDs erforderlich.'
    [[ "${#compose_files[@]}" -eq 0 && "${#compose_env_files[@]}" -eq 0 && -z "${compose_project_name}" ]] || config_error 'Compose-Angaben benötigen den Compose-Modus; reine Sicherungsdateien gehören in additional_config_files.'
fi
for config_file in "${additional_config_files[@]}"; do add_config_file "${config_file}"; done

logfile="${backup_root}/${logfile_name}"
[[ ! -L "${logfile}" && ( ! -e "${logfile}" || -f "${logfile}" ) ]] || config_error 'Die Protokolldatei darf kein symbolischer Link oder Verzeichnis sein.'
if [[ -f "${logfile}" ]]; then
    [[ "$(stat -c '%h' -- "${logfile}")" == 1 && ! "${logfile}" -ef "${BASH_SOURCE[0]}" ]] || config_error 'Die Protokolldatei darf keine andere Datei oder das Skript überschreiben.'
fi

# Datensicherungsziel erstellen und seinen absoluten Pfad festhalten
mkdir -p -- "${backup_root}"
backup_dir="${backup_root}"

# Standardausgabe und Fehler gemeinsam protokollieren. Ein Dump leitet nur seine
# SQL-Standardausgabe um; seine Fehler bleiben dadurch im Sicherungsprotokoll.
: > "${logfile}"
exec 3>&1 4>&2
exec > >(tee -a -- "${logfile}" >&3) 2>&1
log_pid=$!
log() { printf '%s\n' "$*"; }
backup_step='Vorbereitung des Sicherungsziels'
dump_tmp=
finish() {
    local status=$? log_status
    trap - EXIT
    if [[ -n "${dump_tmp}" ]]; then
        if ! rm -f -- "${dump_tmp}"; then
            log ' - Die temporäre Dump-Datei konnte nicht entfernt werden.'
            [[ "${status}" -ne 0 ]] || status=1
        fi
    fi
    if [[ "${status}" -ne 0 ]]; then
        log " - FEHLER: Datensicherung nicht erfolgreich; Schritt: ${backup_step}; Rückgabecode: ${status}."
    fi
    # Alle Ausgaben müssen geschrieben sein, bevor der Aufrufer den Status erhält.
    exec 1>&3 2>&4 3>&- 4>&-
    if wait "${log_pid}"; then
        :
    else
        log_status=$?
        printf 'FEHLER: Das Sicherungsprotokoll konnte nicht vollständig geschrieben werden.\n' >&2
        [[ "${status}" -ne 0 ]] || status=${log_status}
    fi
    exit "${status}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Einen einzelnen laufenden Container ermitteln und anschließend über seine ID
# ansprechen. Dadurch verwenden Prüfung und Export denselben Container.
resolve_container() {
    local service="$1" container="$2" role="$3" output state id extra
    local ids=()
    if [[ "${effective_mode}" == compose ]]; then
        if ! output=$( (unset COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_ENV_FILES; "${compose_command[@]}" ps --all -q -- "${service}") ); then
            printf ' - %s: Compose-Abfrage fehlgeschlagen; kein Wechsel zu einem anderen Container.\n' "${role}" >&2
            return 1
        fi
        [[ -z "${output}" ]] || mapfile -t ids <<< "${output}"
        if [[ "${#ids[@]}" -ne 1 || ! "${ids[0]}" =~ ^[a-f0-9]{64}$ ]]; then
            printf ' - %s: Es muss genau ein Container für den Compose-Service gefunden werden.\n' "${role}" >&2
            return 1
        fi
        container="${ids[0]}"
    fi
    if ! output=$(docker inspect --type container --format '{{.State.Running}} {{.Id}}' -- "${container}"); then
        printf ' - %s: Container konnte nicht geprüft werden.\n' "${role}" >&2
        return 1
    fi
    read -r state id extra <<< "${output}"
    if [[ "${state}" != true || ! "${id}" =~ ^[a-f0-9]{64}$ || -n "${extra}" || "${output}" == *$'\n'* ]]; then
        printf ' - %s: Kein eindeutig identifizierter laufender Container.\n' "${role}" >&2
        return 1
    fi
    printf '%s\n' "${id}"
}

check_export_mount() {
    local endpoint mounts type source target writable extra actual_source matched=false
    if [[ -n "${DOCKER_CONTEXT:-}" || -z "${DOCKER_HOST:-}" ]]; then
        endpoint=$(docker context inspect --format '{{(index .Endpoints "docker").Host}}')
    else
        endpoint="${DOCKER_HOST}"
    fi
    [[ "${endpoint}" == unix:///* ]] || { log ' - Für die Hostpfad-Prüfung ist ein lokaler Docker-Daemon mit Unix-Socket erforderlich.'; return 1; }
    [[ -d "${export_host_dir}" ]] || { log ' - Der konfigurierte Exportordner auf dem Host fehlt.'; return 1; }
    mounts=$(docker inspect --type container --format '{{range .Mounts}}{{printf "%s\x1f%s\x1f%s\x1f%t\n" .Type .Source .Destination .RW}}{{end}}' -- "${paperless_id}")
    while IFS=$'\037' read -r type source target writable extra; do
        [[ -n "${type}" ]] || continue
        [[ -n "${target}" && -z "${extra}" && "${writable}" =~ ^(true|false)$ ]] || { log ' - Ungültige Mount-Angaben vom Docker-Daemon.'; return 1; }
        if [[ "${target}" == "${export_container_dir}" ]]; then
            [[ "${type}" == bind && "${writable}" == true && "${matched}" == false ]] || { log ' - Der Exportpfad benötigt genau einen schreibbaren Bind-Mount; Docker-Volumes werden hier nicht unterstützt.'; return 1; }
            actual_source=$(realpath -e -- "${source}")
            [[ "${actual_source}" == "${export_host_dir}" ]] || { log ' - Der Host-Exportpfad stimmt nicht mit dem Bind-Mount des Containers überein.'; return 1; }
            matched=true
        elif [[ "${target}" == "${export_container_dir}/"* ]]; then
            log ' - Unterhalb des Container-Exportpfads liegt ein weiterer Mount; Export abgebrochen.'
            return 1
        elif [[ "${type}" == bind ]]; then
            actual_source=$(realpath -m -- "${source}")
            if [[ "${actual_source}" == "${export_host_dir}" || "${actual_source}" == "${export_host_dir}/"* ]]; then
                log ' - Der Host-Exportordner enthält Daten eines weiteren Container-Mounts; Export abgebrochen.'
                return 1
            fi
        fi
    done <<< "${mounts}"
    [[ "${matched}" == true ]] || { log ' - Für export_container_dir wurde kein direkter Bind-Mount gefunden.'; return 1; }
}

# Versionsordner neu anlegen; einen bereits vorhandenen Ordner niemals übernehmen
if [[ "${version_history}" =~ ^[1-9][0-9]*$ ]]; then
    backup_dir="${backup_root%/}/$(datetime_dir)"
    mkdir -- "${backup_dir}"
fi

# Falls das Datensicherungsziel exisitiert...
if [[ -d "${backup_dir}" ]]; then

    hr="---------------------------------------------------------------------------------------------------------"

    # Beginn des Protokolls...

    # Prüfen, ob das verwendete Skript aktuell ist oder ob ein Update auf GitHub verfügbar ist
    if git_version=$(wget --no-check-certificate --timeout=60 --tries=1 -q -O- "https://raw.githubusercontent.com/toafez/Paperless-ngx-Backup-Script/refs/heads/main/Paperless-ngx-Backup-Script.sh" | grep '^version=' | cut -d '"' -f2) && [[ -n "${git_version}" ]]; then
        if dpkg --compare-versions "${git_version}" gt "${version}"; then
            log "${hr}"
            log "WICHTIGER HINWEIS:"
            log "Auf GitHub steht ein Update für dieses Skript zur Verfügung."
            log "Bitte aktualisiere deine Version ${version} auf die neue Version ${git_version}."
            log "Link: https://github.com/toafez/Paperless-ngx-Backup-Script"
            log "${hr}"
            log ""
        fi
    else
        log " - Hinweis: Die Updateprüfung konnte nicht abgeschlossen werden (z. B. keine Internetverbindung)."
        log "   Die Updateprüfung wird übersprungen; die Datensicherung wird fortgesetzt."
    fi

    # Wenn das Hauptverzeichnis des Docker-Projekts existiert...
    if [[ -d "${project_dir}" ]]; then

        # Nur nach einer vollständigen Sicherung alte Versionen bereinigen
        backup_complete=true

        # Prüfen, welchem Benutzer bzw. welcher Gruppe das Docker-Projekt Verzeichnis gehört
        backup_step='Ermittlung der Besitzrechte'
        dir_user=$(stat -c '%U' "${project_dir}")
        dir_group=$(stat -c '%G' "${project_dir}")

        log "${hr}"
        log "${project_container_name} Datensicherungsprotokoll vom $(datestamp) um $(timestamp) Uhr"
        log " - Datensicherungsziel: ${backup_dir}"
        log "${hr}"
        log ""

        # Beide Container und die Mount-Zuordnung prüfen, bevor der Export mit -d beginnt.
        backup_step='Prüfung der Docker-Container'
        log " - Docker-Betriebsart: ${effective_mode}"
        cd -- "${project_dir}"
        paperless_id=$(resolve_container "${project_service_name}" "${project_container_name}" Paperless-ngx)
        postgres_id=$(resolve_container "${postgres_service_name}" "${postgres_container_name}" PostgreSQL)
        log " - Paperless-ngx-Container: ${paperless_id}"
        log " - PostgreSQL-Container: ${postgres_id}"
        backup_step='Prüfung des Export-Mounts'
        check_export_mount
        log " - Exportpfad: ${export_host_dir} -> ${export_container_dir}"
        [[ ! -L "${backup_dir}/export" && ( ! -e "${backup_dir}/export" || -d "${backup_dir}/export" ) ]] || { log ' - Das Exportziel ist ein Link oder kein Verzeichnis.'; exit 1; }
        for config_file in "${config_files[@]}"; do
            config_target="${backup_dir}/${config_file##*/}"
            [[ ! -L "${config_target}" && ( ! -e "${config_target}" || -f "${config_target}" ) ]] || { log ' - Eine Konfigurations-Zieldatei ist ein Link oder keine reguläre Datei.'; exit 1; }
        done
        if [[ "${effective_mode}" == container && "${#config_files[@]}" -eq 0 ]]; then
            log ' - Hinweis: Keine lokalen Konfigurationsdateien gefunden. Portainer-Stack und separat gespeicherte Variablen über additional_config_files ergänzen.'
        fi

        # Sichern aller Dokumente in das geprüfte Exportverzeichnis
        backup_step='Paperless-ngx-Export'
        log "Die integrierte Exportfunktion von Paperless-ngx wird ausgeführt. Bitte warten..."
        docker exec "${paperless_id}" document_exporter "${export_container_dir}" -d -p -z
        # -d    : Löscht Dateien aus dem Exportverzeichnis, die in Paperless-ngx nicht mehr vorhanden sind.
        # -p    : Dateien werden in die entsprechenden Unterordner /archive, /originals und /thumbnails sortiert.
        # -z    : Der Inhalt des Exportverzeichnisses wird in einer ZIP-Datei nach der Syntax export-YYYY-MM-DD.zip archiviert.
        #         Der document_importer kann solch ein ZIP-Archiv verarbeiten.

        # Wechsle zurück ins Skriptverzeichnis
        cd "${script_dir}"

        # Prüfen, ob Dokumente im Paperless-NGX-Exportverzeichnis vorhanden sind
        backup_step='Übertragung des Exportverzeichnisses'
        if export_files=$(ls -A -- "${export_host_dir}") && [[ -n "${export_files}" ]]; then

            # Auch bei abweichendem Quellnamen immer in den Sicherungsordner export kopieren.
            rsync -a --delete -- "${export_host_dir}/" "${backup_dir}/export/"

            if [[ -d "${backup_dir}/export" ]]; then
                log " - Das Paperless-NGX-Exportverzeichnis [ /export ] wurde gesichert."
            else
                backup_complete=false
                log " - Die Sicherung des Paperless-NGX-Exportverzeichnises war nicht möglich."
            fi
        else
            backup_complete=false
            log " - Die Bereitstellung der Dokumente im Paperless-NGX-Exportverzeichnis war nicht möglich."
        fi

        # Den bereits geprüften Datenbankcontainer direkt über seine ID ansprechen.
        backup_step='PostgreSQL-Dump'
        cd -- "${project_dir}"

        # Den bisherigen Dump erst nach erfolgreicher, nicht leerer Ausgabe
        # ersetzen. Die temporäre Datei liegt für atomisches Umbenennen im selben Ziel.
        dump_tmp=$(mktemp -- "${backup_dir}/.postgres-dump.sql.XXXXXX")
        # Die Umleitung bleibt in einer Subshell, damit auch ein Signalhandler
        # des Hauptskripts weiterhin ins Protokoll und nicht in die SQL-Datei schreibt.
        ( docker exec "${postgres_id}" pg_dump -U "${postgresql_user}" -d "${postgresql_db}" > "${dump_tmp}" )

        cd "${script_dir}"

        if [[ -s "${dump_tmp}" ]]; then
            mv -fT -- "${dump_tmp}" "${backup_dir}/postgres-dump.sql"
            dump_tmp=
            log " - Der Dump der PostgreSQL-Datenbank wurde in der Datei [ postgres-dump.sql ] gesichert."
        else
            backup_complete=false
            log " - Beim Sichern des PostgreSQL-Datenbank-Dumps ist ein Fehler aufgetreten!"
        fi

        # Die vorab geprüften lokalen und ausdrücklich angegebenen Dateien sichern.
        backup_step='Sicherung der Konfigurationsdateien'
        yaml_found=false
        env_found=false
        for config_file in "${config_files[@]}"; do
            config_name="${config_file##*/}"
            case "${config_name,,}" in
                *.yaml|*.yml) config_label='YAML-Datei'; yaml_found=true ;;
                .env|.env.*|*.env|*.env.*) config_label='ENV-Datei'; env_found=true ;;
                *) config_label='Konfigurationsdatei' ;;
            esac
            cp -p -- "${config_file}" "${backup_dir}/"
            if [[ -f "${backup_dir}/${config_name}" ]]; then
                log " - Die ${config_label} [ ${config_name} ] wurde gesichert."
            else
                backup_complete=false
                log " - Beim Sichern der ${config_label} [ ${config_name} ] ist ein Fehler aufgetreten!"
            fi
        done
        [[ "${yaml_found}" == true ]] || log ' - Es wurde keine YAML-Datei gefunden.'
        [[ "${env_found}" == true ]] || log ' - Es wurde keine ENV-Datei gefunden.'

        # Passe Ordner- und Dateireche im Sicherungsziel an
        backup_step='Anpassung der Besitzrechte'
        chown -R -- "${dir_user}:${dir_group}" "${backup_dir}"
        log " - Die Ordner- und Dateirechte im Datensicherungsziel wurden auf [ ${dir_user}:${dir_group} ] gesetzt."

        # Nur eindeutig gekennzeichnete, abgeschlossene Versionsordner automatisch löschen
        backup_step='Versionsbereinigung'
        if [[ "${version_history}" =~ ^[1-9][0-9]*$ ]]; then
            if [[ "${backup_complete}" == true ]]; then
                printf 'Paperless-ngx-Backup-Script:%s\n' "${backup_dir##*/}" > "${backup_dir}/.paperless-ngx-backup"
                for old_backup in "${backup_root%/}"/*; do
                    [[ -d "${old_backup}" && ! -L "${old_backup}" && "${old_backup}" != "${backup_dir}" ]] || continue
                    old_name="${old_backup##*/}"
                    [[ "${old_name}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || continue
                    marker="${old_backup}/.paperless-ngx-backup"
                    [[ -f "${marker}" && ! -L "${marker}" ]] || continue
                    [[ "$(cat -- "${marker}")" == "Paperless-ngx-Backup-Script:${old_name}" ]] || continue
                    expired_backup=$(find "${old_backup}" -maxdepth 0 -type d -mtime +"${version_history}" -print)
                    [[ -n "${expired_backup}" ]] || continue
                    rm -rf -- "${old_backup}"
                    log " - Versionsstand [ ${old_name} ], älter als [ ${version_history} ] Tag(e), wurde gelöscht."
                done
            else
                log " - Die Versionsbereinigung wird übersprungen, da die Datensicherung unvollständig ist."
            fi
        fi

        log ""
        log "${hr}"
        backup_step='Abschlussprüfung (siehe vorherige Fehlermeldungen)'
        [[ "${backup_complete}" == true ]] || exit 1
    else
        log " - Das ${project_container_name} Verzeichnis oder die Docker-Compose Datei wurde nicht gefunden."
        log ""
        log "${hr}"
        exit 1
    fi
else
    log ' - Das Datensicherungsziel ist nicht verfügbar.'
    exit 1
fi
