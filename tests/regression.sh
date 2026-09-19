#!/bin/bash
# Isolierte Regressionstests: kein Docker, Netzwerk oder Root-Zugriff erforderlich.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_script="${1:-${repo_dir}/Paperless-ngx-Backup-Script.sh}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/paperless-backup-tests.XXXXXX")"
test_root="$(cd -- "${test_root}" && pwd -P)"
test_parent="${test_root%/*}"
: > "${test_root}/.test-root"
export test_root

cleanup() {
    if [[ "${KEEP_TEST_ARTIFACTS:-0}" == 1 ]]; then
        printf 'Testdateien: %s\n' "${test_root}"
        return
    fi
    local resolved_root
    resolved_root="$(cd -- "${test_root}" && pwd -P)" || return
    if [[ "${resolved_root}" == "${test_root}" && "${resolved_root%/*}" == "${test_parent}" && "${resolved_root##*/}" == paperless-backup-tests.* && -f "${resolved_root}/.test-root" ]]; then
        command rm -rf -- "${resolved_root}"
    fi
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "Datei fehlt: $1"; }
assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] || fail "Unerwarteter Pfad: $1"; }
assert_log() { grep -Fq -- "$1" "${case_root}/output.log" || fail "Protokolltext fehlt: $1"; }
assert_saved_log() { grep -Fq -- "$1" "${backup}/Protokoll_der_letzten_Sicherung.log" || fail "Gespeicherter Protokolltext fehlt: $1"; }
assert_no_dump_temp() {
    local candidate
    for candidate in "${destination}"/.postgres-dump.sql.*; do
        assert_absent "${candidate}"
    done
}
pass() { printf 'PASS: %s\n' "$*"; }

