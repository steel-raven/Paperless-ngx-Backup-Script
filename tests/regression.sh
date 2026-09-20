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
    for candidate in "${destination}"/.postgres-dump.sql.* "${destination}"/.Sicherungsinfo.txt.*; do
        assert_absent "${candidate}"
    done
}
pass() { printf 'PASS: %s\n' "$*"; }

# Alle externen Aktionen des Backup-Skripts werden durch lokale Testfunktionen ersetzt.
wget() {
    printf '%s\n' "$@" >> "${MOCK_CASE}/update-request.log"
    [[ $# -eq 5 && "$1 $2 $3 $4" == '--timeout=60 --tries=1 -q -O-' &&
       "$5" == 'https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases/latest/download/Paperless-ngx-Backup-Script.sh' ]] || return 99
    case "${MOCK_UPDATE}" in
        offline) return 4 ;;
        tls-error) return 5 ;;
        no-release) return 8 ;;
        empty) return 0 ;;
        malformed) printf '<html>Fehler</html>\n' ;;
        invalid-version) printf 'version="ungueltig"\n' ;;
        multiple-versions) printf 'version="1.1.0"\nversion="9.9.999"\n' ;;
        newer) printf 'version="9.9.999"\n' ;;
        stable) printf 'version="1.1.0"\n' ;;
        older) printf 'version="1.0.0"\n' ;;
        current|compare-fail) printf 'version="1.1.0~rc1"\n' ;;
        *) return 99 ;;
    esac
}
dpkg() {
    [[ $# -eq 4 && "$1" == --compare-versions && "$3" == gt ]] || return 99
    [[ "$4" == '1.1.0~rc1' ]] || return 99
    [[ "${MOCK_UPDATE}" != compare-fail ]] || return 2
    [[ "$2" == 9.9.999 || "$2" == 1.1.0 ]]
}
date() {
    if [[ "$*" == '+%Y-%m-%dT%H-%M-%S' ]]; then
        printf '2026-09-19T12-34-56\n'
    elif [[ "$*" == '+%Y-%m-%dT%H:%M:%S%z' ]]; then
        printf '2026-09-19T12:34:56+0200\n'
    else
        command date "$@"
    fi
}
docker() {
    printf '%s\n' "$*" >> "${MOCK_CASE}/docker.log"
    local ref format id state=true option
    if [[ "$1" == compose ]]; then
        shift
        [[ "$1" == --project-directory && "$2" == "${MOCK_PROJECT}" ]] || return 99
        shift 2
        while [[ "$1" != ps ]]; do
            option="$1"
            case "${option}" in
                -f) [[ -f "$2" ]] || return 99 ;;
                --env-file) [[ "$2" == /dev/null || -f "$2" ]] || return 99 ;;
                -p) [[ -n "$2" ]] || return 99 ;;
                *) return 99 ;;
            esac
            printf '%s\n%s\n' "${option}" "$2" >> "${MOCK_CASE}/compose-options.log"
            shift 2
        done
        [[ $# -eq 5 && "$1 $2 $3 $4" == 'ps --all -q --' ]] || return 99
        [[ -z "${COMPOSE_FILE:-}${COMPOSE_PROJECT_NAME:-}${COMPOSE_ENV_FILES:-}" ]] || return 99
        if [[ "${MOCK_DOCKER}" == probe-fail || "${MOCK_DOCKER}" == compose-fail ]]; then
            printf 'SIMULATED_DOCKER_PROBE_FAILURE\n' >&2
            return 7
        fi
        [[ "${MOCK_DOCKER}" != fallback ]] || return 0
        [[ "${MOCK_DOCKER}" != no-db || "${*: -1}" != db ]] || return 0
        if [[ "$5" == db || "$5" == -db ]]; then id="${MOCK_POSTGRES_ID}"; else id="${MOCK_PAPERLESS_ID}"; fi
        printf '%s\n' "${id}"
        [[ "${MOCK_DOCKER}" != multiple ]] || printf '%s\n' "${MOCK_POSTGRES_ID}"
    elif [[ "$1 $2" == 'context inspect' ]]; then
        printf '%s\n' "${MOCK_ENDPOINT}"
    elif [[ "$1" == inspect ]]; then
        [[ $# -eq 7 && "$2 $3 $4" == '--type container --format' && "$6" == -- ]] || return 99
        format="$5"
        ref="$7"
        if [[ "${MOCK_DOCKER}" == probe-fail ]]; then
            printf 'SIMULATED_DOCKER_INSPECT_FAILURE\n' >&2
            return 7
        fi
        case "${ref}" in
            Paperless-ngx|"${MOCK_PAPERLESS_ID}") id="${MOCK_PAPERLESS_ID}" ;;
            Paperless-ngx-PostgreSQL|"${MOCK_POSTGRES_ID}") id="${MOCK_POSTGRES_ID}" ;;
            *) return 99 ;;
        esac
        if [[ "${format}" == '{{.State.Running}} {{.Id}}' ]]; then
            [[ "${MOCK_DOCKER}" != stopped ]] || state=false
            [[ "${MOCK_DOCKER}" != no-db || "${id}" != "${MOCK_POSTGRES_ID}" ]] || state=false
            printf '%s %s\n' "${state}" "${id}"
        elif [[ "${format}" == '{{.Config.Image}}' ]]; then
            [[ "${MOCK_INFO}" != image-fail ]] || { printf 'SIMULATED_IMAGE_QUERY_FAILURE\n' >&2; return 7; }
            if [[ "${ref}" == "${MOCK_PAPERLESS_ID}" ]]; then
                printf 'ghcr.io/paperless-ngx/paperless-ngx:latest\n'
            else
                printf 'postgres:16\n'
            fi
        elif [[ "${format}" == '{{range .Mounts}}'* ]]; then
            [[ "${ref}" == "${MOCK_PAPERLESS_ID}" ]] || return 99
            case "${MOCK_MOUNT}" in
                absent) return 0 ;;
                mismatch) printf 'bind\037%s\037%s\037true\n' "${MOCK_PROJECT}" "${MOCK_EXPORT_CONTAINER}" ;;
                readonly) printf 'bind\037%s\037%s\037false\n' "${MOCK_EXPORT_HOST}" "${MOCK_EXPORT_CONTAINER}" ;;
                volume) printf 'volume\037%s\037%s\037true\n' "${MOCK_EXPORT_HOST}" "${MOCK_EXPORT_CONTAINER}" ;;
                malformed) printf 'kein gültiger Mount\n' ;;
                *) printf 'bind\037%s\037%s\037true\n' "${MOCK_EXPORT_HOST}" "${MOCK_EXPORT_CONTAINER}" ;;
            esac
            if [[ "${MOCK_MOUNT}" == nested ]]; then
                printf 'bind\037%s\037%s/private\037true\n' "${MOCK_PROJECT}" "${MOCK_EXPORT_CONTAINER}"
            elif [[ "${MOCK_MOUNT}" == shared ]]; then
                printf 'bind\037%s/private\037/data\037true\n' "${MOCK_EXPORT_HOST}"
            fi
        else
            return 99
        fi
    else
        [[ "$1" == exec ]] || return 99
        id="$2"
        shift 2
        case "$1" in
            python3)
                [[ "${id}" == "${MOCK_PAPERLESS_ID}" && $# -eq 4 && "$2 $3" == '-B -c' && "$4" == 'import runpy; print(runpy.run_path("/usr/src/paperless/src/paperless/version.py")["__full_version_str__"])' ]] || return 99
                case "${MOCK_INFO}" in
                    version-fail) printf 'SIMULATED_VERSION_QUERY_FAILURE\n' >&2; return 8 ;;
                    version-empty) return 0 ;;
                    version-invalid) printf 'latest\n' ;;
                    version-multiline) printf '2.20.0\nUNEXPECTED_OUTPUT\n' ;;
                    *) printf '2.20.0\n' ;;
                esac
                ;;
            document_exporter)
                [[ "${id}" == "${MOCK_PAPERLESS_ID}" && $# -eq 5 && "$2" == "${MOCK_EXPORT_CONTAINER}" && "$3 $4 $5" == '-d -p -z' ]] || return 99
                if [[ "${MOCK_DOCKER}" == export-fail ]]; then
                    printf 'SIMULATED_EXPORT_FAILURE\n' >&2
                    return 9
                fi
                if [[ "${MOCK_DOCKER}" != empty-export ]]; then
                    printf 'Export-Daten\n' > "${MOCK_EXPORT_HOST}/document.txt"
                fi
                ;;
            pg_dump)
                [[ "${id}" == "${MOCK_POSTGRES_ID}" ]] || return 99
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
                if [[ "${MOCK_INFO}" != headers-missing ]]; then
                    printf '%s\n' '--' '-- PostgreSQL database dump' '--' '' '\restrict TEST_DUMP_KEY' '' '-- Dumped from database version 16.4 (Debian 16.4-1)' '-- Dumped by pg_dump version 17.6'
                fi
                printf 'SQL-Dump\n'
                ;;
            *) return 99 ;;
        esac
    fi
}
rsync() {
    [[ $# -eq 5 && "$1" == -a && "$2" == --delete && "$3" == -- ]] || return 99
    [[ "$4" == "${MOCK_EXPORT_HOST}/" && "$5" == "${MOCK_DEST}/export/" ]] || return 99
    if [[ "${MOCK_RSYNC}" == fail ]]; then printf 'SIMULATED_RSYNC_FAILURE\n' >&2; return 23; fi
    command mkdir -p -- "$5"
    command cp -a -- "$4." "$5"
}
chown() {
    [[ $# -eq 4 && "$1" == -R && "$2" == -- && "${4%/}" == "${MOCK_DEST}" ]] || return 99
    if [[ "${MOCK_CHOWN}" == fail ]]; then printf 'SIMULATED_CHOWN_FAILURE\n' >&2; return 12; fi
    : > "${MOCK_CASE}/chown-complete"
}
cp() {
    [[ $# -eq 4 && "$1" == -p && "$2" == -- && "$3" == "${MOCK_CASE}/"* && "${4%/}" == "${MOCK_DEST}" ]] || return 99
    if [[ "${MOCK_COPY}" == fail || ( "${MOCK_COPY}" == env-fail && "$3" == *.env ) ]]; then
        printf 'SIMULATED_COPY_FAILURE\n' >&2
        return 11
    fi
    printf '%s\n' "${3##*/}" >> "${MOCK_CASE}/copied.log"
    command cp "$@"
}
mv() {
    if [[ $# -eq 4 && "$1 $2" == '-fT --' && "$3" == "${MOCK_BACKUP}/.paperless-preflight."*/source && "$4" == "${3%/*}/target" ]]; then
        [[ "${MOCK_PREFLIGHT}" != rename-fail ]] || { printf 'SIMULATED_PREFLIGHT_RENAME_FAILURE\n' >&2; return 14; }
        command mv "$@" || return
        [[ "${MOCK_PREFLIGHT}" != readback-fail ]] || printf 'corrupt\n' > "$4"
        return 0
    fi
    if [[ $# -eq 4 && "$1 $2" == '-fT --' && "$3" == "${MOCK_DEST}/.Sicherungsinfo.txt."* && "$4" == "${MOCK_DEST}/Sicherungsinfo.txt" ]]; then
        [[ "${MOCK_INFO}" != rename-fail ]] || { printf 'SIMULATED_INFO_RENAME_FAILURE\n' >&2; return 19; }
        [[ -f "${MOCK_CASE}/chown-complete" ]] || return 99
        command mv "$@"
        return $?
    fi
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
    if [[ $# -eq 4 && "$1 $2" == '-f --' && "$3" == "${MOCK_BACKUP}/.paperless-preflight."*/source && "$4" == "${3%/*}/target" ]]; then
        [[ "$(realpath -m -- "$3")" == "${test_root}/"* && "$(realpath -m -- "$4")" == "${test_root}/"* ]] || return 99
        [[ "${MOCK_PREFLIGHT}" != cleanup-fail ]] || { printf 'SIMULATED_PREFLIGHT_CLEANUP_FAILURE\n' >&2; return 17; }
        command rm "$@"
        return $?
    fi
    if [[ $# -eq 3 && "$1" == -f && "$2" == -- && ( "$3" == "${MOCK_DEST}/.postgres-dump.sql."* || "$3" == "${MOCK_DEST}/.Sicherungsinfo.txt."* || "$3" == "${MOCK_DEST}/Sicherungsinfo.txt" ) ]]; then
        [[ "$(realpath -m -- "$3")" == "${test_root}/"* && ! -L "$3" ]] || return 99
        [[ "${MOCK_INFO}" != remove-fail || "$3" != "${MOCK_DEST}/Sicherungsinfo.txt" ]] || { printf 'SIMULATED_INFO_REMOVE_FAILURE\n' >&2; return 20; }
        command rm -f -- "$3"
        return $?
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
command() {
    if [[ "${1:-}" == -v && " ${MOCK_MISSING:-} " == *" $2 "* ]]; then return 1; fi
    builtin command "$@"
}
realpath() {
    [[ "${MOCK_CAPABILITY:-}" != realpath || "$*" != '-m -- /' ]] || return 2
    command realpath "$@"
}
stat() {
    [[ "${MOCK_CAPABILITY:-}" != stat || "$*" != '-c %h -- /' ]] || { printf 'unsupported\n'; return 0; }
    command stat "$@"
}
find() {
    [[ "${MOCK_CAPABILITY:-}" != find || "$*" != '/ -maxdepth 0 -mtime +0 -print' ]] || return 2
    command find "$@"
}
mktemp() {
    if [[ "${MOCK_INFO:-}" == create-fail && "${*: -1}" == "${MOCK_DEST}/.Sicherungsinfo.txt."* ]]; then
        printf 'SIMULATED_INFO_CREATE_FAILURE\n' >&2
        return 21
    fi
    if [[ "${MOCK_PREFLIGHT:-}" == create-fail && "${*: -1}" == "${MOCK_BACKUP}/.paperless-preflight."* ]]; then
        printf 'SIMULATED_PREFLIGHT_WRITE_DENIED\n' >&2
        return 18
    fi
    command mktemp "$@"
}
printf() {
    if [[ "${MOCK_INFO:-}" == write-fail && "$1" == 'Paperless-ngx – Informationen zu dieser Sicherung\n\n' ]]; then
        builtin printf 'SIMULATED_INFO_WRITE_FAILURE\n' >&2
        return 22
    fi
    builtin printf "$@"
}
export -f printf
findmnt() {
    printf '%q ' "$@" >> "${MOCK_CASE}/findmnt.log"
    printf '\n' >> "${MOCK_CASE}/findmnt.log"
    [[ "$1 $2 $3 $4 $5" == '--kernel --noheadings --raw --output ID' ]] || return 99
    local changed=false dump_candidate
    [[ ! -f "${MOCK_BACKUP}/Protokoll_der_letzten_Sicherung.log" ]] || changed=true
    if [[ "${MOCK_TARGET_MOUNT}" == disappear && "${changed}" == true ]]; then return 1; fi
    if [[ "${MOCK_TARGET_MOUNT}" == after-export && -f "${MOCK_EXPORT_HOST}/document.txt" ]]; then return 1; fi
    if [[ "${MOCK_TARGET_MOUNT}" == after-dump ]]; then
        for dump_candidate in "${MOCK_DEST}"/.postgres-dump.sql.*; do [[ ! -s "${dump_candidate}" ]] || return 1; done
    fi
    if [[ "${MOCK_TARGET_MOUNT}" == before-cleanup && -f "${MOCK_CASE}/chown-complete" ]]; then return 1; fi
    if [[ "$6" == --mountpoint ]]; then
        [[ $# -eq 11 && "$7" == "${MOCK_EXPECTED_MOUNT}" && "$8" == --source && "$9" == "${MOCK_EXPECTED_SOURCE}" && "${10} ${11}" == '--options rw' ]] || return 99
        if [[ "${MOCK_TARGET_MOUNT}" == mountpoint-removed ]]; then
            [[ "${MOCK_EXPECTED_MOUNT}" == "${MOCK_CASE}/Gone medium" ]] || return 99
            command rmdir -- "${MOCK_EXPECTED_MOUNT}" || return 99
        fi
        case "${MOCK_TARGET_MOUNT}" in
            missing|wrong-source|readonly|query-fail) return 1 ;;
            empty) return 0 ;;
            multiple) printf '1234\n5678\n'; return 0 ;;
            malformed) printf 'not-an-id\n'; return 0 ;;
        esac
    elif [[ "$6" == --target ]]; then
        [[ $# -eq 7 && -e "$7" && "$7" == "${MOCK_CASE}"* ]] || return 99
        [[ "${MOCK_TARGET_MOUNT}" != nested ]] || { printf '5678\n'; return 0; }
    else
        return 99
    fi
    if [[ "${MOCK_TARGET_MOUNT}" == remounted && "${changed}" == true ]]; then printf '5678\n'; else printf '1234\n'; fi
}
export -f wget dpkg date docker rsync chown cp mv tee mkdir rm command realpath stat find mktemp findmnt

prepare_case() {
    case_root="${test_root}/$1"
    project="${case_root}/Project with spaces [data]"
    backup="${case_root}/Backup with spaces [data]"
    mkdir -p -- "${project}/export" "${backup}"
    printf 'services: {}\n' > "${project}/compose.yaml"
    export MOCK_CASE="${case_root}" MOCK_PROJECT="${project}" MOCK_BACKUP="${backup}"
    export MOCK_UPDATE=current MOCK_DOCKER=running MOCK_RSYNC=ok MOCK_DELETE=ok
    export MOCK_CHOWN=ok MOCK_COPY=ok MOCK_MOVE=ok MOCK_LOGGER=ok
    export MOCK_INFO=ok
    export MOCK_PAPERLESS_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    export MOCK_POSTGRES_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    export MOCK_EXPORT_HOST="${project}/export" MOCK_EXPORT_CONTAINER=/usr/src/paperless/export
    export MOCK_MOUNT=ok MOCK_ENDPOINT=unix:///var/run/docker.sock
    export MOCK_MISSING='' MOCK_CAPABILITY='' MOCK_PREFLIGHT=ok MOCK_TARGET_MOUNT=ok
    export MOCK_EXPECTED_MOUNT="${case_root}" MOCK_EXPECTED_SOURCE=UUID=test-usb
    unset DOCKER_HOST DOCKER_CONTEXT COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_ENV_FILES
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
set_config_array() {
    local key="$1" line replaced=false
    shift
    while IFS= read -r line; do
        if [[ "${replaced}" == false && "${line}" == "${key}="* ]]; then
            printf '%s=(' "${key}"
            if [[ $# -gt 0 ]]; then printf ' %q' "$@"; fi
            printf ' )\n'
            replaced=true
        else
            printf '%s\n' "${line}"
        fi
    done < "${case_root}/runner with spaces.sh" > "${case_root}/configured.sh"
    command mv -- "${case_root}/configured.sh" "${case_root}/runner with spaces.sh"
}
assert_no_export_started() {
    if [[ -f "${case_root}/docker.log" ]] && grep -q '^exec ' "${case_root}/docker.log"; then
        fail 'Export oder Dump trotz fehlgeschlagener Vorprüfung gestartet'
    fi
}
assert_backup() {
    assert_file "${destination}/export/document.txt"
    assert_file "${destination}/postgres-dump.sql"
    grep -Fxq 'SQL-Dump' "${destination}/postgres-dump.sql" || fail 'Dump-Inhalt falsch'
    assert_file "${destination}/Sicherungsinfo.txt"
    assert_no_dump_temp
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

for update_mode in current older newer stable offline tls-error no-release empty malformed invalid-version multiple-versions; do
    prepare_case "update-${update_mode}" 0
    export MOCK_UPDATE="${update_mode}"
    run_backup || fail "Update-Modus ${update_mode}"
    assert_backup
    grep -Fxq 'https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases/latest/download/Paperless-ngx-Backup-Script.sh' "${case_root}/update-request.log" || fail 'Falsche Updatequelle'
    if grep -Fq -- '--no-check-certificate' "${case_root}/update-request.log"; then fail 'TLS-Pruefung deaktiviert'; fi
    if [[ "${update_mode}" == newer || "${update_mode}" == stable ]]; then
        assert_log 'Auf GitHub steht ein Update'
        assert_saved_log 'Link: https://github.com/steel-raven/Paperless-ngx-Backup-Script/releases'
    elif [[ "${update_mode}" == current || "${update_mode}" == older ]]; then
        if grep -Eq 'Auf GitHub steht ein Update|Updateprüfung wird übersprungen' "${case_root}/output.log"; then fail 'Unzutreffender Updatehinweis'; fi
    else
        assert_log 'Die Updateprüfung wird übersprungen'
        grep -Fq 'Die Updateprüfung wird übersprungen' "${backup}/Protokoll_der_letzten_Sicherung.log" || fail 'Update-Hinweis fehlt in Protokolldatei'
    fi
    pass "Updateprüfung: ${update_mode}; Sicherung abgeschlossen"
done

prepare_case fallback 0
export MOCK_DOCKER=fallback
set_config docker_mode container
run_backup || fail 'Containername als Rückfall'
assert_backup
pass 'Docker-Containername im expliziten Container-Modus'

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
assert_absent "${destination}/Sicherungsinfo.txt"

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
# Minimaler Dump für den exakten Vergleich von SQL- und Protokollausgaben.
export MOCK_DOCKER=dump-warning MOCK_INFO=headers-missing
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
            export MOCK_COPY=fail
            [[ "${failure}" != env-copy ]] || export MOCK_COPY=env-fail
            expected_status=11; diagnostic=SIMULATED_COPY_FAILURE ;;
        chown) export MOCK_CHOWN=fail; expected_status=12; diagnostic=SIMULATED_CHOWN_FAILURE ;;
        probe) export MOCK_DOCKER=probe-fail; expected_status=1; diagnostic=SIMULATED_DOCKER_PROBE_FAILURE ;;
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
    assert_absent "${project}/export/document.txt"
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

    prepare_case config-symlink-parent 0
    mkdir -p -- "${case_root}/External/deep"
    printf 'Richtige Konfiguration\n' > "${case_root}/External/chosen.conf"
    printf 'Falsche Konfiguration\n' > "${project}/chosen.conf"
    ln -s -- "${case_root}/External/deep" "${project}/config-link"
    set_config_array additional_config_files config-link/../chosen.conf
    run_backup || fail 'Konfigurationspfad mit Verzeichnislink und ..'
    command cmp -- "${case_root}/External/chosen.conf" "${destination}/chosen.conf" || fail 'Falsche Datei nach Auflösung von Verzeichnislink und ..'
    pass 'Konfigurationspfade mit Verzeichnislink und .. bleiben korrekt'
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
if grep -Fq 'compose ' "${case_root}/docker.log"; then fail 'Leerer Service fragt alle Container ab'; fi
pass 'Neues Sicherungsziel und explizite Containernamen bleiben nutzbar'

prepare_case compose-service-names 0
set_config project_service_name _web
set_config postgres_service_name -db
run_backup || fail 'Gültige Compose-Servicenamen abgewiesen'
assert_backup
grep -Fq 'ps --all -q -- -db' "${case_root}/docker.log" || fail 'Servicename nicht als eigenes Argument übergeben'
pass 'Compose-Servicenamen mit führendem Unterstrich oder Bindestrich bleiben nutzbar'

# Compose-/Portainer-Auswahl und explizite Dateipfade.
prepare_case auto-portainer 0
command rm -f -- "${project}/compose.yaml"
printf 'Fremdes Projekt\n' > "${case_root}/compose.yaml"
run_backup || fail 'Portainer ohne lokale Compose-Datei'
assert_backup
assert_log 'Docker-Betriebsart: container'
assert_log 'Keine lokalen Konfigurationsdateien gefunden'
if grep -q '^compose ' "${case_root}/docker.log"; then fail 'Compose im übergeordneten Verzeichnis gesucht'; fi
pass 'Auto-Modus verwendet ohne lokale Compose-Datei nur die angegebenen Container'

prepare_case explicit-container 0
set_config docker_mode container
export MOCK_DOCKER=compose-fail
run_backup || fail 'Container-Modus hängt von Compose ab'
assert_backup
if grep -q '^compose ' "${case_root}/docker.log"; then fail 'Compose trotz Container-Modus gestartet'; fi
pass 'Container-Modus benötigt auch bei vorhandener YAML-Datei kein Compose'

for selection_failure in compose-fail multiple no-db stopped; do
    prepare_case "selection-${selection_failure}" 30
    make_version 2020-01-01T00-00-00 yes 45
    export MOCK_DOCKER="${selection_failure}"
    if run_backup; then fail "Ungültige Containerauswahl akzeptiert: ${selection_failure}"; fi
    assert_no_export_started
    assert_absent "${destination}/.paperless-ngx-backup"
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_saved_log 'FEHLER: Datensicherung nicht erfolgreich'
    if grep -Fq -- '-- Paperless-ngx' "${case_root}/docker.log"; then fail 'Stillschweigender Fallback auf Containername'; fi
    pass "Vor beiden Exporten eindeutig abgebrochen: ${selection_failure}"
done

prepare_case compose-overrides 0
printf 'Override\n' > "${project}/compose.override.yml"
printf 'Variablen\n' > "${project}/.env"
export COMPOSE_FILE=/unrelated/project.yaml COMPOSE_PROJECT_NAME=unrelated COMPOSE_ENV_FILES=/unrelated/settings
run_backup || fail 'Lokale Compose-Dateien und Override'
assert_backup
for lookup in 1 2; do
    printf '%s\n' -f "${project}/compose.yaml" -f "${project}/compose.override.yml" --env-file "${project}/.env"
done > "${case_root}/expected-options.log"
command cmp -- "${case_root}/expected-options.log" "${case_root}/compose-options.log" || fail 'Falsche automatische Compose-Dateiauswahl'
pass 'Lokale Compose-Datei, Override und .env explizit gewählt; fremde COMPOSE-Variablen isoliert'

prepare_case explicit-config-paths 0
mkdir -- "${case_root}/External configuration"
base_file="${case_root}/External configuration/base stack.conf"
override_file="${case_root}/External configuration/overrides.conf"
env_one="${case_root}/External configuration/variables one.conf"
env_two="${case_root}/External configuration/variables two.conf"
extra_file="${case_root}/External configuration/Portainer settings.txt"
for file in "${base_file}" "${override_file}" "${env_one}" "${env_two}" "${extra_file}"; do printf 'Testinhalt\n' > "${file}"; done
set_config docker_mode compose
set_config compose_project_name paperless-custom
set_config_array compose_files '../External configuration/base stack.conf' "${override_file}"
set_config_array compose_env_files "${env_one}" "${env_two}"
set_config_array additional_config_files "${extra_file}" "${base_file}"
run_backup || fail 'Explizite Compose- und Konfigurationspfade'
assert_backup
for file in "${base_file}" "${override_file}" "${env_one}" "${env_two}" "${extra_file}"; do
    command cmp -- "${file}" "${destination}/${file##*/}" || fail 'Explizite Konfigurationsdatei fehlt'
done
for lookup in 1 2; do
    printf '%s\n' -f "${base_file}" -f "${override_file}" -p paperless-custom --env-file "${env_one}" --env-file "${env_two}"
done > "${case_root}/expected-options.log"
command cmp -- "${case_root}/expected-options.log" "${case_root}/compose-options.log" || fail 'Compose-Argumentreihenfolge oder Dateipfad verändert'
[[ "$(grep -Fxc 'base stack.conf' "${case_root}/copied.log")" -eq 1 ]] || fail 'Doppelt angegebene Datei mehrfach kopiert'
pass 'Explizite Compose-/ENV-Dateien samt Reihenfolge, Projektname und weiteren Konfigurationen'

prepare_case portainer-stack-copy 0
command rm -f -- "${project}/compose.yaml"
printf 'Portainer-Stack\n' > "${case_root}/portainer-stack.yaml"
set_config docker_mode container
set_config_array additional_config_files "${case_root}/portainer-stack.yaml"
run_backup || fail 'Portainer-Stack separat sichern'
assert_backup
command cmp -- "${case_root}/portainer-stack.yaml" "${destination}/portainer-stack.yaml" || fail 'Portainer-Stack fehlt'
pass 'Portainer-Stack außerhalb des Projektverzeichnisses wird ausdrücklich mitgesichert'

for invalid in mode compose-file env-file extra-file name-collision reserved-name config-in-export compose-missing compose-project container-options host-relative host-root host-project host-backup host-media container-relative container-parent container-media; do
    prepare_case "new-config-${invalid}" 0
    printf 'Bestehendes Protokoll\n' > "${backup}/Protokoll_der_letzten_Sicherung.log"
    case "${invalid}" in
        mode) set_config docker_mode wrong ;;
        compose-file) set_config_array compose_files missing.yaml ;;
        env-file) set_config_array compose_env_files missing.env ;;
        extra-file) set_config_array additional_config_files missing.conf ;;
        name-collision)
            printf 'Anderes Projekt\n' > "${case_root}/compose.yaml"
            set_config_array additional_config_files "${case_root}/compose.yaml" ;;
        reserved-name)
            printf 'Fremde SQL-Datei\n' > "${case_root}/postgres-dump.sql"
            set_config_array additional_config_files "${case_root}/postgres-dump.sql" ;;
        config-in-export)
            printf 'Nicht löschen\n' > "${project}/export/required.env"
            set_config_array additional_config_files export/required.env ;;
        compose-missing) command rm -f -- "${project}/compose.yaml"; set_config docker_mode compose ;;
        compose-project) set_config compose_project_name 'Ungültiger Name' ;;
        container-options) set_config docker_mode container; set_config_array compose_files compose.yaml ;;
        host-relative) set_config export_host_dir relative/export ;;
        host-root) set_config export_host_dir / ;;
        host-project) set_config export_host_dir "${project}" ;;
        host-backup) set_config export_host_dir "${backup}/export" ;;
        host-media) set_config export_host_dir "${project}/media" ;;
        container-relative) set_config export_container_dir ../export ;;
        container-parent) set_config export_container_dir /usr/src/paperless ;;
        container-media) set_config export_container_dir /usr/src/paperless/media ;;
    esac
    if run_backup; then fail "Ungültige neue Konfiguration akzeptiert: ${invalid}"; fi
    assert_log 'Konfigurationsfehler:'
    assert_absent "${case_root}/docker.log"
    [[ "$(cat -- "${backup}/Protokoll_der_letzten_Sicherung.log")" == 'Bestehendes Protokoll' ]] || fail 'Vorprüfung hat Protokoll verändert'
    pass "Neue Konfiguration vor Schreibzugriffen abgewiesen: ${invalid}"
