#!/bin/bash
# Interactive Port Forwarding Manager with TUI (bash 3.2 compatible)

# 언어 메시지 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lang-messages.sh"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 파일
SERVICES_FILE="$HOME/.k8s-port-forward-services.list"
PID_FILE="/tmp/k8s-port-forward.pids"
LOG_DIR="/tmp/k8s-port-forward-logs"

mkdir -p "$LOG_DIR"

# 서비스 파일 초기화
[ ! -f "$SERVICES_FILE" ] && touch "$SERVICES_FILE"

# gum 설치 확인
check_gum() {
  if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}$(msg gum_not_installed)${NC}"
    echo ""
    echo "$(msg install_method)"
    echo "  brew install gum"
    echo ""
    echo -n "$(msg install_now)"
    read -r answer
    if [[ "$answer" == "y" ]]; then
      brew install gum
    else
      echo "$(msg fallback_mode)"
      return 1
    fi
  fi
  return 0
}

# 서비스 추가
add_service() {
  local name=$1
  local namespace=$2
  local local_port=$3
  local remote_port=$4

  # 중복 체크
  if grep -q "^${name}|" "$SERVICES_FILE" 2>/dev/null; then
    return 1
  fi

  echo "${name}|${namespace}|${local_port}|${remote_port}" >> "$SERVICES_FILE"
  return 0
}

# 서비스 삭제
delete_service() {
  local name=$1
  grep -v "^${name}|" "$SERVICES_FILE" > "${SERVICES_FILE}.tmp" 2>/dev/null
  mv "${SERVICES_FILE}.tmp" "$SERVICES_FILE"
}

# 서비스 조회
get_service() {
  local name=$1
  grep "^${name}|" "$SERVICES_FILE" 2>/dev/null
}

# 서비스 수정
update_service() {
  local name=$1
  local namespace=$2
  local local_port=$3
  local remote_port=$4

  delete_service "$name"
  add_service "$name" "$namespace" "$local_port" "$remote_port"
}

# 모든 서비스 목록
list_services() {
  cat "$SERVICES_FILE" 2>/dev/null
}

# 서비스 개수
count_services() {
  if [ -f "$SERVICES_FILE" ]; then
    wc -l < "$SERVICES_FILE" | tr -d ' '
  else
    echo "0"
  fi
}

# 기존 포트 포워딩 정리
cleanup() {
  if [ -f "$PID_FILE" ]; then
    while read pid; do
      kill $pid 2>/dev/null
    done < "$PID_FILE"
    rm "$PID_FILE"
  fi
  pkill -f "kubectl port-forward" 2>/dev/null
}

# 단일 서비스 포트 포워딩 (재연결 기능)
forward_service() {
  local service=$1
  local namespace=$2
  local local_port=$3
  local remote_port=$4

  while true; do
    kubectl port-forward -n $namespace svc/$service $local_port:$remote_port \
      >> "$LOG_DIR/${service}.log" 2>&1
    sleep 3
  done
}

# 실행 중인 포트 포워딩 상태 확인
get_running_services() {
  local running=0
  if [ -f "$PID_FILE" ]; then
    while read pid; do
      if ps -p $pid > /dev/null 2>&1; then
        running=$((running + 1))
      fi
    done < "$PID_FILE"
  fi
  echo "$running"
}

# 선택된 서비스들 시작
start_selected_services() {
  cleanup

  echo -e "${GREEN}$(msg starting)${NC}"
  echo ""

  local IFS=$'\n'
  for line in $@; do
    local name=$(echo "$line" | cut -d'|' -f1)
    local namespace=$(echo "$line" | cut -d'|' -f2)
    local local_port=$(echo "$line" | cut -d'|' -f3)
    local remote_port=$(echo "$line" | cut -d'|' -f4)

    echo "  ▸ $name -> localhost:$local_port"
    forward_service "$name" "$namespace" "$local_port" "$remote_port" &
    echo $! >> "$PID_FILE"
  done

  echo ""
  echo -e "${GREEN}$(msg started)${NC}"
  echo ""
  echo "$(msg running_background)"
  echo "$(msg stop_cmd) $0 stop"
}

