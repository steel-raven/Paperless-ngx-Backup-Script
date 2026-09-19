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

        # Prüfe, ob Paperless-ngx über den Service- oder den Containernamen erreichbar ist, und passe den Docker-Befehl entsprechend an
        backup_step='Paperless-ngx-Export'
        cd -- "${project_dir}"
        if [[ -n "${project_service_name}" ]] && running_containers=$(docker compose ps --status running -q -- "${project_service_name}") && [[ -n "${running_containers}" ]]; then
            docker_command=(docker compose exec -T -- "${project_service_name}")
        elif [[ -n "${project_container_name}" ]] && docker inspect -f '{{.State.Running}}' -- "${project_container_name}" | grep -q '^true$'; then
            docker_command=(docker exec "${project_container_name}")
        else
            docker_command=()
        fi

        # Führe den festgelegten Docker-Befehl aus
        if [[ "${#docker_command[@]}" -gt 0 ]]; then

            # Wechsle ins Hauptverzeichnis des Docker-Projekts
            cd "${project_dir}"

            # Sichern aller Dokumente in das Paperless-NGX-Exportverzeichnis
            log "Die integrierte Exportfunktion von Paperless-ngx wird ausgeführt. Bitte warten..."
            "${docker_command[@]}" document_exporter ../export -d -p -z
                # -d    : Löscht Dateien aus dem Exportverzeichnis, die in Paperless-ngx nicht mehr vorhanden sind.
                # -p    : Dateien werden in die entsprechenden Unterordner /archive, /originals und /thumbnails sortiert.
                # -z    : Der Inhalt des Exportverzeichnisses wird in einer ZIP-Datei nach der Syntax export-YYYY-MM-DD.zip archiviert.
                #         Der document_importer kann solch ein ZIP-Archiv verarbeiten.

            # Wechsle zurück ins Skriptverzeichnis
            cd "${script_dir}"

            # Prüfen, ob Dokumente im Paperless-NGX-Exportverzeichnis vorhanden sind
            backup_step='Übertragung des Exportverzeichnisses'
            if export_files=$(ls -A -- "${project_dir}/export") && [[ -n "${export_files}" ]]; then

                # Sichern aller exportierten Dokumente aus dem Paperless-NGX-Exportverzeichnis ins Datensicherungsziel
                rsync -a --delete -- "${project_dir}/export" "${backup_dir}"

                # Prüfen, ob Dokumente im Datensicherungsziel vorhanden sind
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

            # Variable des Docker-Befehls leeren
            docker_command=()
        else
            backup_complete=false
            log " - Die Sicherung des Paperless-NGX-Exportverzeichnises konnte nicht durchgeführt"
            log "   werden, da der Container aktuell nicht ausgeführt wird!"
        fi

        # Prüfe, ob PostgreSQL über den Service- oder den Containernamen erreichbar ist, und passe den Docker-Befehl entsprechend an
        backup_step='PostgreSQL-Dump'
        cd -- "${project_dir}"
        if [[ -n "${postgres_service_name}" ]] && running_containers=$(docker compose ps --status running -q -- "${postgres_service_name}") && [[ -n "${running_containers}" ]]; then
            docker_command=(docker compose exec -T -- "${postgres_service_name}")
        elif [[ -n "${postgres_container_name}" ]] && docker inspect -f '{{.State.Running}}' -- "${postgres_container_name}" | grep -q '^true$'; then
            docker_command=(docker exec "${postgres_container_name}")
        else
            docker_command=()
        fi

        # Wenn ein Docker-Befehl festgelegt wurde...
        if [[ "${#docker_command[@]}" -gt 0 ]]; then

            # Wechsle ins Hauptverzeichnis des Docker-Projekts
            cd "${project_dir}"

            # Den bisherigen Dump erst nach erfolgreicher, nicht leerer Ausgabe
            # ersetzen. Die temporäre Datei liegt für atomisches Umbenennen im selben Ziel.
            dump_tmp=$(mktemp -- "${backup_dir}/.postgres-dump.sql.XXXXXX")
            # Die Umleitung bleibt in einer Subshell, damit auch ein Signalhandler
            # des Hauptskripts weiterhin ins Protokoll und nicht in die SQL-Datei schreibt.
            ( "${docker_command[@]}" pg_dump -U "${postgresql_user}" -d "${postgresql_db}" > "${dump_tmp}" )

            # Wechsle zurück ins Skriptverzeichnis
            cd "${script_dir}"

            # Prüfen, ob die Sicherung PostgreSQL-Datenbank erfolgreich war
            if [[ -s "${dump_tmp}" ]]; then
                mv -fT -- "${dump_tmp}" "${backup_dir}/postgres-dump.sql"
                dump_tmp=
                log " - Der Dump der PostgreSQL-Datenbank wurde in der Datei [ postgres-dump.sql ] gesichert."
            else
                backup_complete=false
                log " - Beim Sichern des PostgreSQL-Datenbank-Dumps ist ein Fehler aufgetreten!"
            fi

            # Variable des Docker-Befehls leeren
            docker_command=()
        else
            backup_complete=false
            log " - Die Erstellung eines Dumps der PostgreSQL-Datenbank konnte nicht durchgeführt"
            log "   werden, da der Container aktuell nicht ausgeführt wird!"
        fi

        # Übliche YAML- und ENV-Dateinamen im Projektverzeichnis erfassen, auch versteckte Dateien
        backup_step='Sicherung der Konfigurationsdateien'
        yamlfiles=()
        envfiles=()
        for config_file in "${project_dir}"/* "${project_dir}"/.[!.]* "${project_dir}"/..?*; do
            [[ -f "${config_file}" ]] || continue
            config_name="${config_file##*/}"
            case "${config_name,,}" in
                *.yaml|*.yml) yamlfiles+=("${config_file}") ;;
                .env|.env.*|*.env|*.env.*) envfiles+=("${config_file}") ;;
            esac
        done

        # Falls ja, kopiere bzw. überschreibe die YAML-Datei(en) ins Datensicherungsziel
        if [[ "${#yamlfiles[@]}" -eq 0 ]]; then
            log " - Es wurde keine YAML-Datei gefunden."
        else
            for yamlfile in "${yamlfiles[@]}"; do
                cp -p -- "${yamlfile}" "${backup_dir}/"
                if [[ -f "${backup_dir}/${yamlfile##*/}" ]]; then
                    log " - Die YAML-Datei [ ${yamlfile##*/} ] wurde gesichert."
                else
                    backup_complete=false
                    log " - Beim Sichern der YAML-Datei [ ${yamlfile##*/} ] ist ein Fehler aufgetreten!"
                fi
            done
        fi

        # Falls ja, kopiere bzw. überschreibe die ENV-Datei(en) ins Datensicherungsziel
        if [[ "${#envfiles[@]}" -eq 0 ]]; then
            log " - Es wurde keine ENV-Datei gefunden."
        else
            for envfile in "${envfiles[@]}"; do
                cp -p -- "${envfile}" "${backup_dir}/"
                if [[ -f "${backup_dir}/${envfile##*/}" ]]; then
                    log " - Die ENV-Datei [ ${envfile##*/} ] wurde gesichert."
                else
                    backup_complete=false
                    log " - Beim Sichern der ENV-Datei [ ${envfile##*/} ] ist ein Fehler aufgetreten!"
                fi
            done
        fi

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