done

prepare_case custom-export 0
export MOCK_EXPORT_HOST="${case_root}/Exports with spaces" MOCK_EXPORT_CONTAINER='/exports for Paperless'
mkdir -- "${MOCK_EXPORT_HOST}"
set_config export_host_dir "${MOCK_EXPORT_HOST}"
set_config export_container_dir "${MOCK_EXPORT_CONTAINER}"
run_backup || { cat -- "${case_root}/output.log"; fail 'Abweichende Exportpfade'; }
assert_backup
assert_absent "${destination}/Exports with spaces"
pass 'Abweichende Host-/Containerpfade mit Leerzeichen landen stets unter backup/export'

for mount_failure in absent mismatch readonly volume nested shared malformed; do
    prepare_case "mount-${mount_failure}" 30
    make_version 2020-01-01T00-00-00 yes 45
    export MOCK_MOUNT="${mount_failure}"
    if run_backup; then fail "Unsichere Mount-Zuordnung akzeptiert: ${mount_failure}"; fi
    assert_no_export_started
    assert_saved_log 'Schritt: Prüfung des Export-Mounts'
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_absent "${destination}/.paperless-ngx-backup"
    pass "Mount-Prüfung stoppt vor document_exporter -d: ${mount_failure}"
done

for remote_mode in host context; do
    prepare_case "remote-${remote_mode}" 0
    if [[ "${remote_mode}" == host ]]; then export DOCKER_HOST=ssh://example.invalid; else export MOCK_ENDPOINT=tcp://example.invalid:2376; fi
    if run_backup; then fail 'Entfernter Docker-Daemon mit lokalen Hostpfaden akzeptiert'; fi
    assert_no_export_started
    assert_log 'lokaler Docker-Daemon mit Unix-Socket'
    pass "Entfernter Docker-Daemon vor Export abgewiesen: ${remote_mode}"
