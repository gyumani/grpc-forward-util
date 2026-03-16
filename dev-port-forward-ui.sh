#!/bin/bash
# Interactive Port Forwarding Manager with TUI (bash 3.2 compatible)

# 언어 메시지 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lang-messages.sh"

# 버전 정보
VERSION_FILE="$SCRIPT_DIR/VERSION"
if [ -f "$VERSION_FILE" ]; then
  VERSION=$(cat "$VERSION_FILE")
else
  VERSION="unknown"
fi

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 파일
SERVICES_FILE="$HOME/.k8s-port-forward-services.list"
CONFIG_YAML="$HOME/.k8s-port-forward-config.yaml"
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

# YAML 설정 파일로 내보내기
export_to_yaml() {
  local output_file="${1:-$CONFIG_YAML}"

  echo "# K8s Port Forward Manager Configuration" > "$output_file"
  echo "# Version: $VERSION" >> "$output_file"
  echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
  echo "" >> "$output_file"
  echo "services:" >> "$output_file"

  if [ -f "$SERVICES_FILE" ] && [ -s "$SERVICES_FILE" ]; then
    while IFS='|' read -r name namespace local_port remote_port; do
      echo "  - name: $name" >> "$output_file"
      echo "    namespace: $namespace" >> "$output_file"
      echo "    local_port: $local_port" >> "$output_file"
      echo "    remote_port: $remote_port" >> "$output_file"
      echo "" >> "$output_file"
    done < "$SERVICES_FILE"
  fi

  return 0
}

# YAML 설정 파일에서 가져오기 (간단한 YAML 파서)
import_from_yaml() {
  local input_file="${1:-$CONFIG_YAML}"

  if [ ! -f "$input_file" ]; then
    return 1
  fi

  # 임시 파일 생성
  local temp_file=$(mktemp)

  # YAML 파싱 (Bash 3.2 호환)
  local in_services=0
  local name="" namespace="" local_port="" remote_port=""

  while IFS= read -r line; do
    # 주석과 빈 줄 무시
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # services: 섹션 시작
    if [[ "$line" =~ ^services: ]]; then
      in_services=1
      continue
    fi

    if [ $in_services -eq 1 ]; then
      # 새 서비스 항목 시작
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]]; then
        # 이전 서비스 저장
        if [ -n "$name" ]; then
          echo "${name}|${namespace}|${local_port}|${remote_port}" >> "$temp_file"
        fi
        # 새 서비스 초기화
        name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
        namespace=""
        local_port=""
        remote_port=""
      elif [[ "$line" =~ ^[[:space:]]*name: ]]; then
        name=$(echo "$line" | sed 's/^[[:space:]]*name:[[:space:]]*//')
      elif [[ "$line" =~ ^[[:space:]]*namespace: ]]; then
        namespace=$(echo "$line" | sed 's/^[[:space:]]*namespace:[[:space:]]*//')
      elif [[ "$line" =~ ^[[:space:]]*local_port: ]]; then
        local_port=$(echo "$line" | sed 's/^[[:space:]]*local_port:[[:space:]]*//')
      elif [[ "$line" =~ ^[[:space:]]*remote_port: ]]; then
        remote_port=$(echo "$line" | sed 's/^[[:space:]]*remote_port:[[:space:]]*//')
      fi
    fi
  done < "$input_file"

  # 마지막 서비스 저장
  if [ -n "$name" ]; then
    echo "${name}|${namespace}|${local_port}|${remote_port}" >> "$temp_file"
  fi

  # 기존 서비스 파일 백업
  if [ -f "$SERVICES_FILE" ]; then
    cp "$SERVICES_FILE" "${SERVICES_FILE}.backup"
  fi

  # 새 설정으로 교체
  mv "$temp_file" "$SERVICES_FILE"

  return 0
}

