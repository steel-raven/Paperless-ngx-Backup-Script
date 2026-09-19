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
    if [[ "$1 $2" == 'compose ps' ]]; then
        [[ "${MOCK_DOCKER}" != stopped && "${MOCK_DOCKER}" != fallback ]] || return 0
        [[ "${MOCK_DOCKER}" != no-db || "${*: -1}" != db ]] || return 0
        printf 'test-container\n'
    elif [[ "$1" == inspect ]]; then
        [[ "${MOCK_DOCKER}" == fallback ]] && printf 'true\n' || printf 'false\n'
    else
        if [[ "$1 $2" == 'compose exec' ]]; then
            [[ "$3" == -T ]] || return 99
            shift 4
        elif [[ "$1" == exec ]]; then
            shift 2
        else
            return 99
        fi
        case "$1" in
            document_exporter)
                [[ "${MOCK_DOCKER}" != export-fail ]] || return 9
                mkdir -p -- "${MOCK_PROJECT}/export"
                if [[ "${MOCK_DOCKER}" != empty-export ]]; then
                    printf 'Export-Daten\n' > "${MOCK_PROJECT}/export/document.txt"
                fi
                ;;
            pg_dump)
                [[ "${MOCK_DOCKER}" != dump-fail ]] || return 9
                [[ "${MOCK_DOCKER}" != empty-dump ]] || return 0
                printf 'SQL-Dump\n'
                ;;
            *) return 99 ;;
        esac
    fi
}
rsync() {
    [[ $# -eq 5 && "$1" == -a && "$2" == --delete && "$3" == -- ]] || return 99
    [[ "$4" == "${MOCK_PROJECT}/export" && "${5%/}" == "${MOCK_DEST}" ]] || return 99
    [[ "${MOCK_RSYNC}" != fail ]] || return 23
    command cp -a -- "$4" "$5/"
}
chown() {
    [[ $# -eq 4 && "$1" == -R && "$2" == -- && "${4%/}" == "${MOCK_DEST}" ]] || return 99
}
rm() {
    # Vor jeder echten Testlöschung den aufgelösten Pfad auf den isolierten Testbereich begrenzen.
    [[ $# -eq 3 && "$1" == -rf && "$2" == -- && -d "$3" && ! -L "$3" ]] || return 99
    local resolved_target resolved_backup
    resolved_target="$(cd -- "$3" && pwd -P)" || return 99
    resolved_backup="$(cd -- "${MOCK_BACKUP}" && pwd -P)" || return 99
    [[ "${resolved_target}" == "${test_root}/"* && "${resolved_target%/*}" == "${resolved_backup}" ]] || return 99
    printf '%s\n' "${resolved_target}" >> "${MOCK_CASE}/deleted.log"
    [[ "${MOCK_DELETE}" != fail ]] || return 13
    command rm -rf -- "${resolved_target}"
}
export -f wget dpkg date docker rsync chown rm

prepare_case() {
    case_root="${test_root}/$1"
    project="${case_root}/Project with spaces [data]"
    backup="${case_root}/Backup with spaces [data]"
    mkdir -p -- "${project}" "${backup}"
    export MOCK_CASE="${case_root}" MOCK_PROJECT="${project}" MOCK_BACKUP="${backup}"
    export MOCK_UPDATE=current MOCK_DOCKER=running MOCK_RSYNC=ok MOCK_DELETE=ok
    history="$2"
    destination="${backup}"
    if [[ "${history}" != 0 ]]; then
        destination="${backup}/2026-09-19T12-34-56"
    fi
    export MOCK_DEST="${destination}"
    # Nur benutzerspezifische Angaben ersetzen, den eigentlichen Skriptcode unverändert testen.
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
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
    case "${failure}" in
        *-fail) [[ "${status}" -ne 0 ]] || fail "Fehler verschluckt: ${failure}" ;;
        *) [[ "${status}" -eq 0 ]] || fail "Unerwarteter Abbruch: ${failure}"; assert_log 'Versionsbereinigung wird übersprungen' ;;
    esac
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

printf 'Alle Regressionstests erfolgreich.\n'
