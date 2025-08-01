#!/bin/bash

# ---------------- HEADER ----------------
clear
echo -e "\e[1;36m"
echo "=============================================="
echo "        DNS Benchmark & Auto-Configuration"
echo "    Originally made by Matthew Deiter"
echo "=============================================="
echo -e "\e[0m"

# ---------------- CONFIGURATION SECTION ----------------
DNS_SERVERS=(
  "8.8.8.8"           # Google Primary
  "8.8.4.4"           # Google Secondary
  "1.1.1.1"           # Cloudflare Primary
  "1.0.0.1"           # Cloudflare Secondary
  "208.67.222.222"    # OpenDNS Primary
  "208.67.220.220"    # OpenDNS Secondary
  "9.9.9.9"           # Quad9 Primary
  "149.112.112.112"   # Quad9 Secondary
)

TEST_DOMAINS=("google.com" "cloudflare.com" "github.com")
DNSSEC_DOMAIN="cloudflare.com"
RETRIES=3
TIMEOUT=3

# Custom logic parameters:
MAX_ALLOWED_LATENCY=100        # ms
PROVIDER_FILTER="Cloudflare"   # Only use servers with this string in get_server_name ("" for any)

# Integration: choose how to apply DNS
DNS_APPLY_METHOD="auto"  # "resolvconf", "networkmanager", "systemd-resolved", or "auto"

# Stats output file
STATS_FILE="/tmp/dns_benchmark_stats_$(date +%Y%m%d_%H%M%S).csv"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------------- LOGGING PROMPT AND SETUP ----------------
read -rp "Do you want to enable detailed logging of all DNS test output? (recommended) (y/N): " enable_log

if [[ "$enable_log" =~ ^[Yy]$ ]]; then
  ENABLE_LOGGING=true
else
  ENABLE_LOGGING=false
fi

LOG_FILE="/tmp/dns_benchmark_$(date +%Y%m%d_%H%M%S).log"

log() {
  if [ "$ENABLE_LOGGING" = true ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  fi
}

# ---------------- SERVER NAME HELPER ----------------
get_server_name() {
  case "$1" in
    "8.8.8.8") echo "Google Primary";;
    "8.8.4.4") echo "Google Secondary";;
    "1.1.1.1") echo "Cloudflare Primary";;
    "1.0.0.1") echo "Cloudflare Secondary";;
    "208.67.222.222") echo "OpenDNS Primary";;
    "208.67.220.220") echo "OpenDNS Secondary";;
    "9.9.9.9") echo "Quad9 Primary";;
    "149.112.112.112") echo "Quad9 Secondary";;
    *) echo "Unknown";;
  esac
}