# INI 설정 파일로 내보내기
export_to_ini() {
  local output_file="${1:-${CONFIG_YAML%.yaml}.ini}"

  echo "; K8s Port Forward Manager Configuration" > "$output_file"
  echo "; Version: $VERSION" >> "$output_file"
  echo "; Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
  echo "" >> "$output_file"

  if [ -f "$SERVICES_FILE" ] && [ -s "$SERVICES_FILE" ]; then
    while IFS='|' read -r name namespace local_port remote_port; do
      echo "[$name]" >> "$output_file"
      echo "namespace = $namespace" >> "$output_file"
      echo "local_port = $local_port" >> "$output_file"
      echo "remote_port = $remote_port" >> "$output_file"
      echo "" >> "$output_file"
    done < "$SERVICES_FILE"
  fi

  return 0
}

# INI 설정 파일에서 가져오기
import_from_ini() {
  local input_file="${1}"

  if [ ! -f "$input_file" ]; then
    return 1
  fi

  # 임시 파일 생성
  local temp_file=$(mktemp)

  # INI 파싱
  local current_service=""
  local namespace="" local_port="" remote_port=""

  while IFS= read -r line; do
    # 주석과 빈 줄 무시
    [[ "$line" =~ ^[[:space:]]*\; ]] && continue
    [[ -z "${line// }" ]] && continue

    # 섹션 헤더 [service_name]
    if [[ "$line" =~ ^\[(.*)\] ]]; then
      # 이전 서비스 저장
      if [ -n "$current_service" ]; then
        echo "${current_service}|${namespace}|${local_port}|${remote_port}" >> "$temp_file"
      fi
      # 새 서비스 초기화
      current_service="${BASH_REMATCH[1]}"
      namespace=""
      local_port=""
      remote_port=""
    # 키-값 쌍
    elif [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      case "$key" in
        namespace) namespace="$value" ;;
        local_port) local_port="$value" ;;
        remote_port) remote_port="$value" ;;
      esac
    fi
  done < "$input_file"

  # 마지막 서비스 저장
  if [ -n "$current_service" ]; then
    echo "${current_service}|${namespace}|${local_port}|${remote_port}" >> "$temp_file"
  fi

  # 기존 서비스 파일 백업
  if [ -f "$SERVICES_FILE" ]; then
    cp "$SERVICES_FILE" "${SERVICES_FILE}.backup"
  fi

  # 새 설정으로 교체
  mv "$temp_file" "$SERVICES_FILE"

  return 0
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

# 현재 Kubernetes 컨텍스트 가져오기
get_current_context() {
  if command -v kubectl &> /dev/null; then
    local ctx=$(kubectl config current-context 2>/dev/null)
    if [ -n "$ctx" ]; then
      echo "$ctx"
    else
      echo "$(msg context_not_set)"
    fi
  else
    echo "kubectl not found"
  fi
}