# Alle externen Aktionen des Backup-Skripts werden durch lokale Testfunktionen ersetzt.
wget() {
    case "${MOCK_UPDATE}" in
        offline) return 4 ;;
        empty) return 0 ;;
        malformed) printf '<html>Fehler</html>\n' ;;
        newer) printf 'version="9.9-999"\n' ;;
        current) printf 'version="1.0-700"\n' ;;
        *) return 99 ;;
    esac
}
dpkg() {
    [[ $# -eq 4 && "$1" == --compare-versions && "$3" == gt ]] || return 99
    [[ "$2" == 9.9-999 ]]
}
date() {
    if [[ "$*" == '+%Y-%m-%dT%H-%M-%S' ]]; then
        printf '2026-09-19T12-34-56\n'
    else
        command date "$@"
    fi
}
docker() {
    printf '%s\n' "$*" >> "${MOCK_CASE}/docker.log"
    if [[ "$1 $2" == 'compose ps' ]]; then
        if [[ "${MOCK_DOCKER}" == probe-fail ]]; then
            printf 'SIMULATED_DOCKER_PROBE_FAILURE\n' >&2
            return 7
        fi
        [[ "${MOCK_DOCKER}" != stopped && "${MOCK_DOCKER}" != fallback ]] || return 0
        [[ "${MOCK_DOCKER}" != no-db || "${*: -1}" != db ]] || return 0
        printf 'test-container\n'
    elif [[ "$1" == inspect ]]; then
        if [[ "${MOCK_DOCKER}" == probe-fail ]]; then
            printf 'SIMULATED_DOCKER_INSPECT_FAILURE\n' >&2
            return 7
        fi
        [[ "${MOCK_DOCKER}" == fallback ]] && printf 'true\n' || printf 'false\n'
    else
        if [[ "$1 $2" == 'compose exec' ]]; then
            [[ "$3" == -T && "$4" == -- ]] || return 99
            shift 5
        elif [[ "$1" == exec ]]; then
            shift 2
        else
            return 99
        fi
        case "$1" in
            document_exporter)
                if [[ "${MOCK_DOCKER}" == export-fail ]]; then
                    printf 'SIMULATED_EXPORT_FAILURE\n' >&2
                    return 9
                fi
                mkdir -p -- "${MOCK_PROJECT}/export"
                if [[ "${MOCK_DOCKER}" != empty-export ]]; then
                    printf 'Export-Daten\n' > "${MOCK_PROJECT}/export/document.txt"
                fi
                ;;
            pg_dump)
                if [[ "${MOCK_DOCKER}" == dump-fail || "${MOCK_DOCKER}" == partial-dump ]]; then
                    [[ "${MOCK_DOCKER}" != partial-dump ]] || printf 'Unvollständige SQL-Daten\n'
                    printf 'SIMULATED_PG_DUMP_CONNECTION_FAILURE\n' >&2
                    return 9
                fi
                if [[ "${MOCK_DOCKER}" == interrupted-dump ]]; then
                    printf 'Unvollständige SQL-Daten\n'
                    kill -TERM "$$"
                    return 0
                fi
                [[ "${MOCK_DOCKER}" != empty-dump ]] || return 0
                [[ "${MOCK_DOCKER}" != dump-warning ]] || printf 'SIMULATED_PG_DUMP_WARNING\n' >&2
                printf 'SQL-Dump\n'
                ;;
            *) return 99 ;;
        esac
    fi
}
rsync() {
    [[ $# -eq 5 && "$1" == -a && "$2" == --delete && "$3" == -- ]] || return 99
    [[ "$4" == "${MOCK_PROJECT}/export" && "${5%/}" == "${MOCK_DEST}" ]] || return 99
    if [[ "${MOCK_RSYNC}" == fail ]]; then printf 'SIMULATED_RSYNC_FAILURE\n' >&2; return 23; fi
    command cp -a -- "$4" "$5/"
}
chown() {
    [[ $# -eq 4 && "$1" == -R && "$2" == -- && "${4%/}" == "${MOCK_DEST}" ]] || return 99
    if [[ "${MOCK_CHOWN}" == fail ]]; then printf 'SIMULATED_CHOWN_FAILURE\n' >&2; return 12; fi
}
cp() {
    [[ $# -eq 4 && "$1" == -p && "$2" == -- && "$3" == "${MOCK_PROJECT}/"* && "${4%/}" == "${MOCK_DEST}" ]] || return 99
    if [[ "${MOCK_COPY}" == fail ]]; then printf 'SIMULATED_COPY_FAILURE\n' >&2; return 11; fi
    command cp "$@"
}
mv() {
    [[ $# -eq 4 && "$1" == -fT && "$2" == -- && "$3" == "${MOCK_DEST}/.postgres-dump.sql."* && "$4" == "${MOCK_DEST}/postgres-dump.sql" ]] || return 99
    if [[ "${MOCK_MOVE}" == fail ]]; then printf 'SIMULATED_RENAME_FAILURE\n' >&2; return 14; fi
    command mv "$@"
}
tee() {
    if [[ "${MOCK_LOGGER}" == fail ]]; then
        command cat
        printf 'SIMULATED_LOG_WRITE_FAILURE\n' >&2
        return 15
    fi
    command tee "$@"
}
mkdir() {
    # Auch bei einer Regression der Pfadprüfung niemals außerhalb der Testwurzel schreiben.
    local path
    for path in "$@"; do
        case "${path}" in -p|--) continue ;; esac
        [[ "$(realpath -m -- "${path}")" == "${test_root}/"* ]] || return 99
    done
    command mkdir "$@"
}
rm() {
    # Vor jeder echten Testlöschung den aufgelösten Pfad auf den isolierten Testbereich begrenzen.
    if [[ $# -eq 3 && "$1" == -f && "$2" == -- && "$3" == "${MOCK_DEST}/.postgres-dump.sql."* ]]; then
        [[ "$(realpath -m -- "$3")" == "${test_root}/"* && ! -L "$3" ]] || return 99
        command rm -f -- "$3"
        return
    fi
    [[ $# -eq 3 && "$1" == -rf && "$2" == -- && -d "$3" && ! -L "$3" ]] || return 99
    local resolved_target resolved_backup
    resolved_target="$(cd -- "$3" && pwd -P)" || return 99
    resolved_backup="$(cd -- "${MOCK_BACKUP}" && pwd -P)" || return 99
    [[ "${resolved_target}" == "${test_root}/"* && "${resolved_target%/*}" == "${resolved_backup}" ]] || return 99
    printf '%s\n' "${resolved_target}" >> "${MOCK_CASE}/deleted.log"
    if [[ "${MOCK_DELETE}" == fail ]]; then printf 'SIMULATED_DELETE_FAILURE\n' >&2; return 13; fi
    command rm -rf -- "${resolved_target}"
}
export -f wget dpkg date docker rsync chown cp mv tee mkdir rm

prepare_case() {
    case_root="${test_root}/$1"
    project="${case_root}/Project with spaces [data]"
    backup="${case_root}/Backup with spaces [data]"
    mkdir -p -- "${project}" "${backup}"
    export MOCK_CASE="${case_root}" MOCK_PROJECT="${project}" MOCK_BACKUP="${backup}"
    export MOCK_UPDATE=current MOCK_DOCKER=running MOCK_RSYNC=ok MOCK_DELETE=ok
    export MOCK_CHOWN=ok MOCK_COPY=ok MOCK_MOVE=ok MOCK_LOGGER=ok
    history="$2"
    destination="${backup}"
    if [[ "${history}" != 0 ]]; then
        destination="${backup}/2026-09-19T12-34-56"
    fi
    export MOCK_DEST="${destination}"
    # Nur benutzerspezifische Angaben ersetzen, den eigentlichen Skriptcode unverändert testen.
    local in_config=true
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ "${line}" != 'set -e' ]] || in_config=false
        if [[ "${in_config}" == false ]]; then
            printf '%s\n' "${line}"
            continue
        fi
        case "${line}" in
            backup_dir=*) printf 'backup_dir=%q\n' "${backup}/" ;;
            project_dir=*) printf 'project_dir=%q\n' "${project}" ;;
            version_history=*) printf 'version_history=%q\n' "${history}" ;;
            *) printf '%s\n' "${line}" ;;
        esac
    done < "${source_script}" > "${case_root}/runner with spaces.sh"
}
run_backup() {
    bash --noprofile --norc "${case_root}/runner with spaces.sh" > "${case_root}/output.log" 2>&1
}
set_config() {
    local key="$1" value="$2" line replaced=false
    while IFS= read -r line; do
        if [[ "${replaced}" == false && "${line}" == "${key}="* ]]; then
            printf '%s=%q\n' "${key}" "${value}"
            replaced=true
        else
            printf '%s\n' "${line}"
        fi
    done < "${case_root}/runner with spaces.sh" > "${case_root}/configured.sh"
    command mv -- "${case_root}/configured.sh" "${case_root}/runner with spaces.sh"
}
assert_backup() {
    assert_file "${destination}/export/document.txt"
    assert_file "${destination}/postgres-dump.sql"
    grep -Fxq 'SQL-Dump' "${destination}/postgres-dump.sql" || fail 'Dump-Inhalt falsch'
}
make_version() {
    local name="$1" marked="$2" age="$3"
    mkdir -p -- "${backup}/${name}"
    printf 'Erhaltene Sicherungsdaten\n' > "${backup}/${name}/payload.txt"
    if [[ "${marked}" == yes ]]; then
        printf 'Paperless-ngx-Backup-Script:%s\n' "${name}" > "${backup}/${name}/.paperless-ngx-backup"
    fi
    command touch -d "${age} days ago" -- "${backup}/${name}"
}

prepare_case filenames 0
config_names=('compose.yaml' 'docker-compose.yml' 'compose.override.yaml' '.hidden.yml' 'UPPER.YAML' '.env' '.env.production' 'paperless.env' 'paperless.env.local' 'settings with spaces.env' '.hidden.env' 'PRODUCTION.ENV' '..private.env')
for name in "${config_names[@]}"; do
    printf 'Testinhalt für %s\n' "${name}" > "${project}/${name}"
done
: > "${project}/empty.env"
: > "${project}/empty.yml"
printf 'Keine Konfiguration\n' > "${project}/notes.txt"
mkdir -- "${project}/directory.env"
run_backup || { cat -- "${case_root}/output.log"; fail 'Sicherung mit Leerzeichen'; }
assert_backup
for name in "${config_names[@]}" empty.env empty.yml; do
    command cmp -- "${project}/${name}" "${destination}/${name}" || fail "Konfiguration falsch: ${name}"
done
assert_absent "${destination}/notes.txt"
assert_absent "${destination}/directory.env"
assert_absent "${destination}/.paperless-ngx-backup"
assert_log 'Die ENV-Datei [ empty.env ] wurde gesichert.'
assert_log 'Die YAML-Datei [ empty.yml ] wurde gesichert.'
pass 'Leerzeichen, Musterzeichen und alle dokumentierten Konfigurationsnamen'

for update_mode in current newer offline empty malformed; do
    prepare_case "update-${update_mode}" 0
    export MOCK_UPDATE="${update_mode}"
    run_backup || fail "Update-Modus ${update_mode}"
    assert_backup
    if [[ "${update_mode}" == newer ]]; then
        assert_log 'Auf GitHub steht ein Update'
    elif [[ "${update_mode}" != current ]]; then
        assert_log 'Die Updateprüfung wird übersprungen'
        grep -Fq 'Die Updateprüfung wird übersprungen' "${backup}/Protokoll_der_letzten_Sicherung.log" || fail 'Update-Hinweis fehlt in Protokolldatei'
    fi
    pass "Updateprüfung: ${update_mode}; Sicherung abgeschlossen"
done

prepare_case fallback 0
export MOCK_DOCKER=fallback
run_backup || fail 'Containername als Rückfall'
assert_backup
pass 'Docker-Containername als Rückfall'

prepare_case retention 30
make_version 2020-01-01T00-00-00 yes 45
make_version 2020-01-02T00-00-00 no 45
make_version 2020-01-03T00-00-00 yes 1
make_version 'fremde Dokumente' yes 45
make_version 2020-01-04T00-00-00 no 45
printf 'falsche Kennzeichnung\n' > "${backup}/2020-01-04T00-00-00/.paperless-ngx-backup"
command touch -d '45 days ago' -- "${backup}/2020-01-04T00-00-00"
mkdir -p -- "${backup}/nested/2020-01-05T00-00-00"
printf 'Verschachtelte Daten\n' > "${backup}/nested/2020-01-05T00-00-00/payload.txt"
printf 'Paperless-ngx-Backup-Script:2020-01-05T00-00-00\n' > "${backup}/nested/2020-01-05T00-00-00/.paperless-ngx-backup"
command touch -d '45 days ago' -- "${backup}/nested/2020-01-05T00-00-00" "${backup}/nested"
symlink_supported=false
if ln -s -- "${backup}/2020-01-01T00-00-00" "${backup}/2020-01-06T00-00-00" 2>/dev/null && [[ -L "${backup}/2020-01-06T00-00-00" ]]; then
    symlink_supported=true
    make_version 2020-01-07T00-00-00 no 45
    printf 'Paperless-ngx-Backup-Script:2020-01-07T00-00-00\n' > "${case_root}/external-marker"
    ln -s -- "${case_root}/external-marker" "${backup}/2020-01-07T00-00-00/.paperless-ngx-backup"
    command touch -d '45 days ago' -- "${backup}/2020-01-07T00-00-00"
fi
run_backup || { cat -- "${case_root}/output.log"; fail 'Versionsbereinigung'; }
assert_backup
assert_absent "${backup}/2020-01-01T00-00-00"
for name in 2020-01-02T00-00-00 2020-01-03T00-00-00 'fremde Dokumente' 2020-01-04T00-00-00 nested/2020-01-05T00-00-00; do
    assert_file "${backup}/${name}/payload.txt"
done
assert_file "${destination}/.paperless-ngx-backup"
grep -Fxq 'Paperless-ngx-Backup-Script:2026-09-19T12-34-56' "${destination}/.paperless-ngx-backup" || fail 'Neue Kennzeichnung falsch'
[[ "$(wc -l < "${case_root}/deleted.log")" -eq 1 ]] || fail 'Mehr als ein Ordner zur Löschung ausgewählt'
if [[ "${symlink_supported}" == true ]]; then
    [[ -L "${backup}/2020-01-06T00-00-00" ]] || fail 'Verzeichnislink gelöscht'
    assert_file "${backup}/2020-01-07T00-00-00/payload.txt"
    pass 'Symbolische Verzeichnis- und Kennzeichnungslinks bleiben erhalten'
else
    printf 'SKIP: In dieser Testumgebung konnten keine symbolischen Links angelegt werden\n'
fi
pass 'Nur alte, gekennzeichnete, direkte Versionsordner gelöscht'

for failure in stopped no-db empty-export empty-dump export-fail dump-fail rsync-fail; do
    prepare_case "incomplete-${failure}" 30
    make_version 2020-01-01T00-00-00 yes 45
    if [[ "${failure}" == rsync-fail ]]; then
        export MOCK_RSYNC=fail
    else
        export MOCK_DOCKER="${failure}"
    fi
    status=0
    run_backup || status=$?
    [[ "${status}" -ne 0 ]] || fail "Fehler verschluckt: ${failure}"
    assert_saved_log 'FEHLER: Datensicherung nicht erfolgreich'
    assert_no_dump_temp
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_absent "${destination}/.paperless-ngx-backup"
    assert_absent "${case_root}/deleted.log"
    pass "Keine Bereinigung bei unvollständiger Sicherung: ${failure}"
done

prepare_case collision 30
mkdir -- "${destination}"
printf 'Fremde Daten\n' > "${destination}/payload.txt"
if run_backup; then fail 'Vorhandener Versionsordner wurde übernommen'; fi
assert_file "${destination}/payload.txt"
assert_absent "${destination}/.paperless-ngx-backup"
pass 'Kollision mit vorhandenem Versionsordner bricht sicher ab'

prepare_case deletion-failure 30
make_version 2020-01-01T00-00-00 yes 45
export MOCK_DELETE=fail
if run_backup; then fail 'Löschfehler wurde verschluckt'; fi
assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
if grep -Fq 'wurde gelöscht' "${case_root}/output.log"; then fail 'Falsche Erfolgsmeldung bei Löschfehler'; fi
pass 'Löschfehler wird nicht als Erfolg protokolliert'
assert_saved_log 'SIMULATED_DELETE_FAILURE'
assert_saved_log 'Rückgabecode: 13'

for failure in dump-fail partial-dump empty-dump interrupted-dump rename-fail; do
    prepare_case "preserve-${failure}" 0
    printf 'Bisheriger vollständiger Dump\n' > "${destination}/postgres-dump.sql"
    command cp -- "${destination}/postgres-dump.sql" "${case_root}/previous.sql"
    if [[ "${failure}" == rename-fail ]]; then
        export MOCK_MOVE=fail
        expected_status=14
    else
        export MOCK_DOCKER="${failure}"
        case "${failure}" in empty-dump) expected_status=1 ;; interrupted-dump) expected_status=143 ;; *) expected_status=9 ;; esac
    fi
    status=0
    run_backup || status=$?
    [[ "${status}" -eq "${expected_status}" ]] || fail "Falscher Rückgabecode ${status}: ${failure}"
    command cmp -- "${case_root}/previous.sql" "${destination}/postgres-dump.sql" || fail "Vorheriger Dump beschädigt: ${failure}"
    assert_no_dump_temp
    assert_saved_log "Rückgabecode: ${expected_status}"
    case "${failure}" in
        dump-fail|partial-dump)
            assert_saved_log 'SIMULATED_PG_DUMP_CONNECTION_FAILURE'
            assert_saved_log 'Schritt: PostgreSQL-Dump' ;;
    esac
    pass "Vorheriger Dump bleibt unverändert, temporäre Datei entfernt: ${failure}"
done

prepare_case successful-replacement 0
printf 'Alter Dump\n' > "${destination}/postgres-dump.sql"
export MOCK_DOCKER=dump-warning
run_backup || fail 'Ersetzung des Dumps'
assert_backup
[[ "$(cat -- "${destination}/postgres-dump.sql")" == SQL-Dump ]] || fail 'Protokolltext im SQL-Dump'
assert_saved_log 'SIMULATED_PG_DUMP_WARNING'
if grep -Fq 'SQL-Dump' "${backup}/Protokoll_der_letzten_Sicherung.log"; then fail 'SQL-Inhalt im Protokoll'; fi
assert_no_dump_temp
pass 'Erfolgreicher Dump ersetzt Vorgänger; SQL und Protokoll bleiben getrennt'

for failure in export rsync yaml-copy env-copy chown probe; do
    prepare_case "logged-${failure}" 30
    make_version 2020-01-01T00-00-00 yes 45
    case "${failure}" in
        export) export MOCK_DOCKER=export-fail; expected_status=9; diagnostic=SIMULATED_EXPORT_FAILURE ;;
        rsync) export MOCK_RSYNC=fail; expected_status=23; diagnostic=SIMULATED_RSYNC_FAILURE ;;
        yaml-copy|env-copy)
            printf 'Testkonfiguration\n' > "${project}/settings.${failure%-copy}"
            export MOCK_COPY=fail; expected_status=11; diagnostic=SIMULATED_COPY_FAILURE ;;
        chown) export MOCK_CHOWN=fail; expected_status=12; diagnostic=SIMULATED_CHOWN_FAILURE ;;
        probe) export MOCK_DOCKER=probe-fail; expected_status=1; diagnostic=SIMULATED_DOCKER_INSPECT_FAILURE ;;
    esac
    status=0
    run_backup || status=$?
    [[ "${status}" -eq "${expected_status}" ]] || fail "Fehlercode ${status}: ${failure}"
    assert_saved_log "${diagnostic}"
    assert_saved_log "Rückgabecode: ${expected_status}"
    assert_absent "${destination}/.paperless-ngx-backup"
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_absent "${case_root}/deleted.log"
    pass "Fehlercode und gespeicherte Diagnose, keine Versionsbereinigung: ${failure}"
