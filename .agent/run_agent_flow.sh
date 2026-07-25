#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AGENT_DIR="$PROJECT_ROOT/.agent"
cd "$PROJECT_ROOT"

LOCK_FILE="$AGENT_DIR/run.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "❌ [Error] 另一个 AGY 执行进程正在运行中，跳过本次触发。"
    exit 1
fi

TASKS_FILE="$AGENT_DIR/tasks.json"
SPEC_FILE="$AGENT_DIR/spec.md"
REVIEW_FILE="$AGENT_DIR/review.md"
RESULT_FILE="$AGENT_DIR/result.json"
TEST_REPORT_FILE="$AGENT_DIR/test_report.md"

update_json_stage() {
    local new_stage="$1"
    local inc_attempt="${2:-false}"
    local tmp_file="$AGENT_DIR/tasks.tmp.json"

    if [ "$inc_attempt" = "true" ]; then
        jq --arg stage "$new_stage" '.current_stage = $stage | .attempt += 1' "$TASKS_FILE" > "$tmp_file"
    else
        jq --arg stage "$new_stage" '.current_stage = $stage' "$TASKS_FILE" > "$tmp_file"
    fi
    mv "$tmp_file" "$TASKS_FILE"
}

CURRENT_STAGE=$(jq -r '.current_stage' "$TASKS_FILE")
ATTEMPT=$(jq -r '.attempt' "$TASKS_FILE")
MAX_ATTEMPTS=$(jq -r '.max_attempts' "$TASKS_FILE")

if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    echo "❌ [Error] 已达到最大重试次数 ($ATTEMPT / $MAX_ATTEMPTS)，进入停机防护状态。"
    update_json_stage "MAX_RETRY_EXCEEDED"
    exit 1
fi

if [ "$CURRENT_STAGE" = "SPEC_DESIGN" ] || [ "$CURRENT_STAGE" = "REJECTED" ]; then
    update_json_stage "CODING" true
elif [ "$CURRENT_STAGE" != "CODING" ]; then
    echo "⚠️ 当前阶段为 $CURRENT_STAGE，无需执行 AGY。"
    exit 0
fi

AGY_PROMPT="[IMPORTANT - Non-Interactive Session: Do not output text waiting for user input.]
请严格遵循以下规则：
1. 仔细阅读需求设计规范: .agent/spec.md
"

if [ -f "$REVIEW_FILE" ] && [ "$CURRENT_STAGE" = "REJECTED" ]; then
    AGY_PROMPT="$AGY_PROMPT
2. ⚠️ 上轮 Code Review 未通过，请阅读意见反馈: .agent/review.md，并针对性修复代码。
"
fi

AGY_PROMPT="$AGY_PROMPT
3. 修改代码后，运行测试命令。
4. 将测试结果和详细堆栈写入: .agent/test_report.md
5. 在 .agent/result.json 写入运行总结: {\"status\": \"SUCCESS\"|\"FAILED\", \"summary\": \"...\"}
"

rm -f "$RESULT_FILE" "$TEST_REPORT_FILE"

set +e
agy --print "$AGY_PROMPT" \
    --mode accept-edits \
    --dangerously-skip-permissions \
    --print-timeout 30m \
    --add-dir "$PROJECT_ROOT"
AGY_EXIT_CODE=$?
set -e

if [ $AGY_EXIT_CODE -ne 0 ] || [ ! -f "$TEST_REPORT_FILE" ]; then
    update_json_stage "FAILED"
    exit 1
fi

AGY_STATUS=$(jq -r '.status // "FAILED"' "$RESULT_FILE" 2>/dev/null || echo "FAILED")

if [ "$AGY_STATUS" = "SUCCESS" ]; then
    update_json_stage "REVIEW"
else
    update_json_stage "FAILED"
    exit 1
fi