# gum UI 모드
gum_ui() {
  while true; do
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    printf "${BLUE}║   %-28s v%-7s  ║${NC}\n" "$(msg header_title)" "$VERSION"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # 현재 Kubernetes 컨텍스트 표시
    local current_ctx=$(get_current_context)
    echo -e "${YELLOW}$(msg current_context)${NC} ${GREEN}$current_ctx${NC}"
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
      "$(msg menu_config)" \
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

    elif [[ "$ACTION" == *"Config"* ]] || [[ "$ACTION" == *"설정"* ]]; then
      # 설정 관리
      while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        printf "${BLUE}║   %-36s  ║${NC}\n" "$(msg menu_config)"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""

        CONFIG_ACTION=$(gum choose \
          "$(msg config_export_yaml)" \
          "$(msg config_export_ini)" \
          "$(msg config_import_yaml)" \
          "$(msg config_import_ini)" \
          "$(msg config_back)")

        if [[ "$CONFIG_ACTION" == *"Export"* ]] || [[ "$CONFIG_ACTION" == *"내보내기"* ]]; then
          echo ""
          echo "$(msg enter_file_path)"

          if [[ "$CONFIG_ACTION" == *"YAML"* ]]; then
            FILE_PATH=$(gum input --placeholder "$CONFIG_YAML" --value "$CONFIG_YAML")
            [ -z "$FILE_PATH" ] && FILE_PATH="$CONFIG_YAML"

            export_to_yaml "$FILE_PATH"
            echo ""
            echo -e "${GREEN}$(msg export_success)${NC}"
            echo "$(msg export_location) $FILE_PATH"
          else
            FILE_PATH=$(gum input --placeholder "$HOME/.k8s-port-forward-config.ini" --value "$HOME/.k8s-port-forward-config.ini")
            [ -z "$FILE_PATH" ] && FILE_PATH="$HOME/.k8s-port-forward-config.ini"

            export_to_ini "$FILE_PATH"
            echo ""
            echo -e "${GREEN}$(msg export_success)${NC}"
            echo "$(msg export_location) $FILE_PATH"
          fi

          echo ""
          echo "$(msg press_enter)"
          read

        elif [[ "$CONFIG_ACTION" == *"Import"* ]] || [[ "$CONFIG_ACTION" == *"가져오기"* ]]; then
          echo ""
          echo "$(msg enter_file_path)"

          if [[ "$CONFIG_ACTION" == *"YAML"* ]]; then
            FILE_PATH=$(gum input --placeholder "$CONFIG_YAML" --value "$CONFIG_YAML")
            [ -z "$FILE_PATH" ] && FILE_PATH="$CONFIG_YAML"
          else
            FILE_PATH=$(gum input --placeholder "$HOME/.k8s-port-forward-config.ini" --value "$HOME/.k8s-port-forward-config.ini")
            [ -z "$FILE_PATH" ] && FILE_PATH="$HOME/.k8s-port-forward-config.ini"
          fi

          if [ ! -f "$FILE_PATH" ]; then
            echo ""
            echo -e "${RED}$(msg import_failed)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          echo ""
          echo -e "${YELLOW}$(msg import_confirm)${NC}"
          echo ""

          if gum confirm "Continue?"; then
            if [[ "$CONFIG_ACTION" == *"YAML"* ]]; then
              import_from_yaml "$FILE_PATH"
            else
              import_from_ini "$FILE_PATH"
            fi

            local imported_count=$(count_services)
            echo ""
            echo -e "${GREEN}$(msg import_success)${NC}"
            echo "$imported_count $(msg services_imported)"

            if [ -f "${SERVICES_FILE}.backup" ]; then
              echo "$(msg backup_created) ${SERVICES_FILE}.backup"
            fi
          else
            echo ""
            echo -e "${YELLOW}$(msg canceled)${NC}"
          fi

          echo ""
          echo "$(msg press_enter)"
          read

        elif [[ "$CONFIG_ACTION" == *"Back"* ]] || [[ "$CONFIG_ACTION" == *"뒤로"* ]]; then
          break
        fi
      done

    elif [[ "$ACTION" == *"Manage"* ]] || [[ "$ACTION" == *"서비스"* ]]; then
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

# 도움말 표시
show_help() {
  echo ""
  echo -e "${BLUE}$(msg help_description)${NC}"
  echo ""
  echo -e "${YELLOW}$(msg help_usage)${NC}"
  echo "  port-machine [command] [options]"
  echo ""
  echo -e "${YELLOW}$(msg help_commands)${NC}"
  echo "  ui                      $(msg help_ui)"
  echo "  start [service...]      $(msg help_start)"
  echo "  stop                    $(msg help_stop)"
  echo "  status                  $(msg help_status)"
  echo "  upgrade                 $(msg help_upgrade)"
  echo "  -h, --help              $(msg help_help)"
  echo ""
  echo -e "${YELLOW}$(msg help_examples)${NC}"
  echo "  port-machine            $(msg help_example1)"
  echo "  port-machine start      $(msg help_example2)"
  echo "  port-machine start svc1 svc2"
  echo "                          $(msg help_example3)"
  echo "  port-machine status     $(msg help_example4)"
  echo "  port-machine stop       $(msg help_example5)"
  echo "  port-machine upgrade    $(msg help_example6)"
  echo ""
  echo -e "${BLUE}Version:${NC} v$VERSION"
  echo ""
}

# 메인
main() {
  case "${1:-ui}" in
    -h|--help|help)
      show_help
      ;;
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
      echo "Usage: port-machine {ui|start [services...]|stop|status|upgrade|-h|--help}"
      exit 1
      ;;
  esac
}

main "$@"