done

for missing in dirname date realpath stat mkdir rmdir tee docker ls rsync mktemp mv cp chown rm find cat; do
    prepare_case "missing-${missing}" 30
    printf 'Vorheriges Protokoll\n' > "${backup}/Protokoll_der_letzten_Sicherung.log"
    export MOCK_MISSING="${missing}"
    if run_backup; then fail "Fehlendes Pflichtprogramm akzeptiert: ${missing}"; fi
    assert_log "Benötigte Programme fehlen: ${missing}"
    assert_no_export_started
    assert_absent "${destination}"
    [[ "$(< "${backup}/Protokoll_der_letzten_Sicherung.log")" == 'Vorheriges Protokoll' ]] || fail 'Vorprüfung überschreibt altes Protokoll'
    pass "Fehlendes Pflichtprogramm vor Schreibzugriffen erkannt: ${missing}"
done

for optional in wget grep cut dpkg findmnt; do
    prepare_case "missing-optional-${optional}" 0
    export MOCK_MISSING="${optional}"
    run_backup || fail "Optionales Programm verhindert Backup: ${optional}"
    assert_backup
    [[ "${optional}" == findmnt ]] || assert_saved_log 'Die Updateprüfung wird übersprungen'
    assert_absent "${case_root}/findmnt.log"
    pass "Optionales Programm blockiert Backup nicht: ${optional}"
