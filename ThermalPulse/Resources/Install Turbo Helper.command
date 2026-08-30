#!/bin/bash

set -euo pipefail

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

readonly APP_PATH="/Applications/ThermalPulse.app"
readonly APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/ThermalPulse"
readonly HELPER_SOURCE="${APP_PATH}/Contents/Resources/ThermalPulseHelper"
readonly PLIST_SOURCE="${APP_PATH}/Contents/Resources/io.github.iyuenan3.thermalpulse.helper.manual.plist"
readonly HELPER_DESTINATION="/Library/PrivilegedHelperTools/io.github.iyuenan3.thermalpulse.helper"
readonly PLIST_DESTINATION="/Library/LaunchDaemons/io.github.iyuenan3.thermalpulse.helper.plist"
readonly SUPPORT_DIRECTORY="/Library/Application Support/ThermalPulse"
readonly MANIFEST_DESTINATION="${SUPPORT_DIRECTORY}/installation.plist"
readonly LEASE_PATH="${SUPPORT_DIRECTORY}/turbo-lease.plist"
readonly LABEL="io.github.iyuenan3.thermalpulse.helper"
readonly APP_IDENTIFIER="io.github.iyuenan3.thermalpulse"
readonly HELPER_IDENTIFIER="io.github.iyuenan3.thermalpulse.helper"
readonly SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"

fail() {
    echo "安装失败：$1" >&2
    exit 1
}

signature_field() {
    local path="$1"
    local field="$2"
    /usr/bin/codesign -d --verbose=4 "$path" 2>&1 \
        | /usr/bin/awk -F= -v field="$field" '$1 == field { print $2; exit }'
}

sha256() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{ print $1 }'
}

