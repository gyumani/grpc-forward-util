#!/bin/bash
# port-machine Upgrade Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/gyumani/grpc-forward-util.git"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CURRENT_VERSION="1.1.1"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   K8s Port Forward Manager - Upgrade    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# Git이 설치되어 있는지 확인
if ! command -v git &> /dev/null; then
  echo -e "${RED}✗ Git이 설치되어 있지 않습니다.${NC}"
  echo ""
  echo "Git을 먼저 설치해주세요:"
  echo "  brew install git"
  exit 1
fi

# 현재 버전 표시
if [ -f "$VERSION_FILE" ]; then
  CURRENT_VERSION=$(cat "$VERSION_FILE")
fi

echo -e "${YELLOW}현재 버전: ${NC}v$CURRENT_VERSION"
echo ""

# Git 저장소인지 확인
if [ ! -d "$SCRIPT_DIR/.git" ]; then
  echo -e "${RED}✗ 이 디렉토리는 Git 저장소가 아닙니다.${NC}"
  echo ""
  echo "업그레이드를 사용하려면 Git을 통해 설치해야 합니다:"
  echo "  git clone $REPO_URL"
  exit 1
fi

echo -e "${YELLOW}업데이트 확인 중...${NC}"
echo ""

# 원격 저장소에서 최신 정보 가져오기
cd "$SCRIPT_DIR"
git fetch origin --quiet

# 로컬과 원격 비교
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u})
BASE=$(git merge-base @ @{u})

if [ "$LOCAL" = "$REMOTE" ]; then
  echo -e "${GREEN}✓ 이미 최신 버전입니다!${NC}"
  exit 0
elif [ "$LOCAL" = "$BASE" ]; then
  echo -e "${YELLOW}새 버전이 있습니다!${NC}"
  echo ""

  # 최신 태그 확인
  LATEST_TAG=$(git describe --tags --abbrev=0 origin/master 2>/dev/null || echo "")
  if [ -n "$LATEST_TAG" ]; then
    echo -e "${BLUE}최신 버전: ${NC}$LATEST_TAG"
    echo ""
  fi

  # 변경사항 미리보기
  echo -e "${BLUE}변경사항:${NC}"
  git log --oneline --decorate --graph HEAD..origin/master | head -10
  echo ""

  # 업그레이드 확인
  echo -n "업그레이드를 진행하시겠습니까? (y/n): "
  read -r answer

  if [[ "$answer" != "y" ]]; then
    echo ""
    echo -e "${YELLOW}업그레이드가 취소되었습니다.${NC}"
    exit 0
  fi

  echo ""
  echo -e "${YELLOW}업그레이드 중...${NC}"
  echo ""

  # 사용자 설정 백업
  if [ -f "$HOME/.k8s-port-forward-services.list" ]; then
    cp "$HOME/.k8s-port-forward-services.list" "$HOME/.k8s-port-forward-services.list.backup"
    echo -e "${GREEN}✓${NC} 서비스 목록 백업 완료"
  fi

  if [ -f "$HOME/.port-machine-lang" ]; then
    cp "$HOME/.port-machine-lang" "$HOME/.port-machine-lang.backup"
    echo -e "${GREEN}✓${NC} 언어 설정 백업 완료"
  fi

  # Git pull
  git pull origin master

  if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ 업그레이드가 완료되었습니다!${NC}"
    echo ""

    # 버전 파일 업데이트
    if [ -f "$VERSION_FILE" ]; then
      NEW_VERSION=$(cat "$VERSION_FILE")
      echo -e "${BLUE}업데이트된 버전: ${NC}v$NEW_VERSION"
    elif [ -n "$LATEST_TAG" ]; then
      echo "$LATEST_TAG" | sed 's/^v//' > "$VERSION_FILE"
      echo -e "${BLUE}업데이트된 버전: ${NC}$LATEST_TAG"
    fi

    echo ""
    echo -e "${YELLOW}변경사항을 적용하려면 다음 중 하나를 실행하세요:${NC}"
    echo "  source ~/.zshrc   # zsh 사용 시"
    echo "  source ~/.bashrc  # bash 사용 시"
    echo ""
    echo "또는 새 터미널을 여세요."

    # 실행 권한 확인
    chmod +x "$SCRIPT_DIR"/*.sh

  else
    echo ""
    echo -e "${RED}✗ 업그레이드 중 오류가 발생했습니다.${NC}"
    echo ""

    # 백업에서 복원
    if [ -f "$HOME/.k8s-port-forward-services.list.backup" ]; then
      cp "$HOME/.k8s-port-forward-services.list.backup" "$HOME/.k8s-port-forward-services.list"
      echo -e "${GREEN}✓${NC} 서비스 목록 복원 완료"
    fi

    if [ -f "$HOME/.port-machine-lang.backup" ]; then
      cp "$HOME/.port-machine-lang.backup" "$HOME/.port-machine-lang"
      echo -e "${GREEN}✓${NC} 언어 설정 복원 완료"
    fi

    exit 1
  fi

elif [ "$REMOTE" = "$BASE" ]; then
  echo -e "${YELLOW}⚠ 로컬 변경사항이 있습니다.${NC}"
  echo ""
  echo "업그레이드하기 전에 로컬 변경사항을 커밋하거나 되돌려주세요:"
  echo "  git status"
  exit 1
else
  echo -e "${YELLOW}⚠ 브랜치가 분기되었습니다.${NC}"
  echo ""
  echo "Git 상태를 확인해주세요:"
  echo "  git status"
  exit 1
fi