# ---------------- MAIN TEST FUNCTION ----------------
test_dns_server_enhanced() {
  local server=$1
  local retries=$2
  local total_time=0
  local successful_queries=0
  local failed_queries=0
  local dnssec_supported=false
  local consistency_score=0
  local error_message=""

  for domain in "${TEST_DOMAINS[@]}"; do
    for ((i=1; i<=retries; i++)); do
      local start_time=$(date +%s%3N)
      local dig_output
      if command -v timeout >/dev/null; then
        dig_output=$(timeout "${TIMEOUT}"s dig @"$server" "$domain" A +tries=1 +time=2 +noall +answer 2>&1)
        local exit_code=$?
      else
        dig_output=$(dig @"$server" "$domain" A +tries=1 +time=2 +noall +answer 2>&1)
        local exit_code=$?
      fi
      local end_time=$(date +%s%3N)

      if [ "$ENABLE_LOGGING" = true ]; then
        echo "===== DIG OUTPUT (${server} -> ${domain}) =====" >> "$LOG_FILE"
        echo "$dig_output" >> "$LOG_FILE"
      fi

      if [ $exit_code -eq 0 ] && [ -n "$dig_output" ] && ! echo "$dig_output" | grep -iqE "connection timed out|no servers could be reached|timed out|SERVFAIL|REFUSED"; then
        local response_time=$((end_time - start_time))
        (( response_time > 5000 )) && response_time=5000
        total_time=$((total_time + response_time))
        successful_queries=$((successful_queries + 1))

        if [ $response_time -lt 200 ]; then
          consistency_score=$((consistency_score + 3))
        elif [ $response_time -lt 500 ]; then
          consistency_score=$((consistency_score + 2))
        else
          consistency_score=$((consistency_score + 1))
        fi

        break
      else
        failed_queries=$((failed_queries + 1))
        if [ -z "$error_message" ]; then
          error_message="$dig_output"
          if [ "$ENABLE_LOGGING" = true ]; then
            echo "=== ERROR DETAILS for $server ===" >> "$LOG_FILE"
            echo "$error_message" >> "$LOG_FILE"
          fi
        fi
      fi
    done
  done

  # DNSSEC test with logging (improved: use +dnssec and check for RRSIG)
  local dnssec_check
  if command -v timeout >/dev/null; then
    dnssec_check=$(timeout 3s dig @"$server" "$DNSSEC_DOMAIN" A +dnssec +noall +answer +ttlid 2>&1)
  else
    dnssec_check=$(dig @"$server" "$DNSSEC_DOMAIN" A +dnssec +noall +answer +ttlid 2>&1)
  fi
  if [ "$ENABLE_LOGGING" = true ]; then
    echo "===== DNSSEC CHECK ($server) =====" >> "$LOG_FILE"
    echo "$dnssec_check" >> "$LOG_FILE"
  fi

  if echo "$dnssec_check" | grep -q 'RRSIG'; then
    dnssec_supported=true
  fi

  local avg_response_time="FAILED"
  local reliability=0
  local total_queries=$((successful_queries + failed_queries))
  if [ $successful_queries -gt 0 ]; then
    avg_response_time=$((total_time / successful_queries))
    reliability=$((successful_queries * 100 / total_queries))
  fi

  if [ "$avg_response_time" = "FAILED" ]; then
    echo "$avg_response_time:$dnssec_supported:$reliability:$consistency_score:$error_message"
  else
    echo "$avg_response_time:$dnssec_supported:$reliability:$consistency_score"
  fi
}

# ---------------- APPLY SYSTEM DNS HELPERS ----------------
apply_dns_resolvconf() {
  local servers=("$@")
  local backup_file="/etc/resolv.conf.dnsbench.bak"
  echo -e "${YELLOW}Backing up current /etc/resolv.conf to $backup_file...${NC}"
  sudo cp /etc/resolv.conf "$backup_file"
  echo -e "${GREEN}Updating /etc/resolv.conf...${NC}"
  for srv in "${servers[@]}"; do
    echo "nameserver $srv"
  done | sudo tee /etc/resolv.conf > /dev/null
  echo -e "${GREEN}System DNS updated in /etc/resolv.conf.${NC}"
}

apply_dns_networkmanager() {
  local servers=("$@")
  local dns_string="${servers[*]}"
  local cons
  cons=$(nmcli -g NAME,TYPE con show | awk -F: '$2 ~ /ethernet|wifi/ {print $1}')
  for con in $cons; do
    echo -e "${GREEN}Updating DNS for NetworkManager connection: $con${NC}"
    nmcli con mod "$con" ipv4.ignore-auto-dns yes
    nmcli con mod "$con" ipv4.dns "$dns_string"
    nmcli con up "$con"
  done
}

apply_dns_systemd_resolved() {
  local servers=("$@")
  local dns_string="${servers[*]}"
  # Extract interface names without parentheses
  for iface in $(resolvectl status | awk '/^Link [0-9]/ {gsub(/[()]/,"",$3); print $3}'); do
    echo -e "${GREEN}Setting DNS for systemd-resolved on $iface: $dns_string${NC}"
    sudo resolvectl dns "$iface" $dns_string
  done
  sudo systemctl restart systemd-resolved
}