done
prepare_case update-comparison-fails 0
export MOCK_UPDATE=compare-fail
run_backup || fail 'Fehler im Versionsvergleich verhindert Backup'
assert_saved_log 'Der Versionsvergleich ist fehlgeschlagen'
assert_backup
pass 'Fehlgeschlagener Versionsvergleich wird als Hinweis protokolliert'

for capability in realpath stat find; do
    prepare_case "unsupported-${capability}" 30
    export MOCK_CAPABILITY="${capability}"
    if run_backup; then fail "Ungeeignetes Programm akzeptiert: ${capability}"; fi
    assert_log 'Vorprüfungsfehler:'
    assert_no_export_started
    assert_absent "${destination}"
    pass "Erforderliche Programmoptionen geprüft: ${capability}"
done

for probe_failure in create-fail rename-fail readback-fail cleanup-fail; do
    prepare_case "write-probe-${probe_failure}" 30
    printf 'Vorheriges Protokoll\n' > "${backup}/Protokoll_der_letzten_Sicherung.log"
    make_version 2020-01-01T00-00-00 yes 45
    export MOCK_PREFLIGHT="${probe_failure}"
    if run_backup; then fail "Fehlgeschlagener Schreibtest akzeptiert: ${probe_failure}"; fi
    assert_log 'Vorprüfungsfehler:'
    assert_no_export_started
    assert_absent "${destination}"
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    [[ "$(< "${backup}/Protokoll_der_letzten_Sicherung.log")" == 'Vorheriges Protokoll' ]] || fail 'Schreibtest überschreibt altes Protokoll'
    if [[ "${probe_failure}" != cleanup-fail ]]; then
        for probe_path in "${backup}"/.paperless-preflight.*; do assert_absent "${probe_path}"; done
    fi
    pass "Schreibtestfehler vor Export, altes Protokoll erhalten: ${probe_failure}"
