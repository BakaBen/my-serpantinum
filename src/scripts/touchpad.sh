#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

ACTION="${1:-toggle}"

DE="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}"
DE="${DE,,}"

# Hyprland does not report whether a device is enabled, so the last state set here is kept.
HYPR_STATE_FILE="$QS_RUN_DIR/touchpad_disabled"

hypr_devices() {
    hyprctl devices -j 2>/dev/null | jq -r '.mice[]?.name | select(test("touchpad|trackpad"; "i"))'
}

hypr_set() {
    local enabled="$1" dev found=false
    while IFS= read -r dev; do
        [ -n "$dev" ] || continue
        found=true
        hyprctl keyword "device[$dev]:enabled" "$enabled" >/dev/null 2>&1 ||
            hyprctl eval "hl.device({ name = \"$dev\", enabled = $enabled })" >/dev/null 2>&1
    done < <(hypr_devices)
    [ "$found" = true ] || return 1
    if [ "$enabled" = true ]; then rm -f "$HYPR_STATE_FILE"; else touch "$HYPR_STATE_FILE"; fi
}

hypr_status() {
    [ -f "$HYPR_STATE_FILE" ] && echo off || echo on
}

sway_set() {
    local events=enabled
    [ "$1" = true ] || events=disabled
    swaymsg input type:touchpad events "$events" >/dev/null 2>&1
}

sway_status() {
    local ev
    ev="$(swaymsg -t get_inputs -r 2>/dev/null | jq -r '[.[] | select(.type == "touchpad")][0].libinput.send_events // empty')"
    [ "$ev" = "enabled" ] && echo on || echo off
}

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" || "$DE" == *"hyprland"* ]]; then
    BACKEND=hypr
elif [[ -n "${SWAYSOCK:-}" || "$DE" == *"sway"* ]]; then
    BACKEND=sway
else
    # Niri and Mango have no runtime IPC to toggle input devices; set it in their input config instead.
    echo "touchpad: unsupported compositor" >&2
    exit 1
fi

case "$ACTION" in
    status) "${BACKEND}_status"; exit 0 ;;
    on) target=true ;;
    off) target=false ;;
    toggle) [ "$("${BACKEND}_status")" = on ] && target=false || target=true ;;
    *) echo "Usage: serpantinum touchpad [toggle|on|off|status]" >&2; exit 1 ;;
esac

"${BACKEND}_set" "$target" || { echo "touchpad: no touchpad found" >&2; exit 1; }
status="$("${BACKEND}_status")"
quickshell ${MAIN_QML:+-p "$MAIN_QML"} ipc call osd showToggle touchpad "$status" >/dev/null 2>&1 || true
echo "$status"