done

for failure in logger logger-and-dump; do
    prepare_case "failure-${failure}" 0
    export MOCK_LOGGER=fail
    expected_status=15
    if [[ "${failure}" == logger-and-dump ]]; then
        export MOCK_DOCKER=dump-fail
        expected_status=9
    fi
    status=0
    run_backup || status=$?
    [[ "${status}" -eq "${expected_status}" ]] || fail "Protokollfehler verändert/verschluckt den Rückgabecode: ${status}"
    assert_log 'Das Sicherungsprotokoll konnte nicht vollständig geschrieben werden.'
    assert_no_dump_temp
    pass "Protokollfehler erkannt, ursprünglicher Befehlsfehler hat Vorrang: ${failure}"
done

for invalid in history-text history-negative history-empty history-fraction history-leading-zero log-parent log-subdir log-backslash log-empty log-dot log-dump log-export log-marker log-env log-yaml missing-project relative-project relative-backup placeholder root top-level system same-dir target-inside source-inside normalized-overlap missing-service invalid-service missing-user; do
    prepare_case "invalid-${invalid}" 0
    printf 'Bestehendes Protokoll\n' > "${backup}/Protokoll_der_letzten_Sicherung.log"
    printf 'Unbeteiligte Datei\n' > "${case_root}/unrelated.txt"
    case "${invalid}" in
        history-text) set_config version_history '30 Tage' ;;
        history-negative) set_config version_history -1 ;;
        history-empty) set_config version_history '' ;;
        history-fraction) set_config version_history 1.5 ;;
        history-leading-zero) set_config version_history 030 ;;
        log-parent) set_config logfile_name ../unrelated.txt ;;
        log-subdir) set_config logfile_name subdir/protokoll.log ;;
        log-backslash) set_config logfile_name '..\unrelated.txt' ;;
        log-empty) set_config logfile_name '' ;;
        log-dot) set_config logfile_name . ;;
        log-dump) set_config logfile_name postgres-dump.sql ;;
        log-export) set_config logfile_name export ;;
        log-marker) set_config logfile_name .paperless-ngx-backup ;;
        log-env) set_config logfile_name .env.production ;;
        log-yaml) set_config logfile_name COMPOSE.YAML ;;
        missing-project) set_config project_dir "${case_root}/missing-project" ;;
        relative-project) set_config project_dir relative-project ;;
        relative-backup) set_config backup_dir relative-backup ;;
        placeholder) set_config backup_dir /Absoluter/Pfad/zum/Datensicherungsziel ;;
        root) set_config backup_dir / ;;
        top-level) set_config backup_dir /tmp ;;
        system) set_config backup_dir /etc/paperless-backup ;;
        same-dir) set_config backup_dir "${project}" ;;
        target-inside) set_config backup_dir "${project}/export/backup" ;;
        source-inside) set_config backup_dir "${case_root}" ;;
        normalized-overlap) set_config backup_dir "${project}/export/../" ;;
        missing-service) set_config project_service_name ''; set_config project_container_name '' ;;
        invalid-service) set_config project_service_name 'web server' ;;
        missing-user) set_config postgresql_user '' ;;
    esac
    if run_backup; then fail "Ungültige Konfiguration akzeptiert: ${invalid}"; fi
    assert_log 'Konfigurationsfehler:'
    assert_absent "${case_root}/docker.log"
    assert_absent "${project}/export"
    assert_absent "${backup}/postgres-dump.sql"
    [[ "$(cat -- "${backup}/Protokoll_der_letzten_Sicherung.log")" == 'Bestehendes Protokoll' ]] || fail "Vorhandenes Protokoll verändert: ${invalid}"
    [[ "$(cat -- "${case_root}/unrelated.txt")" == 'Unbeteiligte Datei' ]] || fail "Fremde Datei verändert: ${invalid}"
    pass "Konfiguration vor Schreibzugriffen abgelehnt: ${invalid}"