done

for invalid in source-only mount-only relative root equal outside missing-dir control; do
    prepare_case "invalid-target-${invalid}" 0
    set_config backup_mountpoint "${case_root}"
    set_config backup_mount_source UUID=test-usb
    case "${invalid}" in
        source-only) set_config backup_mountpoint '' ;;
        mount-only) set_config backup_mount_source '' ;;
        relative) set_config backup_mountpoint relative/path ;;
        root) set_config backup_mountpoint / ;;
        equal) set_config backup_mountpoint "${backup}" ;;
        outside) set_config backup_mountpoint "${project}" ;;
        missing-dir) set_config backup_mountpoint "${case_root}/missing" ;;
        control) set_config backup_mount_source $'server:/share\nother' ;;
    esac
    if run_backup; then fail "Ungültiger Zielschutz akzeptiert: ${invalid}"; fi
    assert_log 'Konfigurationsfehler:'
    assert_no_export_started
    assert_absent "${backup}/Protokoll_der_letzten_Sicherung.log"
    pass "Ungültige Angaben zum Sicherungsmedium abgewiesen: ${invalid}"
done

for mount_failure in missing wrong-source readonly query-fail empty multiple malformed nested; do
    prepare_case "target-${mount_failure}" 30
    set_config backup_mountpoint "${case_root}"
    set_config backup_mount_source UUID=test-usb
    printf 'Vorheriges Protokoll\n' > "${backup}/Protokoll_der_letzten_Sicherung.log"
    export MOCK_TARGET_MOUNT="${mount_failure}"
    if run_backup; then fail "Ungeeignetes Sicherungsmedium akzeptiert: ${mount_failure}"; fi
    assert_log 'Vorprüfungsfehler:'
    assert_no_export_started
    assert_absent "${destination}"
    [[ "$(< "${backup}/Protokoll_der_letzten_Sicherung.log")" == 'Vorheriges Protokoll' ]] || fail 'Mountprüfung überschreibt altes Protokoll'
    pass "Sicherungsmedium vor Schreibzugriffen abgewiesen: ${mount_failure}"
