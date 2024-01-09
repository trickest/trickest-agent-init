#!/bin/bash

OS=$(awk -F= '/^ID=/{print tolower($2)}' /etc/os-release | tr -d '"')
echo "Detected OS: $OS"
# TRICKEST_DATA_DIR - do not change this one, it it still not configurable, coming soon
TRICKEST_DATA_DIR="/data"
# TRICKEST_JOB_LOGS_PATH - do not change this one, it it still not configurable, coming soon
TRICKEST_JOB_LOGS_PATH="${TRICKEST_DATA_DIR}/storage/container"
TRICKEST_RSYSLOG_CONF_PATH="/etc/rsyslog.d/99-trickest.conf"

detect_agent_service() {
	AGENT_SERVICE_STATUS=$(
		sudo systemctl status trickest-agent >/dev/null 2>&1
		echo $?
	)
	case "$AGENT_SERVICE_STATUS" in
	4)
		echo "Service not detected, proceeding..."
		;;
	3)
		echo "Service already stopped, proceeding..."
		;;
	0)
		echo "Service already running..."
		read -r -p "Stop the service now, and proceed with update? [y/N] : " choice
		case "$choice" in
		[yY][eE][sS] | [yY])
			echo "Stopping service..."
			sudo systemctl stop trickest-agent
			;;
		*)
			exit "Aborting initialization"
			;;
		esac
		;;
	*)
		echo "Service is in non running, nor stopped state, assuming not working..."
		;;
	esac
}

check_docker() {
	if which docker 2>&1 >/dev/null; then
		echo "Docker found..."
	else
		echo "Docker not found..."
		read -r -p "Do you wish to attempt automatic installation of the Docker? (needs sudo privilege!) [y/N] : " choice
		case "$choice" in
		[yY][eE][sS] | [yY])
			install_docker
			;;
		*)
			echo "Refer to https://docs.docker.com/engine/install/ for installation instructions."
			exit "Aborting initialization"
			;;
		esac
	fi
}

install_docker() {
	curl -fsSL https://get.docker.com -o get-docker.sh
	sh ./get-docker.sh
	rm ./get-docker.sh
}

check_rsyslog() {
	if sudo bash -c 'which rsyslogd 2>&1 >/dev/null'; then
		echo "rsyslog found..."
	else
		echo "rsyslog not found..."
		read -r -p "Do you wish to attempt automatic installation of the rsyslog? (needs sudo privilege!) [y/N] : " choice
		case "$choice" in
		[yY][eE][sS] | [yY])
			install_rsyslog
			;;
		*)
			echo "Refer to https://www.rsyslog.com for installation instructions."
			exit "Aborting initialization"
			;;
		esac
	fi
}

install_rsyslog() {
	case "$OS" in
	ubuntu)
		echo "Adding rsyslog repository..."
		sudo add-apt-repository -y ppa:adiscon/v8-stable >/dev/null
		echo "Updating apt-get..."
		sudo apt-get -qq update
		echo "Installing rsyslog on Ubuntu..."
		sudo apt-get -qq install -y rsyslog
		;;
	fedora)
		echo "Installing rsyslog on Fedora..."
		dnf install -y rsyslog >/dev/null
		echo "rsyslog installed successfully."
		;;
	centos)
		echo "Installing rsyslog on CentOS..."
		yum install -y rsyslog >/dev/null
		echo "rsyslog installed successfully."
		;;
	*)
		echo "Unsupported OS. rsyslog installation not supported."
		exit 1
		;;
	esac
	echo "rsyslog is installed..."
}

configure_rsyslog() {
	echo "Configuring rsyslog for Trickest agent..."

	echo "The rsyslog configuration file will be created at: ${TRICKEST_RSYSLOG_CONF_PATH}"
	read -r -p "Please confirm to proceed with rsyslog configuration (y/n): " confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		if ! cat <<EOF >"${TRICKEST_RSYSLOG_CONF_PATH}"; then
\$EscapeControlCharactersOnReceive off

\$template DockerFileName,"/data/storage/container/%syslogtag:R,ERE,1,FIELD:twe/(.*)\[--end%-%syslogpriority%.log"
\$template DockerLog,"%msg:2:\$%\n"

:syslogtag,startswith,"twe/" ?DockerFileName;DockerLog

& ~
EOF
			echo "Failed to configure rsyslog."
			exit 1
		else
		  sudo systemctl restart rsyslog
			echo "rsyslog configured successfully. Configuration file created at: ${TRICKEST_RSYSLOG_CONF_PATH}"
		fi
	else
		echo "rsyslog configuration cancelled."
		exit 1
	fi
}

