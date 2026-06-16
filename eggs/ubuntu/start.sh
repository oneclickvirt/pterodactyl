#!/bin/bash
set -u

PROMPT_TEXT="${SHELL_PROMPT:-user@MyVPS:~ }"
STARTUP_CMD="${STARTUP_CMD:-}"

echo "started / 已启动"

run_command() {
    local command_text="$1"

    if [ -z "$command_text" ]; then
        return 0
    fi

    case "$command_text" in
        exit|quit)
            exit 0
            ;;
    esac

    bash -lc "$command_text"
}

if [ -n "$STARTUP_CMD" ]; then
    run_command "$STARTUP_CMD"
fi

while true; do
    printf "%s" "$PROMPT_TEXT"
    if ! IFS= read -r CMD; then
        break
    fi
    run_command "$CMD"
done