apply_dns_auto() {
  # Try to detect system type and apply best method
  if pidof systemd-resolved >/dev/null 2>&1; then
    apply_dns_systemd_resolved "$@"
  elif pidof NetworkManager >/dev/null 2>&1; then
    apply_dns_networkmanager "$@"
  else
    apply_dns_resolvconf "$@"
  fi
}

# ---------------- MAIN SCRIPT LOGIC ----------------
main() {
  # Print CSV header
  echo "server,server_name,avg_time_ms,dnssec,reliability,quality" > "$STATS_FILE"
  declare -a all_results
  echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - DNS Benchmark started with ${#DNS_SERVERS[@]} servers${NC}"
  log "DNS Benchmark started with ${#DNS_SERVERS[@]} servers"

  for server in "${DNS_SERVERS[@]}"; do
    server_name=$(get_server_name "$server")
    result=$(test_dns_server_enhanced "$server" "$RETRIES")
    avg_time=$(echo "$result" | cut -d: -f1)
    dnssec=$(echo "$result" | cut -d: -f2)
    reliability=$(echo "$result" | cut -d: -f3)
    consistency=$(echo "$result" | cut -d: -f4)
    error_msg=$(echo "$result" | cut -d: -f5-)

    # Save stats
    echo "$server,$server_name,$avg_time,$dnssec,$reliability,$consistency" >> "$STATS_FILE"

    # Custom logic: filter by provider, DNSSEC, reliability, and latency
    if [ "$avg_time" != "FAILED" ] \
      && [ "$dnssec" = "true" ] \
      && [ "$reliability" = "100" ] \
      && [ "$avg_time" -le "$MAX_ALLOWED_LATENCY" ] \
      && { [ -z "$PROVIDER_FILTER" ] || [[ "$server_name" =~ $PROVIDER_FILTER ]]; }
    then
      all_results+=( "$server $avg_time" )
    fi

    # Output
    if [ "$avg_time" = "FAILED" ]; then
      echo -e "${RED}Tested $server ($server_name): FAILED${NC}"
      echo -e "${RED}  Error: $error_msg${NC}"
      log "Tested $server ($server_name): FAILED | $error_msg"
    else
      echo -e "${GREEN}Tested $server ($server_name): ${avg_time}ms, DNSSEC: $dnssec, Reliability: ${reliability}%, Quality: $consistency${NC}"
      log "Tested $server ($server_name): ${avg_time}ms, DNSSEC: $dnssec, Reliability: ${reliability}%, Quality: $consistency"
    fi
  done

  echo -e "${YELLOW}Full stats saved to $STATS_FILE${NC}"

  # Sort by avg_time (ascending), pick top 2
  mapfile -t top2 < <(printf "%s\n" "${all_results[@]}" | sort -k2 -n | head -2 | awk '{print $1}')

  if [ "${#top2[@]}" -ge 1 ]; then
    echo -e "${YELLOW}Top DNSSEC-supporting servers matching your criteria: ${top2[*]}${NC}"
    read -rp "Update system DNS with these? (y/N): " set_dns
    if [[ "$set_dns" =~ ^[Yy]$ ]]; then
      case "$DNS_APPLY_METHOD" in
        "resolvconf")           apply_dns_resolvconf "${top2[@]}";;
        "networkmanager")       apply_dns_networkmanager "${top2[@]}";;
        "systemd-resolved")     apply_dns_systemd_resolved "${top2[@]}";;
        *)                      apply_dns_auto "${top2[@]}";;
      esac
      echo "System DNS updated to use: ${top2[*]}"
    else
      echo "System DNS not changed."
    fi
  else
    echo -e "${RED}No servers matched your criteria (DNSSEC, reliability, provider, latency).${NC}"
  fi
}

main