validate_hex() {
    local value="$1"
    local length="$2"
    [[ ${#value} -eq $length && "$value" =~ ^[0-9a-f]+$ ]]
}

validate_existing_manifest_security() {
    [[ ! -L "$MANIFEST_DESTINATION" ]] || fail "现有安装身份文件是符号链接。"
    local owner
    local mode
    owner="$(/usr/bin/stat -f '%u' "$MANIFEST_DESTINATION")"
    mode="$(/usr/bin/stat -f '%Lp' "$MANIFEST_DESTINATION")"
    [[ "$owner" == "0" ]] || fail "现有安装身份文件不属于 root。"
    (( (8#$mode & 022) == 0 )) || fail "现有安装身份文件可被非 root 用户写入。"
}

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
    echo "ThermalPulse 将安装一个固定身份、接口受限的 root helper。"
    echo "安装只登记服务，不会启动 Turbo，也不会写入 SMC。"
    echo
    /usr/bin/sudo -- "$SCRIPT_PATH" --root
    echo
    echo "安装完成。返回 ThermalPulse 后点击“重新检查状态”。"
    read -r -p "按回车键关闭窗口。" _
    exit 0
fi

[[ "${1:-}" == "--root" ]] || fail "root 模式参数无效。"
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || fail "仅支持 Apple 芯片 Mac。"

os_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ print $1 }')"
[[ "$os_major" =~ ^[0-9]+$ && "$os_major" -ge 26 ]] || fail "需要 macOS 26 或更高版本。"

[[ -d "$APP_PATH" ]] || fail "请先把 ThermalPulse.app 拖入“应用程序”文件夹。"
[[ -x "$APP_EXECUTABLE" ]] || fail "App 主程序缺失。"
[[ -x "$HELPER_SOURCE" ]] || fail "App 内的 helper 缺失。"
[[ -f "$PLIST_SOURCE" ]] || fail "App 内的 LaunchDaemon 配置缺失。"
[[ ! -e "$LEASE_PATH" ]] || fail "检测到 Turbo 租约。请先停止 Turbo，再重新安装。"

temporary_directory="$(/usr/bin/mktemp -d /private/tmp/thermalpulse-helper.XXXXXX)"
readonly temporary_directory
cleanup_temporary_directory() {
    /bin/rm -rf "$temporary_directory"
}
trap cleanup_temporary_directory EXIT

/usr/bin/install -o root -g wheel -m 0755 "$HELPER_SOURCE" "${temporary_directory}/helper"
/usr/bin/install -o root -g wheel -m 0644 "$PLIST_SOURCE" "${temporary_directory}/launchd.plist"

/usr/bin/codesign --verify --deep --strict "$APP_PATH" \
    || fail "App 代码完整性校验失败。请重新下载官方 GitHub Release。"
/usr/bin/codesign --verify --strict "${temporary_directory}/helper" \
    || fail "helper 代码完整性校验失败。"
/usr/bin/plutil -lint "${temporary_directory}/launchd.plist" >/dev/null \
    || fail "LaunchDaemon 配置无效。"

plist_label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "${temporary_directory}/launchd.plist")"
plist_program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "${temporary_directory}/launchd.plist")"
plist_process_type="$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "${temporary_directory}/launchd.plist")"
plist_mach_service="$(/usr/libexec/PlistBuddy -c "Print :MachServices:${LABEL}" "${temporary_directory}/launchd.plist")"
[[ "$plist_label" == "$LABEL" ]] || fail "LaunchDaemon label 不匹配。"
[[ "$plist_program" == "$HELPER_DESTINATION" ]] || fail "LaunchDaemon helper 路径不匹配。"
[[ "$plist_process_type" == "Interactive" ]] || fail "LaunchDaemon process type 不匹配。"
[[ "$plist_mach_service" == "true" ]] || fail "LaunchDaemon Mach service 不匹配。"
if /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' \
    "${temporary_directory}/launchd.plist" >/dev/null 2>&1; then
    fail "LaunchDaemon 包含未授权的额外参数。"
fi

app_identifier="$(signature_field "$APP_PATH" Identifier)"
helper_identifier="$(signature_field "${temporary_directory}/helper" Identifier)"
app_cdhash="$(signature_field "$APP_PATH" CDHash | /usr/bin/tr '[:upper:]' '[:lower:]')"
helper_cdhash="$(signature_field "${temporary_directory}/helper" CDHash | /usr/bin/tr '[:upper:]' '[:lower:]')"
app_sha256="$(sha256 "$APP_EXECUTABLE")"
helper_sha256="$(sha256 "${temporary_directory}/helper")"

[[ "$app_identifier" == "$APP_IDENTIFIER" ]] || fail "App identifier 不匹配。"
[[ "$helper_identifier" == "$HELPER_IDENTIFIER" ]] || fail "helper identifier 不匹配。"
validate_hex "$app_cdhash" 40 || fail "App CDHash 无效。"
validate_hex "$helper_cdhash" 40 || fail "helper CDHash 无效。"
validate_hex "$app_sha256" 64 || fail "App SHA-256 无效。"
validate_hex "$helper_sha256" 64 || fail "helper SHA-256 无效。"

had_previous_installation=0
if [[ -e "$MANIFEST_DESTINATION" ]]; then
    validate_existing_manifest_security
    [[ -f "$HELPER_DESTINATION" && -f "$PLIST_DESTINATION" ]] \
        || fail "现有手动安装不完整，请先人工检查。"
    had_previous_installation=1
elif [[ -e "$HELPER_DESTINATION" || -e "$PLIST_DESTINATION" ]]; then
    fail "检测到没有安装身份文件的旧 helper 文件。为避免误删，请先人工检查。"
elif /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    fail "检测到旧版 ServiceManagement helper。请先用原签名版本注销它，再运行本安装器。"
fi

completed=0
mutation_started=0

rollback() {
    local exit_code="$1"
    set +e
    if [[ "$completed" -eq 0 && "$mutation_started" -eq 1 ]]; then
        /bin/launchctl bootout "system/${LABEL}" >/dev/null 2>&1
        if [[ "$had_previous_installation" -eq 1 ]]; then
            /usr/bin/install -o root -g wheel -m 0755 \
                "${temporary_directory}/previous-helper" "$HELPER_DESTINATION"
            /usr/bin/install -o root -g wheel -m 0644 \
                "${temporary_directory}/previous-launchd.plist" "$PLIST_DESTINATION"
            /usr/bin/install -o root -g wheel -m 0644 \
                "${temporary_directory}/previous-installation.plist" "$MANIFEST_DESTINATION"
            /bin/launchctl bootstrap system "$PLIST_DESTINATION" >/dev/null 2>&1
        else
            /bin/rm -f "$HELPER_DESTINATION" "$PLIST_DESTINATION" "$MANIFEST_DESTINATION"
        fi
    fi
    exit "$exit_code"
}
trap 'rollback $?' ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM

if [[ "$had_previous_installation" -eq 1 ]]; then
    /bin/cp -p "$HELPER_DESTINATION" "${temporary_directory}/previous-helper"
    /bin/cp -p "$PLIST_DESTINATION" "${temporary_directory}/previous-launchd.plist"
    /bin/cp -p "$MANIFEST_DESTINATION" "${temporary_directory}/previous-installation.plist"
fi

/usr/bin/plutil -create xml1 "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert formatVersion -integer 1 "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert appIdentifier -string "$APP_IDENTIFIER" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert helperIdentifier -string "$HELPER_IDENTIFIER" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert appBundlePath -string "$APP_PATH" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert helperExecutablePath -string "$HELPER_DESTINATION" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert appCodeDirectoryHash -string "$app_cdhash" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert helperCodeDirectoryHash -string "$helper_cdhash" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert appExecutableSHA256 -string "$app_sha256" "${temporary_directory}/installation.plist"
/usr/bin/plutil -insert helperExecutableSHA256 -string "$helper_sha256" "${temporary_directory}/installation.plist"
/usr/bin/plutil -lint "${temporary_directory}/installation.plist" >/dev/null

mutation_started=1
if /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/${LABEL}"
fi

/usr/bin/install -d -o root -g wheel -m 0755 "/Library/PrivilegedHelperTools"
/usr/bin/install -d -o root -g wheel -m 0755 "/Library/LaunchDaemons"
/usr/bin/install -d -o root -g wheel -m 0755 "$SUPPORT_DIRECTORY"
/usr/bin/install -o root -g wheel -m 0755 "${temporary_directory}/helper" "$HELPER_DESTINATION"
/usr/bin/install -o root -g wheel -m 0644 "${temporary_directory}/launchd.plist" "$PLIST_DESTINATION"
/usr/bin/install -o root -g wheel -m 0644 "${temporary_directory}/installation.plist" "$MANIFEST_DESTINATION"

/usr/bin/codesign --verify --strict "$HELPER_DESTINATION"
/bin/launchctl bootstrap system "$PLIST_DESTINATION"
/bin/launchctl print "system/${LABEL}" >/dev/null

completed=1
trap - ERR INT TERM
/bin/rm -rf "$temporary_directory"
trap - EXIT

echo "Turbo helper 已安装并由 launchd 登记。"
echo "调用身份已固定到当前 App 和 helper 的代码哈希。"
echo "Turbo 尚未启动，Apple 自动风扇控制保持不变。"