configure_rsyslog_permissions_best_effort() {
  if [ -f /etc/rsyslog.conf ]
  then
    _RSYSLOG_FILE_OWNER=$(grep "\$FileOwner" /etc/rsyslog.conf | cut -d' ' -f2)
    _RSYSLOG_GROUP_OWNER=$(grep "\$FileGroup" /etc/rsyslog.conf | cut -d' ' -f2)
    if [ "${_RSYSLOG_FILE_OWNER}" != "" ] && [ "${_RSYSLOG_GROUP_OWNER}" != "" ] 
    then
      echo "Ensuring directory rsyslog permissions..."
      _RSYSLOG_CONATINER_DIR_PERMISSION="${_RSYSLOG_FILE_OWNER}:${_RSYSLOG_GROUP_OWNER}"
      chown ${_RSYSLOG_CONATINER_DIR_PERMISSION} ${TRICKEST_JOB_LOGS_PATH}
    else 
      echo "Failed extracting file owner, and group..."
    fi
  else 
    echo "Coult not find /etc/rsyslog.conf..."
  fi

	if [ -f /etc/apparmor.d/usr.sbin.rsyslogd ]
	then
		if grep ' include if exists <rsyslog.d>' /etc/apparmor.d/usr.sbin.rsyslogd
		then
			echo "Configuring AppArmor rsyslog trickest patch..."
			_RSYSLOG_PROFILE_INCLUDE="/data/storage/container/**	rw,"
			echo "${_RSYSLOG_PROFILE_INCLUDE}" > /etc/apparmor.d/rsyslog.d/trickest
			apparmor_parser -r /etc/apparmor.d/usr.sbin.rsyslogd
		else 
			echo "Cannot include Trickest conf to AppArmor rsyslog profile, skipping..."
		fi
	fi
}

test_rsyslog() {
  if which logger >/dev/null 2>&1
  then
      echo "Testing rsyslog implementation..."
      msg="testing Trickest rsyslog implementation"
      logger -p daemon.info -t 'twe/init-test[99]' "${msg} stdout" && sleep 2
      if [[ $(grep "${msg}" "${TRICKEST_JOB_LOGS_PATH}/init-test-6.log" 2>&1 >/dev/null; echo $?) != 0 ]]; then
          echo "rsyslog implementation test failed at stdout..."
          echo "Please write to us at Discord for support: https://trickest.com/community/"
          exit 1
      fi

      logger -p daemon.err -t 'twe/init-test[99]' "${msg} st" && sleep 2
      if [[ $(grep "${msg}" "${TRICKEST_JOB_LOGS_PATH}/init-test-3.log" 2>&1 >/dev/null; echo $?) != 0 ]]; then
          echo "rsyslog implementation test failed at stderr..."
          echo "Please write to us at Discord for support: https://trickest.com/community/"
          exit 1
      fi

      rm "${TRICKEST_JOB_LOGS_PATH}/init-test-6.log"
      rm "${TRICKEST_JOB_LOGS_PATH}/init-test-3.log"
  else
    echo "Cloud not find logger command, cannot test rsyslog implementation, skipping ..."
  fi
}

ensure_data_dir_structure() {
	if [ -d ${TRICKEST_DATA_DIR} ]; then
		echo "Directory intended for trickest data usage already exists at ${TRICKEST_DATA_DIR}"
		read -r -p "Do you wish to proceed? [y/N] : " choice
		case "$choice" in
		[yY][eE][sS] | [yY])
			echo "Proceeding..."
			clear_cache
			;;
		*)
			exit "Aborting initialization"
			;;
		esac
	else
		echo "Creating directory structure intended for Trickest data usage at ${TRICKEST_DATA_DIR}"
		create_data_directory
	fi
}

create_data_directory() {
	if ! mkdir -p ${TRICKEST_JOB_LOGS_PATH}; then
		echo "Failed to create data directory structure."
		exit 1
	fi
}

clear_cache() {
	echo "Clearing cache..."
	if [ -f "${TRICKEST_DATA_DIR}/agent.crt" ]; then
		rm -f "${TRICKEST_DATA_DIR}/agent.crt"
	fi
	if [ -f "${TRICKEST_DATA_DIR}/agent.key" ]; then
		rm -f "${TRICKEST_DATA_DIR}/agent.key"
	fi
	if [ -f "${TRICKEST_DATA_DIR}/ca.crt" ]; then
		rm -f "${TRICKEST_DATA_DIR}/ca.crt"
	fi
}

