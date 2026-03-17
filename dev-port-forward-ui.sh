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
PROFILES_DIR="$HOME/.port-machine-profiles"
CURRENT_PROFILE_FILE="$HOME/.port-machine-current-profile"
SERVICES_FILE="$HOME/.k8s-port-forward-services.list"
CONFIG_YAML="$HOME/.k8s-port-forward-config.yaml"
PID_FILE="/tmp/k8s-port-forward.pids"
LOG_DIR="/tmp/k8s-port-forward-logs"

mkdir -p "$LOG_DIR"
mkdir -p "$PROFILES_DIR"

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

# ========================================
# 프로필 관리 함수
# ========================================

# 현재 프로필 이름 가져오기
get_current_profile() {
  if [ -f "$CURRENT_PROFILE_FILE" ]; then
    cat "$CURRENT_PROFILE_FILE"
  else
    echo "default"
  fi
}

# 프로필 생성
create_profile() {
  local profile_name=$1
  local description=$2

  if [ -z "$profile_name" ]; then
    return 1
  fi

  # 프로필 이름에서 특수문자 제거
  profile_name=$(echo "$profile_name" | sed 's/[^a-zA-Z0-9_-]//g')

  local profile_file="$PROFILES_DIR/${profile_name}.yaml"

  # 이미 존재하는지 확인
  if [ -f "$profile_file" ]; then
    return 2
  fi

  # 현재 서비스 목록을 프로필로 저장
  echo "# Profile: $profile_name" > "$profile_file"
  echo "# Description: ${description:-No description}" >> "$profile_file"
  echo "# Created: $(date '+%Y-%m-%d %H:%M:%S')" >> "$profile_file"
  echo "" >> "$profile_file"
  echo "services:" >> "$profile_file"

  if [ -f "$SERVICES_FILE" ] && [ -s "$SERVICES_FILE" ]; then
    while IFS='|' read -r name namespace local_port remote_port; do
      echo "  - name: $name" >> "$profile_file"
      echo "    namespace: $namespace" >> "$profile_file"
      echo "    local_port: $local_port" >> "$profile_file"
      echo "    remote_port: $remote_port" >> "$profile_file"
      echo "" >> "$profile_file"
    done < "$SERVICES_FILE"
  fi

  return 0
}

# 프로필 목록
list_profiles() {
  local profiles=()

  if [ -d "$PROFILES_DIR" ]; then
    for profile in "$PROFILES_DIR"/*.yaml; do
      if [ -f "$profile" ]; then
        local profile_name=$(basename "$profile" .yaml)
        profiles+=("$profile_name")
      fi
    done
  fi

  # 배열 출력 (Bash 3.2 호환)
  for profile in "${profiles[@]}"; do
    echo "$profile"
  done
}

# 프로필 개수
count_profiles() {
  local count=0

  if [ -d "$PROFILES_DIR" ]; then
    for profile in "$PROFILES_DIR"/*.yaml; do
      if [ -f "$profile" ]; then
        count=$((count + 1))
      fi
    done
  fi

  echo "$count"
}

# 프로필 로드
load_profile() {
  local profile_name=$1

  if [ -z "$profile_name" ]; then
    return 1
  fi

  local profile_file="$PROFILES_DIR/${profile_name}.yaml"

  if [ ! -f "$profile_file" ]; then
    return 2
  fi

  # 현재 서비스 목록 백업
  if [ -f "$SERVICES_FILE" ]; then
    cp "$SERVICES_FILE" "${SERVICES_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  fi

  # 프로필에서 서비스 로드
  import_from_yaml "$profile_file"

  # 현재 프로필 설정
  echo "$profile_name" > "$CURRENT_PROFILE_FILE"

  return 0
}

# 프로필 삭제
delete_profile() {
  local profile_name=$1

  if [ -z "$profile_name" ]; then
    return 1
  fi

  # default 프로필은 삭제 불가
  if [ "$profile_name" = "default" ]; then
    return 2
  fi

  local profile_file="$PROFILES_DIR/${profile_name}.yaml"

  if [ ! -f "$profile_file" ]; then
    return 3
  fi

  rm "$profile_file"

  # 현재 프로필이 삭제되는 경우 default로 변경
  local current_profile=$(get_current_profile)
  if [ "$current_profile" = "$profile_name" ]; then
    echo "default" > "$CURRENT_PROFILE_FILE"
  fi

  return 0
}

# 프로필 정보 출력
show_profile_info() {
  local profile_name=$1

  if [ -z "$profile_name" ]; then
    return 1
  fi

  local profile_file="$PROFILES_DIR/${profile_name}.yaml"

  if [ ! -f "$profile_file" ]; then
    return 2
  fi

  # 상단 3줄 (메타데이터) 출력
  head -n 3 "$profile_file" | sed 's/^# //'

  # 서비스 개수 계산
  local service_count=$(grep -c "^[[:space:]]*- name:" "$profile_file" 2>/dev/null || echo "0")
  echo "Services: $service_count"

  return 0
}

# 경로에서 프로필 이름 생성
generate_profile_name_from_path() {
  local path=$1

  # 경로를 정규화
  path=$(cd "$path" 2>/dev/null && pwd || echo "$path")

  # basename 추출
  local base_name=$(basename "$path")

  # 특수문자 제거 및 정규화
  local profile_name=$(echo "$base_name" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/^-*//' | sed 's/-*$//')

  # 비어있으면 "discovered" 사용
  if [ -z "$profile_name" ]; then
    profile_name="discovered"
  fi

  # 중복 확인 및 번호 추가
  local original_name="$profile_name"
  local counter=1
  while [ -f "$PROFILES_DIR/${profile_name}.yaml" ]; do
    profile_name="${original_name}-${counter}"
    counter=$((counter + 1))
  done

  echo "$profile_name"
}