done

prepare_case target-missing-findmnt 0
set_config backup_mountpoint "${case_root}"
set_config backup_mount_source UUID=test-usb
export MOCK_MISSING=findmnt
if run_backup; then fail 'Aktiver Mountschutz ohne findmnt akzeptiert'; fi
assert_log 'Benötigte Programme fehlen: findmnt'
assert_no_export_started
pass 'findmnt ist nur bei eingeschaltetem Zielschutz erforderlich'

prepare_case target-absent-new-directory 0
set_config backup_mountpoint "${case_root}"
set_config backup_mount_source UUID=test-usb
set_config backup_dir "${case_root}/not-created/backup"
export MOCK_TARGET_MOUNT=missing
if run_backup; then fail 'Fehlendes Sicherungsmedium akzeptiert'; fi
assert_absent "${case_root}/not-created"
assert_no_export_started
pass 'Fehlendes Medium führt auch nicht zur Anlage eines neuen Backup-Ordners'

for source_kind in uuid smb nfs; do
    prepare_case "target-success-${source_kind}" 30
    case "${source_kind}" in
        uuid) export MOCK_EXPECTED_SOURCE=UUID=test-usb ;;
        smb) export MOCK_EXPECTED_SOURCE='//server/Backup with spaces' ;;
        nfs) export MOCK_EXPECTED_SOURCE='server:/Backup with spaces' ;;
    esac
    set_config backup_mountpoint "${case_root}"
    set_config backup_mount_source "${MOCK_EXPECTED_SOURCE}"
    make_version 2020-01-01T00-00-00 yes 45
    run_backup || { cat -- "${case_root}/output.log"; fail "Erlaubtes Sicherungsmedium: ${source_kind}"; }
    assert_backup
    assert_absent "${backup}/2020-01-01T00-00-00"
    for probe_path in "${backup}"/.paperless-preflight.*; do assert_absent "${probe_path}"; done
    pass "Sicherung und Bereinigung auf geprüftem Medium: ${source_kind}"