done

prepare_case logfile-directory 0
mkdir -- "${backup}/protokoll.log"
set_config logfile_name protokoll.log
if run_backup; then fail 'Verzeichnis als Protokolldatei akzeptiert'; fi
assert_log 'Konfigurationsfehler:'
assert_absent "${case_root}/docker.log"
pass 'Verzeichnis als Protokolldatei abgewiesen'

prepare_case logfile-hardlink 0
printf 'Unbeteiligter Inhalt\n' > "${case_root}/unrelated.txt"
if ln -- "${case_root}/unrelated.txt" "${backup}/Protokoll_der_letzten_Sicherung.log" && [[ "$(stat -c '%h' -- "${case_root}/unrelated.txt")" -gt 1 ]]; then
    if run_backup; then fail 'Hardlink als Protokolldatei akzeptiert'; fi
    assert_log 'Konfigurationsfehler:'
    assert_absent "${case_root}/docker.log"
    [[ "$(cat -- "${case_root}/unrelated.txt")" == 'Unbeteiligter Inhalt' ]] || fail 'Hardlink-Ziel überschrieben'
    pass 'Hardlink als Protokolldatei abgewiesen, fremder Inhalt unverändert'
else
    printf 'SKIP: In dieser Testumgebung konnten keine Hardlinks angelegt werden\n'