# ========================================
# Phase 2: 프로젝트 자동 감지 함수
# ========================================

# 프로젝트 루트 디렉토리 찾기
find_project_root() {
  local dir="${1:-$(pwd)}"

  # 최대 10단계 상위까지 탐색
  local max_depth=10
  local current_depth=0

  while [ "$current_depth" -lt "$max_depth" ]; do
    # 프로젝트 루트를 나타내는 파일/디렉토리 체크
    if [ -d "$dir/.git" ] || \
       [ -f "$dir/package.json" ] || \
       [ -f "$dir/build.gradle" ] || \
       [ -f "$dir/build.gradle.kts" ] || \
       [ -f "$dir/pom.xml" ] || \
       [ -f "$dir/Cargo.toml" ] || \
       [ -f "$dir/go.mod" ] || \
       [ -f "$dir/docker-compose.yml" ] || \
       [ -f "$dir/docker-compose.yaml" ]; then
      echo "$dir"
      return 0
    fi

    # 루트 디렉토리에 도달했는지 확인
    if [ "$dir" = "/" ]; then
      return 1
    fi

    # 상위 디렉토리로 이동
    dir=$(dirname "$dir")
    current_depth=$((current_depth + 1))
  done

  return 1
}

# application.yaml/yml에서 서비스 정보 추출
parse_application_yaml() {
  local file=$1

  if [ ! -f "$file" ]; then
    return 1
  fi

  # spring.application.name 추출
  local app_name=$(grep -E "^\s*application:" -A 5 "$file" | grep -E "^\s*name:\s*" | head -1 | sed -E 's/^[[:space:]]*name:[[:space:]]*([^[:space:]]+).*/\1/')

  # spring.application.name이 없으면 파일명에서 추출 시도
  if [ -z "$app_name" ]; then
    # 파일 경로에서 서비스 이름 추출 (예: /path/to/user-service/src/.../application.yaml)
    local dir_path=$(dirname "$file")
    # src 또는 resources 상위 디렉토리 찾기
    while [[ "$dir_path" != "/" ]]; do
      local dir_name=$(basename "$dir_path")
      if [[ "$dir_name" != "src" ]] && [[ "$dir_name" != "main" ]] && [[ "$dir_name" != "resources" ]] && [[ "$dir_name" != "config" ]]; then
        app_name="$dir_name"
        break
      fi
      dir_path=$(dirname "$dir_path")
    done
  fi

  # 서비스 이름이 없으면 스킵
  if [ -z "$app_name" ]; then
    return 1
  fi

  # grpc.server.port 추출
  local grpc_port=$(grep -E "grpc:" -A 10 "$file" | grep -E "server:" -A 5 | grep -E "^\s*port:\s*[0-9]+" | head -1 | sed -E 's/^[[:space:]]*port:[[:space:]]*([0-9]+).*/\1/')

  # server.port 추출 (Spring Boot HTTP)
  local server_port=$(grep -E "^server:" -A 10 "$file" | grep -E "^\s*port:\s*[0-9]+" | head -1 | sed -E 's/^[[:space:]]*port:[[:space:]]*([0-9]+).*/\1/')

  # 포트 우선순위: gRPC > HTTP server
  if [ -n "$grpc_port" ]; then
    echo "${app_name}-svc|default|${grpc_port}|${grpc_port}"
  elif [ -n "$server_port" ]; then
    echo "${app_name}-svc|default|${server_port}|${server_port}"
  fi
}