done

for change in disappear remounted; do
    prepare_case "target-changed-${change}" 30
    set_config backup_mountpoint "${case_root}"
    set_config backup_mount_source UUID=test-usb
    export MOCK_TARGET_MOUNT="${change}"
    make_version 2020-01-01T00-00-00 yes 45
    if run_backup; then fail 'Mountwechsel während des Laufs akzeptiert'; fi
    assert_no_export_started
    assert_saved_log 'FEHLER: Datensicherung nicht erfolgreich'
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_absent "${destination}/.paperless-ngx-backup"
    pass "Erneute Mountprüfung vor Export erkennt Änderung: ${change}"
done

prepare_case target-new-subdirectories 0
export MOCK_BACKUP="${case_root}/New backup/with/subdirectories" MOCK_DEST="${case_root}/New backup/with/subdirectories"
backup="${MOCK_BACKUP}"
destination="${MOCK_DEST}"
set_config backup_dir "${backup}"
set_config backup_mountpoint "${case_root}"
set_config backup_mount_source UUID=test-usb
run_backup || { cat -- "${case_root}/output.log"; fail 'Neues Ziel auf geprüftem Medium'; }
assert_backup
pass 'Fehlende Unterverzeichnisse erst auf geprüftem Medium angelegt'

for stage in after-export after-dump before-cleanup; do
    prepare_case "target-lost-${stage}" 30
    set_config backup_mountpoint "${case_root}"
    set_config backup_mount_source UUID=test-usb
    make_version 2020-01-01T00-00-00 yes 45
    export MOCK_TARGET_MOUNT="${stage}"
    if run_backup; then fail "Mountverlust nicht erkannt: ${stage}"; fi
    assert_saved_log 'FEHLER: Datensicherung nicht erfolgreich'
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_absent "${destination}/.paperless-ngx-backup"
    assert_absent "${case_root}/deleted.log"
    if [[ "${stage}" == after-export ]]; then assert_absent "${destination}/export"; fi
    if [[ "${stage}" == after-dump ]]; then assert_absent "${destination}/postgres-dump.sql"; fi
    pass "Mountverlust verhindert folgende Schreib-/Löschschritte: ${stage}"
done

prepare_case target-mountpoint-removed 0
export MOCK_EXPECTED_MOUNT="${case_root}/Gone medium" MOCK_TARGET_MOUNT=mountpoint-removed
mkdir -- "${MOCK_EXPECTED_MOUNT}"
set_config backup_mountpoint "${MOCK_EXPECTED_MOUNT}"
set_config backup_mount_source UUID=test-usb
set_config backup_dir "${MOCK_EXPECTED_MOUNT}/backup"
if run_backup; then fail 'Zwischen Abfragen verschwundener Mountpfad akzeptiert'; fi
assert_log 'Der erwartete Mountpfad ist nicht mehr verfügbar'
assert_absent "${MOCK_EXPECTED_MOUNT}"
assert_no_export_started
pass 'Verschwundener Mountpfad wird nicht neu angelegt'

for history in 0 30; do
    prepare_case "info-content-${history}" "${history}"
    printf 'SECRET_TEST_VALUE=not-for-the-overview\n' > "${project}/.env"
    run_backup || { cat -- "${case_root}/output.log"; fail 'Versionsübersicht'; }
    assert_backup
    info="${destination}/Sicherungsinfo.txt"
    for expected in \
        'Sicherungsbeginn: 2026-09-19T12:34:56+0200' \
        'Datenübertragung abgeschlossen: 2026-09-19T12:34:56+0200' \
        'Skriptversion: 1.1.0~rc1' \
        'Skriptprojekt: https://github.com/steel-raven/Paperless-ngx-Backup-Script (steel-raven Fork)' \
        'Paperless-ngx-Version: 2.20.0' \
        'PostgreSQL-Serverversion (aus Dump): 16.4 (Debian 16.4-1)' \
        'pg_dump-Version (aus Dump): 17.6' \
        'Paperless-ngx-Image: ghcr.io/paperless-ngx/paperless-ngx:latest' \
        'PostgreSQL-Image: postgres:16' \
        '  .env – Konfigurationsdatei'; do
        grep -Fxq -- "${expected}" "${info}" || fail "Falsche/fehlende Versionsangabe: ${expected}"
    done
    if grep -Eq 'SECRET_TEST_VALUE|SQL-Dump' "${info}"; then fail 'Dateninhalt in Versionsübersicht'; fi
    if grep -q $'\r' "${info}"; then fail 'Windows-Zeilenumbrüche in Versionsübersicht'; fi
    if [[ "${history}" == 30 ]]; then assert_absent "${backup}/Sicherungsinfo.txt"; fi
    assert_saved_log 'Die Versionsübersicht wurde in [ Sicherungsinfo.txt ] gesichert.'
    pass "Versionsübersicht mit getrennten Server-/Clientversionen, Zeitversatz und Linux-Zeilenumbrüchen: ${history}"
