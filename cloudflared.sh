#!/bin/bash

# Function to log messages with timestamp
log_message() {
  local message="$1"
  printf "%s - %s\n" "$(date +"%Y-%m-%d %H:%M:%S")" "$message" | tee -a cloudflared_me.log
}

# Function to check for necessary commands
check_command() {
  command -v "$1" >/dev/null 2>&1 || {
    log_message "Error: $1 is not installed. Please install it and try again."
    exit 1
  }
}

# Function to ensure cloudflared is installed and authenticated
ensure_cloudflared() {
  check_command "cloudflared"
  log_message "Ensuring cloudflared is authenticated..."
  cloudflared tunnel login || {
    log_message "Error: cloudflared login failed. Please authenticate and try again."
    exit 1
  }
  log_message "cloudflared authenticated successfully."
}

# Function to create a new Cloudflare tunnel
create_tunnel() {
  log_message "Creating a new Cloudflare tunnel..."
  tunnel_id=$(cloudflared tunnel create "$tunnel_name" | grep -oP '(?<=ID: )[a-zA-Z0-9-]+') || {
    log_message "Error: Failed to create tunnel."
    exit 1
  }
  log_message "Tunnel created successfully with ID: $tunnel_id"
}

# Function to backup existing config.yaml
backup_config() {
  if [[ -f "$config_file" ]]; then
    log_message "Backing up existing config.yaml..."
    cp "$config_file" "${config_file}.bak"
    log_message "Backup created: ${config_file}.bak"
  fi
}

# Function to generate or modify the config.yaml file
generate_config_yaml() {
  log_message "Generating or modifying config.yaml..."
  config_file="${config_dir}/config.yaml"
  backup_config

  # Read existing config.yaml content if it exists
  if [[ -f "$config_file" ]]; then
    existing_config=$(<"$config_file")
  else
    existing_config=""
  fi

  # Check if tunnel with same name or domain already exists
  if echo "$existing_config" | grep -q "tunnel: $tunnel_id"; then
    log_message "Tunnel with the same ID already exists in config.yaml."
  elif echo "$existing_config" | grep -q "hostname: $domain"; then
    log_message "Domain already exists in config.yaml."
  else
    # Append new tunnel configuration
    new_tunnel_config="
tunnel: $tunnel_id
credentials-file: ${config_dir}/$tunnel_id.json

ingress:
  - hostname: $domain
    service: http://localhost:$port
  - service: http_status:404"

    echo "$existing_config" | grep -v '^[[:space:]]*#' | grep -q '^[[:space:]]*tunnel:' && {
      # Append new tunnel configuration to the existing one
      config_with_new_tunnel="$existing_config"$'\n'"$new_tunnel_config"
    } || {
      # Create new tunnel configuration
      config_with_new_tunnel="$new_tunnel_config"
    }

    echo "$config_with_new_tunnel" > "$config_file"
    log_message "config.yaml created/modified successfully."
  fi
}

# Function to run the tunnel in the background
run_tunnel() {
  log_message "Starting the Cloudflare tunnel in the background..."
  nohup cloudflared tunnel run "$tunnel_id" &> cloudflared_tunnel.log &
  tunnel_pid=$!
  log_message "Tunnel started successfully with PID: $tunnel_pid"
}

# Function to route DNS
route_dns() {
  log_message "Routing DNS..."
  cloudflared tunnel route dns "$tunnel_id" "$domain" || {
    log_message "Error: Failed to route DNS."
    exit 1
  }
  log_message "DNS routed successfully to $domain."
}

# Function to show usage
show_usage() {
  echo "Usage: $0 -p <port> -d <domain> -n <tunnel_name> [-c <config_dir>] [-h]"
  echo "Options:"
  echo "  -p  Specify the port to route traffic to"
  echo "  -d  Specify the domain to route traffic from"
  echo "  -n  Specify the name of the Cloudflare tunnel"
  echo "  -c  Specify a custom configuration directory (default is ~/.cloudflared)"
  echo "  -h  Show this help message"
  exit 0
}

# Parse command-line arguments
while getopts ":p:d:n:c:h" opt; do
  case ${opt} in
    p )
      port=$OPTARG
      ;;
    d )
      domain=$OPTARG
      ;;
    n )
      tunnel_name=$OPTARG
      ;;
    c )
      config_dir=$OPTARG
      ;;
    h )
      show_usage
      ;;
    \? )
      show_usage
      ;;
  esac
done

# Validate arguments
if [[ -z "$port" || -z "$domain" || -z "$tunnel_name" ]]; then
  show_usage
fi

# Validate port number
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -le 0 ] || [ "$port" -gt 65535 ]; then
  log_message "Error: Invalid port number. Please provide a valid port number between 1 and 65535."
  exit 1
fi

# Validate domain name
if ! [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  log_message "Error: Invalid domain name. Please provide a valid domain name."
  exit 1
fi

# Set default config directory if not provided
config_dir=${config_dir:-"$HOME/.cloudflared"}

# Ensure the config directory exists
mkdir -p "$config_dir"

# Main script
log_message "Starting CloudflaredMe script..."
ensure_cloudflared
create_tunnel
generate_config_yaml
run_tunnel
route_dns
log_message "CloudflaredMe script completed successfully."

exit 0