# application.properties에서 서비스 정보 추출
parse_application_properties() {
  local file=$1

  if [ ! -f "$file" ]; then
    return 1
  fi

  # spring.application.name 추출
  local app_name=$(grep -E "^spring\.application\.name\s*=" "$file" | head -1 | sed -E 's/^[^=]*=[[:space:]]*([^[:space:]]+).*/\1/')

  # spring.application.name이 없으면 파일명에서 추출 시도
  if [ -z "$app_name" ]; then
    local dir_path=$(dirname "$file")
    while [[ "$dir_path" != "/" ]]; do
      local dir_name=$(basename "$dir_path")
      if [[ "$dir_name" != "src" ]] && [[ "$dir_name" != "main" ]] && [[ "$dir_name" != "resources" ]] && [[ "$dir_name" != "config" ]]; then
        app_name="$dir_name"
        break
      fi
      dir_path=$(dirname "$dir_path")
    done
  fi

  # 서비스 이름이 없으면 스킵
  if [ -z "$app_name" ]; then
    return 1
  fi

  # grpc.server.port 추출
  local grpc_port=$(grep -E "^grpc\.server\.port\s*=" "$file" | head -1 | sed -E 's/^[^=]*=[[:space:]]*([0-9]+).*/\1/')

  # server.port 추출 (Spring Boot HTTP)
  local server_port=$(grep -E "^server\.port\s*=" "$file" | head -1 | sed -E 's/^[^=]*=[[:space:]]*([0-9]+).*/\1/')

  # 포트 우선순위: gRPC > HTTP server
  if [ -n "$grpc_port" ]; then
    echo "${app_name}-svc|default|${grpc_port}|${grpc_port}"
  elif [ -n "$server_port" ]; then
    echo "${app_name}-svc|default|${server_port}|${server_port}"
  fi
}