fi

if [[ "${symlink_supported}" == true ]]; then
    prepare_case symlink-overlap 0
    ln -s -- "${project}" "${case_root}/project-alias"
    set_config backup_dir "${case_root}/project-alias"
    if run_backup; then fail 'Pfadüberschneidung über symbolischen Link akzeptiert'; fi
    assert_log 'Konfigurationsfehler:'
    assert_absent "${case_root}/docker.log"
    assert_absent "${project}/Protokoll_der_letzten_Sicherung.log"
    pass 'Pfadüberschneidung nach Auflösung symbolischer Links abgewiesen'

    prepare_case logfile-symlink 0
    printf 'Unbeteiligter Inhalt\n' > "${case_root}/unrelated.txt"
    ln -s -- "${case_root}/unrelated.txt" "${backup}/Protokoll_der_letzten_Sicherung.log"
    if run_backup; then fail 'Symbolischer Link als Protokolldatei akzeptiert'; fi
    assert_log 'Konfigurationsfehler:'
    assert_absent "${case_root}/docker.log"
    [[ "$(cat -- "${case_root}/unrelated.txt")" == 'Unbeteiligter Inhalt' ]] || fail 'Symbolisches Link-Ziel überschrieben'
    pass 'Symbolischer Link als Protokolldatei abgewiesen'
