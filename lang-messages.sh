#!/bin/bash
# Multi-language support for port-machine (Bash 3.2 compatible)

# 언어 설정 파일
LANG_CONFIG="$HOME/.port-machine-lang"

# 환경변수에서 언어 가져오기, 없으면 설정 파일에서 읽기
if [ -n "$PORT_MACHINE_LANG" ]; then
  LANG="$PORT_MACHINE_LANG"
elif [ -f "$LANG_CONFIG" ]; then
  LANG=$(cat "$LANG_CONFIG")
else
  LANG="ko"  # 기본값: 한국어
fi

# 메시지 가져오기 함수 (Bash 3.2 호환)
msg() {
  local key=$1

  if [ "$LANG" = "en" ]; then
    case $key in
      # gum installation
      gum_not_installed) echo "gum is not installed." ;;
      install_method) echo "Installation method:" ;;
      install_now) echo "Install now? (y/n): " ;;
      fallback_mode) echo "Running in basic mode without gum..." ;;

      # Status messages
      starting) echo "Starting port forwarding..." ;;
      started) echo "✓ Port forwarding started successfully." ;;
      running_background) echo "Running in background." ;;
      stop_cmd) echo "To stop:" ;;
      stopped) echo "✓ All port forwarding stopped." ;;
      running) echo "Running" ;;
      terminated) echo "Terminated" ;;
      no_services_running) echo "No port forwarding running." ;;
      running_services) echo "● Running:" ;;
      services_count) echo "service(s)" ;;
      no_services) echo "● No services running" ;;
      registered_services) echo "No registered services." ;;
      current_services) echo "Currently registered services:" ;;

      # UI menu
      menu_start) echo "🚀 Start Services" ;;
      menu_stop) echo "⏹️  Stop All" ;;
      menu_status) echo "📊 Check Status" ;;
      menu_list) echo "📝 Service List" ;;
      menu_manage) echo "⚙️  Manage Services" ;;
      menu_logs) echo "📋 View Logs" ;;
      menu_exit) echo "❌ Exit" ;;

      # Service management
      manage_add) echo "➕ Add Service" ;;
      manage_delete) echo "➖ Delete Service (multi-select)" ;;
      manage_edit) echo "✏️  Edit Port" ;;
      manage_back) echo "◀️  Back" ;;

      # Input prompts
      select_services) echo "Select services to port-forward (Space to select, Enter to confirm):" ;;
      enter_service_info) echo "Enter new service information:" ;;
      service_name) echo "Service name:" ;;
      namespace) echo "Namespace:" ;;
      local_port) echo "Local port:" ;;
      remote_port) echo "Remote port:" ;;
      example) echo "Example:" ;;
      select_to_delete) echo "Select services to delete (Space to select, Enter to confirm):" ;;
      select_to_edit) echo "Select service to edit:" ;;
      current_settings) echo "Current settings:" ;;
      enter_new_values) echo "Enter new values (Press Enter to keep current value):" ;;
      confirm_input) echo "Confirm input:" ;;
      confirm_add) echo "Add with these values?" ;;

      # Result messages
      canceled) echo "Canceled." ;;
      service_added) echo "Service added successfully!" ;;
      service_deleted) echo "Service deleted successfully." ;;
      service_updated) echo "Service updated successfully!" ;;
      already_exists) echo "✗ Service name already exists:" ;;
      local_port_required) echo "✗ Local port is required." ;;
      no_services_to_delete) echo "No services to delete." ;;
      no_services_to_edit) echo "No services to edit." ;;
      refreshing) echo "Refreshing list..." ;;
      deleted) echo "Deleted" ;;

      # Headers
      header_title) echo "K8s Port Forward Manager" ;;
      header_manage) echo "Service Management" ;;
      header_status) echo "=== Port Forwarding Status ===" ;;
      header_list) echo "=== Configured Services ===" ;;

      # Table headers
      table_pid) echo "PID" ;;
      table_service) echo "Service" ;;
      table_status) echo "Status" ;;
      table_service_name) echo "Service Name" ;;
      table_namespace) echo "Namespace" ;;
      table_local_port) echo "Local Port" ;;
      table_remote_port) echo "Remote Port" ;;

      # Misc
      press_enter) echo "Press Enter to continue..." ;;
      exiting) echo "👋 Exiting." ;;
      no_logs) echo "No log files found." ;;
      choice) echo "Choice (1-5):" ;;
      none) echo "None" ;;

      # Kubernetes context
      current_context) echo "Current Context:" ;;
      context_not_set) echo "Context not set" ;;

      # Version
      version_label) echo "Version:" ;;

      # Help messages
      help_usage) echo "Usage:" ;;
      help_description) echo "K8s Port Forward Manager - Interactive TUI tool for managing Kubernetes port forwarding" ;;
      help_commands) echo "Commands:" ;;
      help_ui) echo "Launch interactive UI mode (default)" ;;
      help_start) echo "Start port forwarding for all or specific services" ;;
      help_stop) echo "Stop all port forwarding" ;;
      help_status) echo "Show status of running port forwards" ;;
      help_upgrade) echo "Upgrade to the latest version from GitHub" ;;
      help_help) echo "Show this help message" ;;
      help_examples) echo "Examples:" ;;
      help_example1) echo "Start interactive mode" ;;
      help_example2) echo "Start all services" ;;
      help_example3) echo "Start specific services" ;;
      help_example4) echo "Check status" ;;
      help_example5) echo "Stop all services" ;;
      help_example6) echo "Upgrade to latest version" ;;

      # Config management
      menu_config) echo "💾 Config Management" ;;
      config_export_yaml) echo "📤 Export to YAML" ;;
      config_export_ini) echo "📤 Export to INI" ;;
      config_import_yaml) echo "📥 Import from YAML" ;;
      config_import_ini) echo "📥 Import from INI" ;;
      config_back) echo "◀️  Back" ;;

      # Export/Import messages
      export_success) echo "✓ Configuration exported successfully!" ;;
      export_location) echo "Location:" ;;
      import_success) echo "✓ Configuration imported successfully!" ;;
      import_failed) echo "✗ Import failed. File not found or invalid format." ;;
      enter_file_path) echo "Enter file path (or press Enter for default):" ;;
      import_confirm) echo "This will replace current services. Continue?" ;;
      backup_created) echo "Backup created:" ;;
      services_imported) echo "services imported." ;;
    esac
  else
    case $key in
      # gum 설치
      gum_not_installed) echo "gum이 설치되어 있지 않습니다." ;;
      install_method) echo "설치 방법:" ;;
      install_now) echo "지금 설치하시겠습니까? (y/n): " ;;
      fallback_mode) echo "gum 없이 기본 모드로 실행합니다..." ;;

      # 상태 메시지
      starting) echo "포트 포워딩 시작 중..." ;;
      started) echo "✓ 포트 포워딩이 시작되었습니다." ;;
      running_background) echo "백그라운드에서 실행 중입니다." ;;
      stop_cmd) echo "중지하려면:" ;;
      stopped) echo "✓ 모든 포트 포워딩이 중지되었습니다." ;;
      running) echo "실행 중" ;;
      terminated) echo "종료됨" ;;
      no_services_running) echo "실행 중인 포트 포워딩이 없습니다." ;;
      running_services) echo "● 실행 중:" ;;
      services_count) echo "개 서비스" ;;
      no_services) echo "● 실행 중인 서비스 없음" ;;
      registered_services) echo "등록된 서비스가 없습니다." ;;
      current_services) echo "현재 등록된 서비스:" ;;

      # UI 메뉴
      menu_start) echo "🚀 서비스 시작" ;;
      menu_stop) echo "⏹️  모두 중지" ;;
      menu_status) echo "📊 상태 확인" ;;
      menu_list) echo "📝 서비스 목록" ;;
      menu_manage) echo "⚙️  서비스 관리" ;;
      menu_logs) echo "📋 로그 보기" ;;
      menu_exit) echo "❌ 종료" ;;

      # 서비스 관리
      manage_add) echo "➕ 서비스 추가" ;;
      manage_delete) echo "➖ 서비스 삭제 (다중선택)" ;;
      manage_edit) echo "✏️  포트 수정" ;;
      manage_back) echo "◀️  뒤로" ;;

      # 입력 프롬프트
      select_services) echo "포트 포워딩할 서비스를 선택하세요 (Space로 선택, Enter로 확인):" ;;
      enter_service_info) echo "새 서비스 정보를 입력하세요:" ;;
      service_name) echo "서비스명:" ;;
      namespace) echo "네임스페이스:" ;;
      local_port) echo "로컬 포트:" ;;
      remote_port) echo "원격 포트:" ;;
      example) echo "예:" ;;
      select_to_delete) echo "삭제할 서비스를 선택하세요 (Space로 선택, Enter로 확인):" ;;
      select_to_edit) echo "수정할 서비스를 선택하세요:" ;;
      current_settings) echo "현재 설정:" ;;
      enter_new_values) echo "새 값을 입력하세요 (Enter만 누르면 기존 값 유지):" ;;
      confirm_input) echo "입력 확인:" ;;
      confirm_add) echo "이대로 추가하시겠습니까?" ;;

      # 결과 메시지
      canceled) echo "취소되었습니다." ;;
      service_added) echo "서비스가 추가되었습니다!" ;;
      service_deleted) echo "서비스가 삭제되었습니다." ;;
      service_updated) echo "서비스가 수정되었습니다!" ;;
      already_exists) echo "✗ 이미 존재하는 서비스명입니다:" ;;
      local_port_required) echo "✗ 로컬 포트는 필수입니다." ;;
      no_services_to_delete) echo "삭제할 서비스가 없습니다." ;;
      no_services_to_edit) echo "수정할 서비스가 없습니다." ;;
      refreshing) echo "목록 갱신 중..." ;;
      deleted) echo "삭제됨" ;;

      # 헤더
      header_title) echo "K8s Port Forward Manager" ;;
      header_manage) echo "서비스 관리" ;;
      header_status) echo "=== 포트 포워딩 상태 ===" ;;
      header_list) echo "=== 설정된 서비스 목록 ===" ;;

      # 테이블 헤더
      table_pid) echo "PID" ;;
      table_service) echo "서비스" ;;
      table_status) echo "상태" ;;
      table_service_name) echo "서비스명" ;;
      table_namespace) echo "네임스페이스" ;;
      table_local_port) echo "로컬 포트" ;;
      table_remote_port) echo "원격 포트" ;;

      # 기타
      press_enter) echo "Press Enter to continue..." ;;
      exiting) echo "👋 종료합니다." ;;
      no_logs) echo "로그 파일이 없습니다." ;;
      choice) echo "선택 (1-5):" ;;
      none) echo "없음" ;;

      # Kubernetes 컨텍스트
      current_context) echo "현재 컨텍스트:" ;;
      context_not_set) echo "컨텍스트 미설정" ;;

      # 버전
      version_label) echo "버전:" ;;

      # 도움말 메시지
      help_usage) echo "사용법:" ;;
      help_description) echo "K8s Port Forward Manager - Kubernetes 포트 포워딩 관리를 위한 대화형 TUI 도구" ;;
      help_commands) echo "명령어:" ;;
      help_ui) echo "대화형 UI 모드 실행 (기본값)" ;;
      help_start) echo "모든 서비스 또는 특정 서비스의 포트 포워딩 시작" ;;
      help_stop) echo "모든 포트 포워딩 중지" ;;
      help_status) echo "실행 중인 포트 포워딩 상태 표시" ;;
      help_upgrade) echo "GitHub에서 최신 버전으로 업그레이드" ;;
      help_help) echo "이 도움말 메시지 표시" ;;
      help_examples) echo "예제:" ;;
      help_example1) echo "대화형 모드 시작" ;;
      help_example2) echo "모든 서비스 시작" ;;
      help_example3) echo "특정 서비스 시작" ;;
      help_example4) echo "상태 확인" ;;
      help_example5) echo "모든 서비스 중지" ;;
      help_example6) echo "최신 버전으로 업그레이드" ;;

      # 설정 관리
      menu_config) echo "💾 설정 관리" ;;
      config_export_yaml) echo "📤 YAML로 내보내기" ;;
      config_export_ini) echo "📤 INI로 내보내기" ;;
      config_import_yaml) echo "📥 YAML에서 가져오기" ;;
      config_import_ini) echo "📥 INI에서 가져오기" ;;
      config_back) echo "◀️  뒤로" ;;

      # Export/Import 메시지
      export_success) echo "✓ 설정이 성공적으로 내보내졌습니다!" ;;
      export_location) echo "위치:" ;;
      import_success) echo "✓ 설정을 성공적으로 가져왔습니다!" ;;
      import_failed) echo "✗ 가져오기 실패. 파일을 찾을 수 없거나 형식이 올바르지 않습니다." ;;
      enter_file_path) echo "파일 경로 입력 (기본값은 Enter):" ;;
      import_confirm) echo "현재 서비스를 모두 대체합니다. 계속하시겠습니까?" ;;
      backup_created) echo "백업 생성됨:" ;;
      services_imported) echo "개 서비스를 가져왔습니다." ;;
    esac
  fi
}