done

for failure in version-fail version-empty version-invalid version-multiline image-fail headers-missing; do
    prepare_case "info-optional-${failure}" 0
    export MOCK_INFO="${failure}"
    run_backup || fail "Optionale Versionsabfrage verhindert Sicherung: ${failure}"
    assert_backup
    assert_saved_log 'nicht ermittelbar; Versionsübersicht bleibt an dieser Stelle unvollständig.'
    case "${failure}" in
        version-*) expected='Paperless-ngx-Version: nicht ermittelbar' ;;
        image-*) expected='Paperless-ngx-Image: nicht ermittelbar' ;;
        headers-*) expected='PostgreSQL-Serverversion (aus Dump): nicht ermittelbar' ;;
    esac
    grep -Fxq -- "${expected}" "${destination}/Sicherungsinfo.txt" || fail 'Unbekannte Version nicht gekennzeichnet'
    if grep -q 'UNEXPECTED_OUTPUT' "${destination}/Sicherungsinfo.txt"; then fail 'Mehrzeilige Metadaten übernommen'; fi
    pass "Fehlende/ungültige Zusatzinformationen verhindern keine Sicherung: ${failure}"
done

for failure in create-fail write-fail rename-fail; do
    prepare_case "info-required-${failure}" 30
    make_version 2020-01-01T00-00-00 yes 45
    export MOCK_INFO="${failure}"
    if run_backup; then fail "Schreibfehler der Versionsübersicht ignoriert: ${failure}"; fi
    assert_saved_log 'FEHLER: Datensicherung nicht erfolgreich'
    assert_absent "${destination}/Sicherungsinfo.txt"
    assert_no_dump_temp
    assert_absent "${destination}/.paperless-ngx-backup"
    assert_file "${backup}/2020-01-01T00-00-00/payload.txt"
    assert_absent "${case_root}/deleted.log"
    pass "Fehler beim Erstellen/Speichern der Übersicht verhindert Versionsbereinigung: ${failure}"
done

for failure in export dump copy chown logger; do
    prepare_case "info-stale-${failure}" 0
    run_backup || fail 'Erste Sicherung für Versionsübersicht fehlgeschlagen'
    assert_backup
    case "${failure}" in
        export) export MOCK_DOCKER=export-fail ;;
        dump) export MOCK_DOCKER=dump-fail ;;
        copy) export MOCK_COPY=fail ;;
        chown) export MOCK_CHOWN=fail ;;
        logger) export MOCK_LOGGER=fail ;;
    esac
    if run_backup; then fail "Fehler im Folgelauf ignoriert: ${failure}"; fi
    assert_absent "${destination}/Sicherungsinfo.txt"
    assert_no_dump_temp
    pass "Kein veralteter oder vorzeitiger Erfolgsstand nach fehlgeschlagenem Folgelauf: ${failure}"
done

prepare_case info-remove-fail 0
printf 'Paperless-ngx – Informationen zu dieser Sicherung\nVorheriger Stand\n' > "${destination}/Sicherungsinfo.txt"
export MOCK_INFO=remove-fail
if run_backup; then fail 'Nicht entfernbare alte Übersicht ignoriert'; fi
assert_no_export_started
grep -Fxq 'Vorheriger Stand' "${destination}/Sicherungsinfo.txt" || fail 'Alte Übersicht verändert'
pass 'Nicht entfernbare alte Übersicht stoppt vor dem Export'

for conflict in log config directory hardlink file; do
    prepare_case "info-conflict-${conflict}" 0
    case "${conflict}" in
        log) set_config logfile_name Sicherungsinfo.txt ;;
        config)
            printf 'Fremde Notizen\n' > "${case_root}/Sicherungsinfo.txt"
            set_config_array additional_config_files "${case_root}/Sicherungsinfo.txt" ;;
        directory) command mkdir -- "${destination}/Sicherungsinfo.txt" ;;
        file) printf 'Fremde Notizen\n' > "${destination}/Sicherungsinfo.txt" ;;
        hardlink)
            printf 'Fremde Notizen\n' > "${case_root}/notes.txt"
            ln -- "${case_root}/notes.txt" "${destination}/Sicherungsinfo.txt" ;;
    esac
    if run_backup; then fail "Konflikt mit Versionsübersicht übersehen: ${conflict}"; fi
    assert_no_export_started
    if [[ "${conflict}" == hardlink ]]; then
        grep -Fxq 'Fremde Notizen' "${case_root}/notes.txt" || fail 'Hardlink-Ziel verändert'
    elif [[ "${conflict}" == file ]]; then
        grep -Fxq 'Fremde Notizen' "${destination}/Sicherungsinfo.txt" || fail 'Fremde Datei verändert'
    fi
    pass "Versionsübersicht schützt reservierten Namen und fremde Dateien: ${conflict}"
done

prepare_case info-symlink 0
printf 'Fremde Notizen\n' > "${case_root}/notes.txt"
if ln -s -- "${case_root}/notes.txt" "${destination}/Sicherungsinfo.txt" 2>/dev/null && [[ -L "${destination}/Sicherungsinfo.txt" ]]; then
    if run_backup; then fail 'Symbolischen Link als Versionsübersicht akzeptiert'; fi
    assert_no_export_started
    grep -Fxq 'Fremde Notizen' "${case_root}/notes.txt" || fail 'Link-Ziel verändert'
    pass 'Symbolischer Link als Versionsübersicht abgewiesen'
else
    printf 'SKIP: Symbolischer Link für Versionsübersicht in dieser Testumgebung nicht verfügbar\n'
fi

printf 'Alle Regressionstests erfolgreich.\n'
