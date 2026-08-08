# --- Zsh Real-time Logging (Local VM Storage Version) ---

# Base directory for logs and notes
export LOG_DIR_BASE="$HOME/0_logs"

if [[ -z "$ZSH_LOGGING_ACTIVE" ]]; then
    export ZSH_LOGGING_ACTIVE=1

    # Save everything to a reliable directory in the user's home folder.
    mkdir -p "$LOG_DIR_BASE"
    LOG_DATE=$(date +"%Y-%m-%d")

    local RAW_LOG_FILE="$LOG_DIR_BASE/${LOG_DATE}.raw.log"
    local CLEAN_LOG_FILE="$LOG_DIR_BASE/${LOG_DATE}.clean.log"

    touch "$RAW_LOG_FILE"
    touch "$CLEAN_LOG_FILE"

    local SED_CLEANUP_COMMAND="/^Script started/d; /^Script done/d; s/.\x08//g; s/\x1b=//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b].* //g; s/\r//g"

    tail -f "$RAW_LOG_FILE" | sed -u "$SED_CLEANUP_COMMAND" >> "$CLEAN_LOG_FILE" &
    export ZSH_LOG_TAIL_PID=$!

    print -P "%B%F{green}Session logging to:%f%b
 -> RAW:   %B${RAW_LOG_FILE}%b
 -> CLEAN: %B${CLEAN_LOG_FILE}%b"

    script -qfa "$RAW_LOG_FILE"
    exit
fi

# --- This code runs inside the logged shell ---

zmodload zsh/datetime
autoload -U add-zsh-hook

_zsh_log_command_marker() {
    local command_to_log="$3"
    [[ -z "$command_to_log" ]] && return
    print -r -- "\n##> $(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS) ## ${command_to_log}" >&2
}
add-zsh-hook preexec _zsh_log_command_marker

zshexit() {
    kill "$ZSH_LOG_TAIL_PID" &>/dev/null
}

# --- opnotes: Focused Note-Taking ---
opnotes() {
    local NOTES_FILE="$LOG_DIR_BASE/1_opnotes.txt"

    mkdir -p "$LOG_DIR_BASE"
    touch "$NOTES_FILE"

    # Use the external .vimrc file for vim configuration
    vim "$NOTES_FILE"
}

# --- VPN Disconnect ---
vpn-disconnect() {
  sudo killall openvpn
  echo "Done: Terminating all OpenVPN processes..."
}

# --- EZ VPN Connect ---
vpn-connect() {
  # Check for .ovpn files in /vagrant/
  if ! ls /vagrant/*.ovpn >/dev/null 2>&1; then
    echo "No .ovpn files found in /vagrant/"
    return 1
  fi
  # Since we know files exist, we can now safely populate the array.
  local files=(/vagrant/*.ovpn)
  # Present a numbered list of the .ovpn files for the user to select.
  echo "Please select an OpenVPN configuration file:"
  select file in "${files[@]}"; do
    # If the user's selection is valid (not empty).
    if [[ -n "$file" ]]; then
      vpn-disconnect
      # Get the base name of the file (e.g., "myconfig" from "/vagrant/myconfig.ovpn")
      local log_name=$(basename "$file" .ovpn)
      echo "Starting OpenVPN with config: $file"
      echo "Log file will be at in /tmp/vpn_${log_name}.log"
      # Run the OpenVPN command with the selected file and corrected log path.
      sudo nohup openvpn --config "$file" > "/tmp/vpn_${log_name}.log" 2>&1 &
      # Wait for OpenVPN to initialize
      sleep 10
      # Check the log file for connection status
      if grep -q "Initialization Sequence Completed" "/tmp/vpn_${log_name}.log" 2>/dev/null; then
        echo "✅ VPN connection successful!"
      elif grep -qi "error\|failed\|fatal" "/tmp/vpn_${log_name}.log" 2>/dev/null; then
        echo "❌ VPN connection failed. Check /tmp/vpn_${log_name}.log for details."
      else
        echo "⏳ VPN is still connecting... Check /tmp/vpn_${log_name}.log for status."
      fi
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
}

# Add hashcat-utils binaries
export PATH=$PATH:/usr/lib/hashcat-utils

# Enable colors for terminal applications
export TERM=xterm-256color

# Aliases
alias ll='ls -la --color=auto'
alias msfconsole='sudo msfconsole -q'