# docker-compose.yaml에서 서비스 정보 추출
parse_docker_compose() {
  local file=$1
  local services=()

  if [ ! -f "$file" ]; then
    return 1
  fi

  # 간단한 docker-compose 파서 (Bash 3.2 호환)
  local in_services=0
  local current_service=""
  local current_ports=""

  while IFS= read -r line; do
    # services: 섹션 시작
    if [[ "$line" =~ ^services: ]]; then
      in_services=1
      continue
    fi

    if [ $in_services -eq 1 ]; then
      # 서비스 이름 (들여쓰기 2칸)
      if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+): ]]; then
        # 이전 서비스 저장
        if [ -n "$current_service" ] && [ -n "$current_ports" ]; then
          # 포트 형식: "8080:8080" 또는 "8080"
          local port=$(echo "$current_ports" | sed -E 's/.*"([0-9]+):([0-9]+)".*/\1/')
          if [ -n "$port" ]; then
            echo "${current_service}-svc|default|${port}|${port}"
          fi
        fi

        current_service="${BASH_REMATCH[1]}"
        current_ports=""
      # ports 섹션
      elif [[ "$line" =~ ports: ]]; then
        :  # ports: 라인은 무시
      # 포트 정의
      elif [[ "$line" =~ ^[[:space:]]{4,6}-[[:space:]]*\"?([0-9]+):([0-9]+)\"? ]]; then
        current_ports="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
      elif [[ "$line" =~ ^[[:space:]]{4,6}-[[:space:]]*([0-9]+) ]]; then
        local port="${BASH_REMATCH[1]}"
        current_ports="${port}:${port}"
      fi
    fi
  done < "$file"

  # 마지막 서비스 저장
  if [ -n "$current_service" ] && [ -n "$current_ports" ]; then
    local port=$(echo "$current_ports" | sed -E 's/([0-9]+):.*/\1/')
    if [ -n "$port" ]; then
      echo "${current_service}-svc|default|${port}|${port}"
    fi
  fi
}

# 프로젝트에서 서비스 자동 감지 (전체 경로 스캔)
discover_services_from_project() {
  local search_path="${1:-$HOME}"
  local discovered_services=()

  # application.yaml/yml 찾기 (전체 경로에서)
  echo "Scanning $search_path for application.yaml/yml files..." >&2
  local app_yamls=$(find "$search_path" -type f \( -name "application.yaml" -o -name "application.yml" \) 2>/dev/null)

  local yaml_count=0
  for yaml in $app_yamls; do
    yaml_count=$((yaml_count + 1))
    local service=$(parse_application_yaml "$yaml")
    if [ -n "$service" ]; then
      discovered_services+=("$service")
    fi
  done
  echo "Found $yaml_count YAML files" >&2

  # application.properties 찾기
  echo "Scanning for application.properties files..." >&2
  local app_props=$(find "$search_path" -type f -name "application.properties" 2>/dev/null)

  local props_count=0
  for props in $app_props; do
    props_count=$((props_count + 1))
    local service=$(parse_application_properties "$props")
    if [ -n "$service" ]; then
      discovered_services+=("$service")
    fi
  done
  echo "Found $props_count properties files" >&2

  # docker-compose.yaml/yml 찾기
  echo "Scanning for docker-compose files..." >&2
  local compose_files=$(find "$search_path" -type f \( -name "docker-compose.yaml" -o -name "docker-compose.yml" \) 2>/dev/null)

  local compose_count=0
  for compose in $compose_files; do
    compose_count=$((compose_count + 1))
    local compose_services=$(parse_docker_compose "$compose")
    if [ -n "$compose_services" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] && discovered_services+=("$line")
      done <<< "$compose_services"
    fi
  done
  echo "Found $compose_count docker-compose files" >&2

  # 배열 출력 (Bash 3.2 호환)
  for service in "${discovered_services[@]}"; do
    echo "$service"
  done

  if [ ${#discovered_services[@]} -eq 0 ]; then
    return 1
  fi

  return 0
}

# 자동 감지된 서비스 개수
count_discovered_services() {
  local services=$(discover_services_from_project "${1:-$(pwd)}")
  if [ -z "$services" ]; then
    echo "0"
  else
    echo "$services" | wc -l | tr -d ' '
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

    # 현재 프로필 표시
    local current_profile=$(get_current_profile)
    echo -e "${YELLOW}$(msg current_profile)${NC} ${GREEN}$current_profile${NC}"
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
      "$(msg menu_profile)" \
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
          "$(msg config_auto_discover)" \
          "$(msg config_export_yaml)" \
          "$(msg config_export_ini)" \
          "$(msg config_import_yaml)" \
          "$(msg config_import_ini)" \
          "$(msg config_back)")

        if [[ "$CONFIG_ACTION" == *"Auto-discover"* ]] || [[ "$CONFIG_ACTION" == *"자동 감지"* ]]; then
          # 프로젝트 자동 감지
          echo ""
          echo "Enter path to scan (default: $HOME):"
          SCAN_PATH=$(gum input --placeholder "$HOME" --value "$HOME")
          [ -z "$SCAN_PATH" ] && SCAN_PATH="$HOME"

          echo ""
          echo -e "${BLUE}$(msg discovering_services)${NC}"
          echo -e "${YELLOW}Scanning path: $SCAN_PATH${NC}"
          echo ""
          echo "$(msg scanning_files)"
          echo ""

          # 서비스 자동 감지 (진행 상황은 stderr로 표시, 결과만 저장)
          local discovered=$(discover_services_from_project "$SCAN_PATH")

          # 빈 줄 제거하여 실제 서비스 데이터만 추출
          discovered=$(echo "$discovered" | grep -v "^Scanning" | grep -v "^Found" | grep -v "^$")

          if [ -z "$discovered" ]; then
            echo -e "${YELLOW}$(msg no_services_discovered)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          # 발견된 서비스 개수
          local discovered_count=$(echo "$discovered" | wc -l | tr -d ' ')
          echo -e "${GREEN}$discovered_count $(msg services_discovered_count)${NC}"
          echo ""

          # 서비스 목록 표시
          echo -e "${BLUE}$(msg discovered_services)${NC}"
          echo "-----------------------------------------------------------------------"
          printf "%-30s %-15s %-10s %-10s\n" "$(msg table_service_name)" "$(msg table_namespace)" "$(msg table_local_port)" "$(msg table_remote_port)"
          echo "-----------------------------------------------------------------------"

          while IFS='|' read -r name namespace local_port remote_port; do
            printf "%-30s %-15s %-10s %-10s\n" "$name" "$namespace" "$local_port" "$remote_port"
          done <<< "$discovered"

          echo ""
          echo "$(msg select_services_to_import)"
          echo ""

          # 멀티 선택 옵션 생성
          local import_options=()
          while IFS='|' read -r name namespace local_port remote_port; do
            import_options+=("$name ($namespace:$local_port)")
          done <<< "$discovered"

          # 서비스 선택
          local selected=$(gum choose --no-limit "${import_options[@]}")

          if [ -n "$selected" ]; then
            echo ""
            local import_count=0

            # 선택된 서비스 개수 계산
            local selected_count=$(echo "$selected" | wc -l | tr -d ' ')
            echo -e "${BLUE}$(msg services_discovered_count): $selected_count${NC}"
            echo ""

            # 선택된 서비스 import (각 서비스별로 네임스페이스 물어보기)
            while IFS= read -r line; do
              local svc_name=$(echo "$line" | cut -d' ' -f1)
              local svc_info=$(echo "$discovered" | grep "^${svc_name}|")

              if [ -n "$svc_info" ]; then
                local name=$(echo "$svc_info" | cut -d'|' -f1)
                local default_namespace=$(echo "$svc_info" | cut -d'|' -f2)
                local local_port=$(echo "$svc_info" | cut -d'|' -f3)
                local remote_port=$(echo "$svc_info" | cut -d'|' -f4)

                # 서비스별로 네임스페이스 입력 받기
                echo -e "${YELLOW}[$name]${NC}"
                echo "  $(msg namespace) (default: $default_namespace):"
                local input_namespace=$(gum input --placeholder "$default_namespace" --value "$default_namespace")
                [ -z "$input_namespace" ] && input_namespace="$default_namespace"

                # 중복 체크 후 추가
                if add_service "$name" "$input_namespace" "$local_port" "$remote_port"; then
                  echo -e "${GREEN}✓${NC} $name → $input_namespace:$local_port"
                  import_count=$((import_count + 1))
                else
                  echo -e "${YELLOW}⊙${NC} $name ($(msg already_exists))"
                fi
                echo ""
              fi
            done <<< "$selected"

            echo ""
            echo -e "${GREEN}$(msg auto_discover_success)${NC}"
            echo "$import_count $(msg services_imported)"
            local final_count=$(count_services)
            echo "$(msg current_services) ${final_count}"

            # 경로 기반 프로필 생성 (서비스가 하나라도 import된 경우)
            if [ "$import_count" -gt 0 ]; then
              echo ""
              local profile_name=$(generate_profile_name_from_path "$SCAN_PATH")
              echo -e "${BLUE}Creating profile from scanned path...${NC}"

              create_profile "$profile_name" "Auto-discovered from $SCAN_PATH"
              local create_result=$?

              if [ $create_result -eq 0 ]; then
                echo -e "${GREEN}✓ Profile created: $profile_name${NC}"
                echo "  Path: $SCAN_PATH"
                echo "  Services: $import_count"
                echo ""

                # 프로필 전환 여부 물어보기
                if gum confirm "Switch to profile '$profile_name'?"; then
                  echo "$profile_name" > "$CURRENT_PROFILE_FILE"
                  echo -e "${GREEN}✓ Switched to profile: $profile_name${NC}"
                fi
              elif [ $create_result -eq 2 ]; then
                echo -e "${YELLOW}⊙ Profile '$profile_name' already exists${NC}"
              fi
            fi
          else
            echo ""
            echo -e "${YELLOW}$(msg canceled)${NC}"
          fi

          echo ""
          echo "$(msg press_enter)"
          read

        elif [[ "$CONFIG_ACTION" == *"Export"* ]] || [[ "$CONFIG_ACTION" == *"내보내기"* ]]; then
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

    elif [[ "$ACTION" == *"Profile"* ]] || [[ "$ACTION" == *"프로필"* ]]; then
      # 프로필 관리
      while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        printf "${BLUE}║   %-36s  ║${NC}\n" "$(msg menu_profile)"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""

        local current_prof=$(get_current_profile)
        local profile_count=$(count_profiles)
        echo -e "${YELLOW}$(msg current_profile)${NC} ${GREEN}$current_prof${NC}"
        echo -e "${YELLOW}$profile_count $(msg profile_count)${NC}"
        echo ""

        PROFILE_ACTION=$(gum choose \
          "$(msg profile_create)" \
          "$(msg profile_switch)" \
          "$(msg profile_list)" \
          "$(msg profile_delete)" \
          "$(msg profile_back)")

        if [[ "$PROFILE_ACTION" == *"Create"* ]] || [[ "$PROFILE_ACTION" == *"생성"* ]]; then
          # 프로필 생성
          echo ""
          echo "$(msg enter_profile_name)"
          PROFILE_NAME=$(gum input --placeholder "my-profile")

          if [ -z "$PROFILE_NAME" ]; then
            echo ""
            echo -e "${YELLOW}$(msg canceled)${NC}"
            sleep 1
            continue
          fi

          echo ""
          echo "$(msg enter_profile_description)"
          PROFILE_DESC=$(gum input --placeholder "Description...")

          create_profile "$PROFILE_NAME" "$PROFILE_DESC"
          local create_result=$?

          if [ $create_result -eq 0 ]; then
            echo ""
            echo -e "${GREEN}$(msg profile_created)${NC}"
            echo "  $(msg profile_name_label) $PROFILE_NAME"
            local svc_count=$(count_services)
            echo "  $(msg profile_service_count) $svc_count"
          elif [ $create_result -eq 2 ]; then
            echo ""
            echo -e "${RED}$(msg profile_already_exists)${NC}"
          else
            echo ""
            echo -e "${RED}$(msg profile_create_failed)${NC}"
          fi

          echo ""
          echo "$(msg press_enter)"
          read

        elif [[ "$PROFILE_ACTION" == *"Switch"* ]] || [[ "$PROFILE_ACTION" == *"전환"* ]]; then
          # 프로필 전환
          local profiles=($(list_profiles))

          if [ ${#profiles[@]} -eq 0 ]; then
            echo ""
            echo -e "${YELLOW}$(msg no_profiles)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          echo ""
          echo "$(msg select_profile)"
          echo ""

          local selected_profile=$(gum choose "${profiles[@]}")

          if [ -n "$selected_profile" ]; then
            load_profile "$selected_profile"
            local load_result=$?

            if [ $load_result -eq 0 ]; then
              echo ""
              echo -e "${GREEN}$(msg profile_switched) $selected_profile${NC}"
              local svc_count=$(count_services)
              echo "  $svc_count $(msg services_imported)"
            elif [ $load_result -eq 2 ]; then
              echo ""
              echo -e "${RED}$(msg profile_not_found)${NC}"
            else
              echo ""
              echo -e "${RED}$(msg profile_switch_failed)${NC}"
            fi

            echo ""
            echo "$(msg press_enter)"
            read
          fi

        elif [[ "$PROFILE_ACTION" == *"List"* ]] || [[ "$PROFILE_ACTION" == *"목록"* ]]; then
          # 프로필 목록
          local profiles=($(list_profiles))

          if [ ${#profiles[@]} -eq 0 ]; then
            echo ""
            echo -e "${YELLOW}$(msg no_profiles)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          echo ""
          echo -e "${BLUE}$(msg profile_info)${NC}"
          echo "-----------------------------------------------------------------------"

          for profile in "${profiles[@]}"; do
            echo ""
            echo -e "${GREEN}▸ $profile${NC}"
            show_profile_info "$profile" | sed 's/^/  /'
          done

          echo ""
          echo "$(msg press_enter)"
          read

        elif [[ "$PROFILE_ACTION" == *"Delete"* ]] || [[ "$PROFILE_ACTION" == *"삭제"* ]]; then
          # 프로필 삭제
          local profiles=($(list_profiles))

          if [ ${#profiles[@]} -eq 0 ]; then
            echo ""
            echo -e "${YELLOW}$(msg no_profiles)${NC}"
            echo ""
            echo "$(msg press_enter)"
            read
            continue
          fi

          echo ""
          echo "$(msg select_profile)"
          echo ""

          local selected_profile=$(gum choose "${profiles[@]}")

          if [ -n "$selected_profile" ]; then
            delete_profile "$selected_profile"
            local delete_result=$?

            if [ $delete_result -eq 0 ]; then
              echo ""
              echo -e "${GREEN}$(msg profile_deleted)${NC}"
              echo "  $(msg profile_name_label) $selected_profile"
            elif [ $delete_result -eq 2 ]; then
              echo ""
              echo -e "${RED}$(msg profile_cannot_delete_default)${NC}"
            elif [ $delete_result -eq 3 ]; then
              echo ""
              echo -e "${RED}$(msg profile_not_found)${NC}"
            else
              echo ""
              echo -e "${RED}$(msg profile_delete_failed)${NC}"
            fi

            echo ""
            echo "$(msg press_enter)"
            read
          fi

        elif [[ "$PROFILE_ACTION" == *"Back"* ]] || [[ "$PROFILE_ACTION" == *"뒤로"* ]]; then
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
    profile)
      shift
      case "${1:-list}" in
        create)
          shift
          PROFILE_NAME="${1}"
          PROFILE_DESC="${2:-No description}"

          if [ -z "$PROFILE_NAME" ]; then
            echo -e "${RED}✗ Profile name is required${NC}"
            echo "Usage: port-machine profile create <name> [description]"
            exit 1
          fi

          create_profile "$PROFILE_NAME" "$PROFILE_DESC"
          case $? in
            0)
              echo -e "${GREEN}$(msg profile_created)${NC}"
              echo "  $(msg profile_name_label) $PROFILE_NAME"
              ;;
            2)
              echo -e "${RED}$(msg profile_already_exists)${NC}"
              exit 1
              ;;
            *)
              echo -e "${RED}$(msg profile_create_failed)${NC}"
              exit 1
              ;;
          esac
          ;;
        switch)
          shift
          PROFILE_NAME="${1}"

          if [ -z "$PROFILE_NAME" ]; then
            echo -e "${RED}✗ Profile name is required${NC}"
            echo "Usage: port-machine profile switch <name>"
            exit 1
          fi

          load_profile "$PROFILE_NAME"
          case $? in
            0)
              echo -e "${GREEN}$(msg profile_switched) $PROFILE_NAME${NC}"
              local svc_count=$(count_services)
              echo "  $svc_count $(msg services_imported)"
              ;;
            2)
              echo -e "${RED}$(msg profile_not_found)${NC}"
              exit 1
              ;;
            *)
              echo -e "${RED}$(msg profile_switch_failed)${NC}"
              exit 1
              ;;
          esac
          ;;
        list)
          local profiles=($(list_profiles))
          local current_prof=$(get_current_profile)

          if [ ${#profiles[@]} -eq 0 ]; then
            echo -e "${YELLOW}$(msg no_profiles)${NC}"
            exit 0
          fi

          echo -e "${BLUE}=== Profiles ===${NC}"
          echo ""
          for profile in "${profiles[@]}"; do
            if [ "$profile" = "$current_prof" ]; then
              echo -e "${GREEN}▸ $profile (current)${NC}"
            else
              echo "  $profile"
            fi
            show_profile_info "$profile" | sed 's/^/    /'
            echo ""
          done
          ;;
        delete)
          shift
          PROFILE_NAME="${1}"

          if [ -z "$PROFILE_NAME" ]; then
            echo -e "${RED}✗ Profile name is required${NC}"
            echo "Usage: port-machine profile delete <name>"
            exit 1
          fi

          delete_profile "$PROFILE_NAME"
          case $? in
            0)
              echo -e "${GREEN}$(msg profile_deleted)${NC}"
              echo "  $(msg profile_name_label) $PROFILE_NAME"
              ;;
            2)
              echo -e "${RED}$(msg profile_cannot_delete_default)${NC}"
              exit 1
              ;;
            3)
              echo -e "${RED}$(msg profile_not_found)${NC}"
              exit 1
              ;;
            *)
              echo -e "${RED}$(msg profile_delete_failed)${NC}"
              exit 1
              ;;
          esac
          ;;
        *)
          echo "Usage: port-machine profile {create|switch|list|delete} [name] [description]"
          echo ""
          echo "Commands:"
          echo "  create <name> [desc]  Create a new profile from current services"
          echo "  switch <name>         Switch to a different profile"
          echo "  list                  List all profiles"
          echo "  delete <name>         Delete a profile"
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Usage: port-machine {ui|start|stop|status|profile|upgrade|-h|--help}"
      echo ""
      echo "Commands:"
      echo "  ui                     Launch interactive UI"
      echo "  start [services...]    Start port forwarding"
      echo "  stop                   Stop all port forwarding"
      echo "  status                 Show status"
      echo "  profile <subcommand>   Manage profiles"
      echo "  upgrade                Upgrade to latest version"
      echo "  -h, --help             Show help"
      exit 1
      ;;
  esac
}

main "$@"