else
    printf 'SKIP: Konfigurationsfälle mit symbolischen Links sind hier nicht verfügbar\n'
fi

prepare_case new-target 0
backup="${case_root}/New backup with spaces"
destination="${backup}"
export MOCK_BACKUP="${backup}" MOCK_DEST="${destination}"
set_config backup_dir "${case_root}/unused/../New backup with spaces"
set_config project_dir "${project}/."
set_config project_service_name ''
set_config postgres_service_name ''
export MOCK_DOCKER=fallback
run_backup || fail 'Neues Ziel mit ausschließlicher Containerkonfiguration'
assert_backup
if grep -Fq 'compose ps' "${case_root}/docker.log"; then fail 'Leerer Service fragt alle Container ab'; fi
pass 'Neues Sicherungsziel und explizite Containernamen bleiben nutzbar'

prepare_case compose-service-names 0
set_config project_service_name _web
set_config postgres_service_name -db
run_backup || fail 'Gültige Compose-Servicenamen abgewiesen'
assert_backup
grep -Fq 'compose exec -T -- -db pg_dump' "${case_root}/docker.log" || fail 'Servicename nicht als eigenes Argument übergeben'
pass 'Compose-Servicenamen mit führendem Unterstrich oder Bindestrich bleiben nutzbar'

printf 'Alle Regressionstests erfolgreich.\n'
