#!/bin/bash
# port-machine Installation Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_FILE="$SCRIPT_DIR/dev-port-forward-ui.sh"
COMMAND_NAME="port-machine"
LANG_CONFIG="$HOME/.port-machine-lang"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 언어 선택
select_language() {
  echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   K8s Port Forward Manager - Install    ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo "Select Language / 언어를 선택하세요:"
  echo ""
  echo "1) English"
  echo "2) 한국어"
  echo ""
  echo -n "Choice (1-2): "
  read -r lang_choice

  case $lang_choice in
    1)
      echo "en" > "$LANG_CONFIG"
      LANG="en"
      ;;
    2)
      echo "ko" > "$LANG_CONFIG"
      LANG="ko"
      ;;
    *)
      echo "ko" > "$LANG_CONFIG"
      LANG="ko"
      ;;
  esac
  echo ""
}

# 항상 언어 선택
select_language

# 메시지 가져오기 함수 (Bash 3.2 호환)
msg() {
  local key=$1

  if [ "$LANG" = "en" ]; then
    case $key in
      granting_permission) echo "Granting execute permission to script..." ;;
      no_shell_config) echo "No shell config files found. Creating .zshrc and .bashrc." ;;
      registering_command) echo "Registering $COMMAND_NAME command..." ;;
      already_registered) echo "Already registered (skipped)" ;;
      registration_complete) echo "Registration complete" ;;
      install_complete) echo "files installed successfully!" ;;
      skipped) echo "files were already registered and skipped." ;;
      current_terminal) echo "To use in current terminal, run one of the following:" ;;
      or_new_terminal) echo "Or open a new terminal." ;;
      usage) echo "Usage:" ;;
      usage_ui) echo "Run UI mode" ;;
      usage_start) echo "Start all services" ;;
      usage_stop) echo "Stop all services" ;;
      usage_status) echo "Check status" ;;
    esac
  else
    case $key in
      granting_permission) echo "스크립트에 실행 권한을 부여합니다..." ;;
      no_shell_config) echo "쉘 설정 파일이 없습니다. .zshrc와 .bashrc를 생성합니다." ;;
      registering_command) echo "$COMMAND_NAME 명령어를 등록합니다..." ;;
      already_registered) echo "이미 등록되어 있음 (건너뜀)" ;;
      registration_complete) echo "등록 완료" ;;
      install_complete) echo "개 파일에 설치 완료!" ;;
      skipped) echo "개 파일은 이미 등록되어 있어 건너뛰었습니다." ;;
      current_terminal) echo "현재 터미널에서 바로 사용하려면 다음 중 하나를 실행하세요:" ;;
      or_new_terminal) echo "또는 새 터미널을 여세요." ;;
      usage) echo "사용법:" ;;
      usage_ui) echo "UI 모드 실행" ;;
      usage_start) echo "모든 서비스 시작" ;;
      usage_stop) echo "모든 서비스 중지" ;;
      usage_status) echo "상태 확인" ;;
    esac
  fi
}

# 스크립트 실행 권한 확인 및 부여
if [ ! -x "$SCRIPT_FILE" ]; then
  echo -e "${YELLOW}$(msg granting_permission)${NC}"
  chmod +x "$SCRIPT_FILE"
fi

# alias 정의 (언어 설정 포함)
ALIAS_COMMAND="export PORT_MACHINE_LANG='$LANG'; alias $COMMAND_NAME='$SCRIPT_FILE'"

# 쉘 설정 파일 목록
SHELL_CONFIGS=()

# zshrc
if [ -f "$HOME/.zshrc" ] || [ -n "$ZSH_VERSION" ]; then
  SHELL_CONFIGS+=("$HOME/.zshrc")
fi

# bashrc 또는 bash_profile
if [ -f "$HOME/.bash_profile" ]; then
  SHELL_CONFIGS+=("$HOME/.bash_profile")
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_CONFIGS+=("$HOME/.bashrc")
fi

# 설정 파일이 없으면 생성
if [ ${#SHELL_CONFIGS[@]} -eq 0 ]; then
  echo -e "${YELLOW}$(msg no_shell_config)${NC}"
  touch "$HOME/.zshrc"
  touch "$HOME/.bashrc"
  SHELL_CONFIGS=("$HOME/.zshrc" "$HOME/.bashrc")
fi

echo -e "${YELLOW}$(msg registering_command)${NC}"
echo ""

INSTALLED_COUNT=0
SKIPPED_COUNT=0

# 각 설정 파일에 alias 추가 또는 업데이트
for config in "${SHELL_CONFIGS[@]}"; do
  if grep -q "alias $COMMAND_NAME=" "$config" 2>/dev/null; then
    # 기존 alias 제거 (PORT_MACHINE_LANG 설정 포함)
    grep -v "PORT_MACHINE_LANG" "$config" | grep -v "alias $COMMAND_NAME=" > "${config}.tmp"
    mv "${config}.tmp" "$config"

    # 새 alias 추가
    echo "" >> "$config"
    echo "# K8s Port Forward Manager" >> "$config"
    echo "$ALIAS_COMMAND" >> "$config"
    echo -e "${GREEN}✓${NC} $(basename $config): $(msg registration_complete) (updated)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  else
    echo "" >> "$config"
    echo "# K8s Port Forward Manager" >> "$config"
    echo "$ALIAS_COMMAND" >> "$config"
    echo -e "${GREEN}✓${NC} $(basename $config): $(msg registration_complete)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  fi
done

echo ""

# 현재 세션에서도 사용 가능하도록
export PORT_MACHINE_LANG="$LANG"
alias "$COMMAND_NAME"="$SCRIPT_FILE"

if [ $INSTALLED_COUNT -gt 0 ]; then
  echo -e "${GREEN}✓ $INSTALLED_COUNT $(msg install_complete)${NC}"
fi

if [ $SKIPPED_COUNT -gt 0 ]; then
  echo -e "${YELLOW}⊘ $SKIPPED_COUNT $(msg skipped)${NC}"
fi

echo ""
echo -e "${YELLOW}$(msg current_terminal)${NC}"
for config in "${SHELL_CONFIGS[@]}"; do
  echo "  source $config"
done
echo ""
echo "$(msg or_new_terminal)"

echo ""
echo -e "${GREEN}$(msg usage)${NC}"
echo "  $COMMAND_NAME          # $(msg usage_ui)"
echo "  $COMMAND_NAME start    # $(msg usage_start)"
echo "  $COMMAND_NAME stop     # $(msg usage_stop)"
echo "  $COMMAND_NAME status   # $(msg usage_status)"