# gum UI 모드
gum_ui() {
  while true; do
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    printf "${BLUE}║   %-36s  ║${NC}\n" "$(msg header_title)"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    local running_count=$(get_running_services)
    if [ "$running_count" -gt 0 ]; then
      echo -e "${GREEN}$(msg running_services) $running_count $(msg services_count)${NC}"
    else
      echo -e "${YELLOW}$(msg no_services)${NC}"
    fi
    echo ""

    ACTION=$(gum choose \
      "$(msg menu_start)" \
      "$(msg menu_stop)" \
      "$(msg menu_status)" \
      "$(msg menu_manage)" \
      "$(msg menu_logs)" \
      "$(msg menu_exit)")

    # 메뉴 선택 처리
    if [[ "$ACTION" == *"Start"* ]] || [[ "$ACTION" == *"시작"* ]]; then
      # 서비스 시작
      local service_count=$(count_services)

      if [ "$service_count" -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}$(msg registered_services)${NC}"
        echo ""
        echo "$(msg press_enter)"
        read
        continue
      fi

      echo ""
      echo "$(msg select_services)"
      echo ""

      local service_options=()
      while IFS='|' read -r name namespace local_port remote_port; do
        service_options+=("$name (localhost:$local_port)")
      done < "$SERVICES_FILE"

      local selected=$(gum choose --no-limit "${service_options[@]}")

      if [ -n "$selected" ]; then
        echo "$selected" | while IFS= read -r line; do
          local svc_name=$(echo "$line" | cut -d' ' -f1)
          get_service "$svc_name"
        done > /tmp/k8s-pf-selected.$$

        echo ""
        start_selected_services "$(cat /tmp/k8s-pf-selected.$$)"
        rm -f /tmp/k8s-pf-selected.$$
        echo ""
        echo "$(msg press_enter)"
        read
      fi

    elif [[ "$ACTION" == *"Stop"* ]] || [[ "$ACTION" == *"중지"* ]]; then
      # 모두 중지
      cleanup
      echo ""
      echo -e "${GREEN}$(msg stopped)${NC}"
      echo ""
      echo "$(msg press_enter)"
      read

    elif [[ "$ACTION" == *"Status"* ]] || [[ "$ACTION" == *"상태"* ]]; then
      # 상태 확인
      echo ""
      echo -e "${BLUE}$(msg header_status)${NC}"
      echo ""

      if [ ! -f "$PID_FILE" ]; then
        echo "$(msg no_services_running)"
      else
        printf "%-5s %-30s %-15s\n" "$(msg table_pid)" "$(msg table_service)" "$(msg table_status)"
        echo "-------------------------------------------------------"

        while read pid; do
          if ps -p $pid > /dev/null 2>&1; then
            local cmd=$(ps -p $pid -o args= | grep -o 'svc/[^ ]*' | cut -d'/' -f2)
            echo -e "${GREEN}✓${NC} $pid  $cmd  $(msg running)"
          else
            echo -e "${RED}✗${NC} $pid  $(msg terminated)"
          fi
        done < "$PID_FILE"
      fi

      echo ""
      echo "$(msg press_enter)"
      read

    elif [[ "$ACTION" == *"Manage"* ]] || [[ "$ACTION" == *"관리"* ]]; then
      # 서비스 관리
      while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        printf "${BLUE}║   %-36s  ║${NC}\n" "$(msg header_manage)"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""

        local svc_count=$(count_services)
        echo -e "${YELLOW}$(msg current_services) ${svc_count}${NC}"
        echo ""

        if [ "$svc_count" -gt 0 ]; then
          printf "%-30s %-15s %-10s %-10s\n" "$(msg table_service_name)" "$(msg table_namespace)" "$(msg table_local_port)" "$(msg table_remote_port)"
          echo "-----------------------------------------------------------------------"
          while IFS='|' read -r name namespace local_port remote_port; do
            printf "%-30s %-15s %-10s %-10s\n" "$name" "$namespace" "$local_port" "$remote_port"
          done < "$SERVICES_FILE"
          echo ""
        fi

        SUB_ACTION=$(gum choose \
          "$(msg manage_add)" \
          "$(msg manage_delete)" \
          "$(msg manage_edit)" \
          "$(msg manage_back)")

        if [[ "$SUB_ACTION" == *"Add"* ]] || [[ "$SUB_ACTION" == *"추가"* ]]; then
          # 서비스 추가
          echo ""
          echo -e "${BLUE}$(msg enter_service_info)${NC}"
          echo ""

          echo "$(msg service_name)"
          ADD_SVC=$(gum input --placeholder "$(msg example) my-service-svc")
          INPUT_EXIT=$?

          if [ $INPUT_EXIT -ne 0 ] || [ -z "$ADD_SVC" ]; then
            echo -e "${YELLOW}$(msg canceled)${NC}"
            sleep 1
            continue
          fi

          if grep -q "^${ADD_SVC}|" "$SERVICES_FILE" 2>/dev/null; then
            echo ""
            echo -e "${RED}$(msg already_exists) $ADD_SVC${NC}"
            echo ""
            sleep 2
            continue
          fi

          echo ""
          echo "$(msg namespace)"
          ADD_NS=$(gum input --placeholder "dev" --value "dev")
          [ -z "$ADD_NS" ] && ADD_NS="dev"

          echo ""
          echo "$(msg local_port)"
          ADD_LOCAL=$(gum input --placeholder "$(msg example) 9999")

          if [ -z "$ADD_LOCAL" ]; then
            echo ""
            echo -e "${RED}$(msg local_port_required)${NC}"
            echo ""
            sleep 1
            continue
          fi

          echo ""
          echo "$(msg remote_port)"
          ADD_REMOTE=$(gum input --placeholder "9090" --value "9090")
          [ -z "$ADD_REMOTE" ] && ADD_REMOTE="9090"

          echo ""
          echo -e "${YELLOW}$(msg confirm_input)${NC}"
          echo "  $(msg service_name): '$ADD_SVC'"
          echo "  $(msg namespace): '$ADD_NS'"
          echo "  $(msg local_port): '$ADD_LOCAL'"
          echo "  $(msg remote_port): '$ADD_REMOTE'"
          echo ""

          if gum confirm "$(msg confirm_add)"; then
            add_service "$ADD_SVC" "$ADD_NS" "$ADD_LOCAL" "$ADD_REMOTE"
            echo ""
            echo -e "${GREEN}$(msg service_added)${NC}"
            echo "  └─ $ADD_NS:$ADD_LOCAL -> $ADD_REMOTE"
            echo ""
            gum spin --spinner dot --title "$(msg refreshing)" -- sleep 1
          else
            echo ""
            echo -e "${YELLOW}$(msg canceled)${NC}"
            sleep 0.5
          fi

        elif [[ "$SUB_ACTION" == *"Delete"* ]] || [[ "$SUB_ACTION" == *"삭제"* ]]; then
          # 서비스 삭제
          local svc_count=$(count_services)

          if [ "$svc_count" -eq 0 ]; then
            echo ""
            echo -e "${YELLOW}$(msg no_services_to_delete)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          echo ""
          echo -e "${YELLOW}$(msg select_to_delete)${NC}"
          echo ""

          local delete_options=()
          while IFS='|' read -r name namespace local_port remote_port; do
            delete_options+=("$name ($namespace:$local_port)")
          done < "$SERVICES_FILE"

          local to_delete=$(gum choose --no-limit "${delete_options[@]}")

          if [ -n "$to_delete" ]; then
            echo ""
            echo "$to_delete" | while IFS= read -r line; do
              local svc_name=$(echo "$line" | cut -d' ' -f1)
              delete_service "$svc_name"
              echo -e "${GREEN}✓${NC} '$svc_name' $(msg deleted)"
            done

            echo ""
            echo -e "${GREEN}$(msg service_deleted)${NC}"
            echo ""
            gum spin --spinner dot --title "$(msg refreshing)" -- sleep 1
          fi

        elif [[ "$SUB_ACTION" == *"Edit"* ]] || [[ "$SUB_ACTION" == *"수정"* ]]; then
          # 포트 수정
          local svc_count=$(count_services)

          if [ "$svc_count" -eq 0 ]; then
            echo ""
            echo -e "${YELLOW}$(msg no_services_to_edit)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          echo ""
          echo "$(msg select_to_edit)"
          echo ""

          local edit_options=()
          while IFS='|' read -r name namespace local_port remote_port; do
            edit_options+=("$name ($namespace:$local_port)")
          done < "$SERVICES_FILE"

          local to_edit=$(gum choose "${edit_options[@]}")

          if [ -n "$to_edit" ]; then
            local svc_name=$(echo "$to_edit" | cut -d' ' -f1)
            local svc_info=$(get_service "$svc_name")

            local old_ns=$(echo "$svc_info" | cut -d'|' -f2)
            local old_local=$(echo "$svc_info" | cut -d'|' -f3)
            local old_remote=$(echo "$svc_info" | cut -d'|' -f4)

            echo ""
            echo -e "${BLUE}$(msg current_settings)${NC}"
            echo "  $(msg service_name): $svc_name"
            echo "  $(msg namespace): $old_ns"
            echo "  $(msg local_port): $old_local"
            echo "  $(msg remote_port): $old_remote"
            echo ""
            echo -e "${YELLOW}$(msg enter_new_values)${NC}"
            echo ""

            local new_ns=$(gum input --placeholder "$(msg namespace)" --value "$old_ns")
            local new_local=$(gum input --placeholder "$(msg local_port)" --value "$old_local")
            local new_remote=$(gum input --placeholder "$(msg remote_port)" --value "$old_remote")

            [ -z "$new_ns" ] && new_ns="$old_ns"
            [ -z "$new_local" ] && new_local="$old_local"
            [ -z "$new_remote" ] && new_remote="$old_remote"

            update_service "$svc_name" "$new_ns" "$new_local" "$new_remote"

            echo ""
            echo -e "${GREEN}$(msg service_updated)${NC}"
            echo "  └─ $new_ns:$new_local -> $new_remote"
            echo ""
            gum spin --spinner dot --title "$(msg refreshing)" -- sleep 1
          fi

        elif [[ "$SUB_ACTION" == *"Back"* ]] || [[ "$SUB_ACTION" == *"뒤로"* ]]; then
          break
        fi
      done

    elif [[ "$ACTION" == *"Logs"* ]] || [[ "$ACTION" == *"로그"* ]]; then
      # 로그 보기
      echo ""
      local log_files=($(ls -1 "$LOG_DIR"/*.log 2>/dev/null))

      if [ ${#log_files[@]} -eq 0 ]; then
        echo "$(msg no_logs)"
        echo ""
        echo "$(msg press_enter)"
        read
      else
        local log_options=()
        for log in "${log_files[@]}"; do
          log_options+=("$(basename $log)")
        done

        local selected_log=$(gum choose "${log_options[@]}")

        if [ -n "$selected_log" ]; then
          clear
          echo -e "${BLUE}=== $selected_log ===${NC}"
          echo ""
          tail -n 50 "$LOG_DIR/$selected_log"
          echo ""
          echo "$(msg press_enter)"
          read
        fi
      fi

    elif [[ "$ACTION" == *"Exit"* ]] || [[ "$ACTION" == *"종료"* ]]; then
      # 종료
      clear
      echo -e "${GREEN}$(msg exiting)${NC}"
      exit 0
    fi
  done
}

# 기본 CLI 모드 (gum 없을 때)
cli_mode() {
  clear
  echo "==================================="
  printf " %-30s\n" "$(msg header_title)"
  echo "==================================="
  echo ""
  echo "1. $(msg usage_start)"
  echo "2. $(msg menu_manage)"
  echo "3. $(msg menu_stop)"
  echo "4. $(msg menu_status)"
  echo "5. $(msg menu_exit)"
  echo ""
  echo -n "$(msg choice) "
  read -r choice

  case $choice in
    1)
      start_selected_services "$(list_services)"
      ;;
    2)
      echo ""
      printf "%-30s %-15s %-10s %-10s\n" "$(msg table_service_name)" "$(msg table_namespace)" "$(msg table_local_port)" "$(msg table_remote_port)"
      echo "-----------------------------------------------------------------------"
      while IFS='|' read -r name namespace local_port remote_port; do
        printf "%-30s %-15s %-10s %-10s\n" "$name" "$namespace" "$local_port" "$remote_port"
      done < "$SERVICES_FILE"
      ;;
    3)
      cleanup
      echo "$(msg stopped)"
      ;;
    4)
      echo ""
      echo "$(msg header_status)"
      if [ ! -f "$PID_FILE" ]; then
        echo "  $(msg none)"
      else
        while read pid; do
          if ps -p $pid > /dev/null 2>&1; then
            echo "  ✓ PID $pid $(msg running)"
          fi
        done < "$PID_FILE"
      fi
      ;;
    5)
      exit 0
      ;;
  esac
}

# 메인
main() {
  case "${1:-ui}" in
    ui)
      if check_gum; then
        gum_ui
      else
        cli_mode
      fi
      ;;
    start)
      shift
      if [ $# -eq 0 ]; then
        start_selected_services "$(list_services)"
      else
        for svc in "$@"; do
          get_service "$svc"
        done > /tmp/k8s-pf-start.$$
        start_selected_services "$(cat /tmp/k8s-pf-start.$$)"
        rm -f /tmp/k8s-pf-start.$$
      fi
      ;;
    stop)
      cleanup
      echo "$(msg stopped)"
      ;;
    status)
      if [ ! -f "$PID_FILE" ]; then
        echo "$(msg no_services_running)"
      else
        while read pid; do
          if ps -p $pid > /dev/null 2>&1; then
            local cmd=$(ps -p $pid -o args=)
            echo "✓ PID $pid: $cmd"
          fi
        done < "$PID_FILE"
      fi
      ;;
    upgrade)
      # upgrade.sh 실행
      if [ -f "$SCRIPT_DIR/upgrade.sh" ]; then
        exec "$SCRIPT_DIR/upgrade.sh"
      else
        echo -e "${RED}✗ upgrade.sh 파일을 찾을 수 없습니다.${NC}"
        echo ""
        echo "Git을 통해 설치했는지 확인해주세요:"
        echo "  git clone https://github.com/gyumani/grpc-forward-util.git"
        exit 1
      fi
      ;;
    *)
      echo "Usage: $0 {ui|start [services...]|stop|status|upgrade}"
      exit 1
      ;;
  esac
}

main "$@"