download_trickest_agent() {
  case $(uname -s) in
    Linux)
      echo "Detected Linux OS..."
      ;;
    *)
      echo "Unsupported OS. Please contact us at Discord for support: https://trickest.com/community/"
      ;;
  esac
  
  case $(uname -p) in
    x86_64)
      echo "Downloading latest Trickest agent for x86_64..."
      agent_url="https://trickest-agent-binary.s3.eu-central-1.amazonaws.com/latest/linux/amd64/twe-agent"
      ;;
    aarch64)
      echo "Downloading latest Trickest agent for aarch64..."
      agent_url="https://trickest-agent-binary.s3.eu-central-1.amazonaws.com/latest/linux/arm64/twe-agent"
      ;;
    *)
      echo "Unsupported architecture. Please contact us at Discord for support: https://trickest.com/community/"
      ;;
  esac

	agent_path="${TRICKEST_DATA_DIR}/trickest-agent"
  if ! curl -s -o "$agent_path" "$agent_url"; then
		echo "Failed to download Trickest agent."
		exit 1
	fi
	chmod +x "$agent_path"
}

ensure_auth_env_variables() {
	if [[ -z "$TRICKEST_CLIENT_AUTH_ID" ]]; then
		echo "TRICKEST_CLIENT_AUTH_ID is not set. Go to https://trickest.io/dashboard/settings/fleet and click on "Add Machine" to generate new TRICKEST_CLIENT_AUTH_ID for your machine"
		exit 1
	fi

	if [[ -z "$TRICKEST_CLIENT_AUTH_SECRET" ]]; then
		echo "TRICKEST_CLIENT_AUTH_SECRET is not set. Go to https://trickest.io/dashboard/settings/fleet and click on "Add Machine"to generate new TRICKEST_CLIENT_AUTH_SECRET for your machine"
		exit 1
	fi
}

create_systemd_service() {
	service_file="/etc/systemd/system/trickest-agent.service"
	log_file="/data/trickest-agent.log"

	if ! touch "$service_file"; then
		echo "Failed to create systemd service file."
		exit 1
	fi

	if ! touch "$log_file"; then
		echo "Failed to create log file."
		exit 1
	fi

	cat <<EOF >"$service_file"
[Unit]
Description=Trickest Workflow Engine - Agent
After=network-online.target
Wants=docker.service
StartLimitBurst=25
StartLimitIntervalSec=100

[Service]
User=root
Type=simple
ExecStart=/bin/bash -c '${TRICKEST_DATA_DIR}/trickest-agent -c ${TRICKEST_DATA_DIR}/conf.yaml run'
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF
	echo "Systemd service file created at: $service_file"
	echo "Reloading systemd daemon..."
	sudo systemctl daemon-reload
}

generate_config_file() {
	echo "Generating config file..."
	ensure_auth_env_variables
	config_file="${TRICKEST_DATA_DIR}/conf.yaml"

	if ! touch "$config_file"; then
		echo "Failed to create config file."
		exit 1
	fi

	cat <<EOF >"$config_file"
log:
  file: ${TRICKEST_DATA_DIR}/trickest-agent.log
node:
    endpoint: "https://api.trickest.io/node"
client:
    auth:
        id: "${TRICKEST_CLIENT_AUTH_ID}"
        secret: "${TRICKEST_CLIENT_AUTH_SECRET}"
        endpoint: "https://api.trickest.io/oauth2/token"
EOF
}

start_and_verify_service() {
  echo "Starting Trickest agent service..."
  sudo systemctl daemon-reload
  set -e
	sudo systemctl start trickest-agent.service
	set +e
	sleep 5
	let try=0
	echo "Waiting for Trickest agent service..."
	while true; do
      if [ $(systemctl show -p SubState trickest-agent.service | cut -d'=' -f2) == "running" ]; then
          echo "Trickest agent service started successfully."
          break
      fi
      let try+=1
      if [ $try -gt 15 ]; then
        echo "Trickest agent service failed to start. Please start it manually using the following command:"
        echo "/data/trickest-agent -c /data/conf.yaml run"
        echo "Please send the output of the manual start command to support@trickest.com for further assistance."
        exit
      fi
      sleep 2
  done
}

detect_agent_service
check_docker
ensure_data_dir_structure
check_rsyslog
configure_rsyslog_permissions_best_effort
configure_rsyslog
test_rsyslog
download_trickest_agent
create_systemd_service
generate_config_file
start_and_verify_service
