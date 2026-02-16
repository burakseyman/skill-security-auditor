#!/bin/bash
# skill-security-test.sh
# Comprehensive automated skill security tester v2.0
# Usage: bash skill-security-test.sh <URL_OR_FILE_PATH>

set -uo pipefail

SKILL_INPUT="$1"
TEST_DIR="/tmp/skill-test-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="$HOME/.claude/skills/skill-security-auditor/reports"
REPORT_FILE="$REPORT_DIR/test-$TIMESTAMP.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create report directory
mkdir -p "$REPORT_DIR"

# Cleanup old reports (keep last 50)
REPORT_COUNT=$(ls -1 "$REPORT_DIR"/test-*.txt 2>/dev/null | wc -l || true)
if [ "$REPORT_COUNT" -gt 50 ]; then
  ls -1t "$REPORT_DIR"/test-*.txt | tail -n +51 | xargs rm -f
fi

# Logging function
log() {
  echo -e "$1" | tee -a "$REPORT_FILE"
}

# Cleanup on exit
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log "${BLUE}Skill Security Tester v2.0${NC}"
log "${BLUE}==========================${NC}"
log "Testing: $SKILL_INPUT"
log "Report: $REPORT_FILE"
log ""

# Check if input is provided
if [ -z "$SKILL_INPUT" ]; then
  echo "Usage: bash skill-security-test.sh <URL_OR_FILE_PATH>"
  echo "Example: bash skill-security-test.sh https://raw.githubusercontent.com/user/repo/SKILL.md"
  exit 1
fi

# Input validation
if [[ "$SKILL_INPUT" =~ [\;\|\&\`] ]]; then
  echo "ERROR: Input contains potentially dangerous characters"
  exit 1
fi

# 1. Download or copy skill
log "${BLUE}[1/13] Acquiring skill file...${NC}"
mkdir -p "$TEST_DIR"

if [[ "$SKILL_INPUT" =~ ^https?:// ]]; then
  if ! [[ "$SKILL_INPUT" =~ ^https?://[a-zA-Z0-9._:/@%-]+$ ]]; then
    echo "ERROR: URL contains unexpected characters"
    exit 1
  fi
  log "  Downloading from URL..."
  if ! curl -sL --max-time 30 --connect-timeout 10 "$SKILL_INPUT" -o "$TEST_DIR/SKILL.md"; then
    log "${RED}  Failed to download skill${NC}"
    exit 1
  fi
else
  if [ ! -f "$SKILL_INPUT" ]; then
    echo "ERROR: File not found: $SKILL_INPUT"
    exit 1
  fi
  log "  Copying local file..."
  cp "$SKILL_INPUT" "$TEST_DIR/SKILL.md"
fi

SKILL_FILE="$TEST_DIR/SKILL.md"
LINE_COUNT=$(wc -l < "$SKILL_FILE" | tr -d ' ')
log "${GREEN}  Skill acquired ($LINE_COUNT lines)${NC}"

# 2. Static analysis - Dangerous patterns
log ""
log "${BLUE}[2/13] Scanning for dangerous patterns...${NC}"

DANGEROUS_PATTERNS=(
  "rm -rf:Critical:40:Destructive file deletion"
  "dd if=:Critical:40:Disk destroyer command"
  "mkfs:Critical:40:Format filesystem"
  "curl.*-X POST.*\$:High:30:POST request with data"
  "wget.*--post-data:High:30:POST with wget"
  "eval \$:High:25:Dynamic code execution"
  "exec \$:High:25:Process execution"
  "/etc/passwd:High:30:Sensitive system file"
  ".ssh/id_rsa:Critical:50:SSH private key access"
  "base64 -d.*|:Medium:20:Piped base64 decode"
  "\${.*PASSWORD.*}:High:30:Password environment variable"
  "chmod 777:Medium:15:Insecure permissions"
  "chown root:High:25:Root ownership change"
  "sudo:Medium:20:Privilege escalation"
  "> /dev/null 2>&1 &:Low:10:Background process hiding"
  "curl.*\|.*bash:Critical:50:Remote code execution pipeline"
  "wget.*\|.*sh:Critical:50:Remote code execution pipeline"
  "nc .*[0-9]:High:30:Netcat connection"
)

FOUND_ISSUES=0
RISK_SCORE=0

for pattern_entry in "${DANGEROUS_PATTERNS[@]}"; do
  IFS=':' read -r pattern severity points description <<< "$pattern_entry"

  if grep -qE "$pattern" "$SKILL_FILE" 2>/dev/null; then
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
    RISK_SCORE=$((RISK_SCORE + points))

    case $severity in
      Critical)
        log "${RED}  [CRITICAL] $description${NC}"
        ;;
      High)
        log "${RED}  [HIGH] $description${NC}"
        ;;
      Medium)
        log "${YELLOW}  [MEDIUM] $description${NC}"
        ;;
      Low)
        log "${YELLOW}  [LOW] $description${NC}"
        ;;
    esac

    # Show line numbers (log-only, no variable mutation needed)
    while IFS= read -r line; do
      log "      Line: $line"
    done < <(grep -n "$pattern" "$SKILL_FILE" 2>/dev/null | head -3)
  fi
done

if [ $FOUND_ISSUES -eq 0 ]; then
  log "${GREEN}  No dangerous patterns found${NC}"
else
  log "${RED}  Found $FOUND_ISSUES dangerous patterns! (+$RISK_SCORE risk points)${NC}"
fi

# 3. Obfuscation check
log ""
log "${BLUE}[3/13] Checking for code obfuscation...${NC}"

OBFUSCATION_PATTERNS=(
  "base64:Base64 encoding"
  "xxd:Hex dump utility"
  "openssl enc:Encryption"
  "rot13:ROT13 encoding"
  "gzip.*base64:Compressed+encoded"
)

OBFUSCATED=0
for pattern_entry in "${OBFUSCATION_PATTERNS[@]}"; do
  IFS=':' read -r pattern description <<< "$pattern_entry"

  if grep -qE "$pattern" "$SKILL_FILE" 2>/dev/null; then
    log "${YELLOW}  $description detected${NC}"
    OBFUSCATED=1
    RISK_SCORE=$((RISK_SCORE + 15))
  fi
done

if [ $OBFUSCATED -eq 0 ]; then
  log "${GREEN}  No obfuscation detected${NC}"
else
  log "${YELLOW}  Obfuscation found (+15 risk points per pattern)${NC}"
fi

# 4. Network activity analysis
log ""
log "${BLUE}[4/13] Analyzing network calls...${NC}"

URLS=$(grep -oE 'https?://[a-zA-Z0-9./?=_&%-]+' "$SKILL_FILE" 2>/dev/null | sort -u || true)
URL_COUNT=0
if [ -n "$URLS" ]; then
  URL_COUNT=$(echo "$URLS" | grep -c . || true)
fi

if [ "$URL_COUNT" -gt 0 ]; then
  log "  Found $URL_COUNT unique URLs:"
  while IFS= read -r url; do
    if echo "$url" | grep -qE "(pastebin|0bin|hastebin|tempfile|anonfile|transfer\.sh|file\.io)"; then
      log "${RED}    SUSPICIOUS: $url${NC}"
      RISK_SCORE=$((RISK_SCORE + 30))
    elif echo "$url" | grep -qE "(github\.com|gitlab\.com|pypi\.org|npmjs\.com|registry\.npmjs\.org|owasp\.org|nist\.gov|cwe\.mitre\.org)"; then
      log "${GREEN}    TRUSTED: $url${NC}"
    else
      log "${YELLOW}    UNKNOWN: $url${NC}"
      RISK_SCORE=$((RISK_SCORE + 5))
    fi
  done < <(echo "$URLS" | head -10)

  if [ "$URL_COUNT" -gt 10 ]; then
    log "    ... and $((URL_COUNT - 10)) more URLs"
  fi
else
  log "${GREEN}  No hardcoded URLs${NC}"
fi

# 5. File operations check
log ""
log "${BLUE}[5/13] Checking file operations...${NC}"

FILE_OPS=$(grep -nE "(Write|Edit|Bash.*>|mv |cp |rm )" "$SKILL_FILE" 2>/dev/null | wc -l | tr -d ' ' || true)

if [ "$FILE_OPS" -gt 0 ]; then
  log "${YELLOW}  $FILE_OPS file operations detected${NC}"
  while IFS= read -r line; do
    log "    $line"
  done < <(grep -nE "(Write|Edit|Bash.*>)" "$SKILL_FILE" 2>/dev/null | head -5)
  RISK_SCORE=$((RISK_SCORE + 5))
else
  log "${GREEN}  No file operations${NC}"
fi

# 6. Credential access check
log ""
log "${BLUE}[6/13] Checking credential access...${NC}"

CREDENTIAL_PATTERNS=(
  "\$HOME/.ssh"
  "\$HOME/.aws"
  "\.env"
  "credentials"
  "api_key"
  "API_KEY"
  "process\.env"
  "PASSWORD"
  "SECRET"
)

CRED_ISSUES=0
for pattern in "${CREDENTIAL_PATTERNS[@]}"; do
  if grep -qE "$pattern" "$SKILL_FILE" 2>/dev/null; then
    log "${RED}  Potential credential access: $pattern${NC}"
    CRED_ISSUES=$((CRED_ISSUES + 1))
    RISK_SCORE=$((RISK_SCORE + 20))
  fi
done

if [ $CRED_ISSUES -eq 0 ]; then
  log "${GREEN}  No credential access detected${NC}"
else
  log "${RED}  Found $CRED_ISSUES credential access patterns (+$((CRED_ISSUES * 20)) risk points)${NC}"
fi

# 7. Dependencies check
log ""
log "${BLUE}[7/13] Checking external dependencies...${NC}"

NPM_DEPS=$(grep -oE "npm install [a-zA-Z0-9@/_-]+" "$SKILL_FILE" 2>/dev/null | cut -d' ' -f3- | sort -u || true)
PIP_DEPS=$(grep -oE "pip install [a-zA-Z0-9_-]+" "$SKILL_FILE" 2>/dev/null | cut -d' ' -f3- | sort -u || true)

if [ -n "$NPM_DEPS" ]; then
  log "  npm dependencies:"
  while IFS= read -r dep; do
    log "    - $dep"
  done < <(echo "$NPM_DEPS")
  RISK_SCORE=$((RISK_SCORE + 5))
fi

if [ -n "$PIP_DEPS" ]; then
  log "  pip dependencies:"
  while IFS= read -r dep; do
    if echo "$dep" | grep -qE "^(numpy|pandas|scipy|requests|matplotlib|flask|django|fastapi|pytest|black|ruff)$"; then
      log "${GREEN}    $dep (trusted)${NC}"
    else
      log "${YELLOW}    $dep (verify)${NC}"
      RISK_SCORE=$((RISK_SCORE + 3))
    fi
  done < <(echo "$PIP_DEPS")
fi

if [ -z "$NPM_DEPS" ] && [ -z "$PIP_DEPS" ]; then
  log "${GREEN}  No external dependencies${NC}"
fi

# 8. Privilege requirements check
log ""
log "${BLUE}[8/13] Checking privilege requirements...${NC}"

if grep -qE "(sudo|chmod 777|chown root)" "$SKILL_FILE" 2>/dev/null; then
  log "${RED}  CRITICAL: Privilege escalation detected!${NC}"
  while IFS= read -r line; do
    log "    $line"
  done < <(grep -nE "(sudo|chmod 777|chown root)" "$SKILL_FILE" 2>/dev/null | head -5)
  RISK_SCORE=$((RISK_SCORE + 40))
else
  log "${GREEN}  No privilege escalation${NC}"
fi

# 9. Metadata extraction
log ""
log "${BLUE}[9/13] Extracting metadata...${NC}"

if grep -q "^name:" "$SKILL_FILE" 2>/dev/null; then
  NAME=$(grep "^name:" "$SKILL_FILE" | head -1 | cut -d: -f2- | xargs)
  log "  Skill name: $NAME"
fi

if grep -q "^description:" "$SKILL_FILE" 2>/dev/null; then
  DESC=$(grep "^description:" "$SKILL_FILE" | head -1 | cut -d: -f2- | xargs | cut -c1-100)
  log "  Description: $DESC..."
fi

if grep -q "^license:" "$SKILL_FILE" 2>/dev/null; then
  LICENSE=$(grep "^license:" "$SKILL_FILE" | head -1 | cut -d: -f2- | xargs)
  log "  License: $LICENSE"

  if [[ "$LICENSE" =~ ^(MIT|Apache|BSD)$ ]]; then
    log "${GREEN}    Open source license (-5 risk points)${NC}"
    RISK_SCORE=$((RISK_SCORE - 5))
  else
    log "${YELLOW}    Non-standard license${NC}"
    RISK_SCORE=$((RISK_SCORE + 10))
  fi
fi

if grep -q "author:" "$SKILL_FILE" 2>/dev/null; then
  AUTHOR=$(grep "author:" "$SKILL_FILE" | head -1 | cut -d: -f2- | xargs)
  log "  Author: $AUTHOR"
fi

# 10. Allowed tools check
log ""
log "${BLUE}[10/13] Checking allowed tools...${NC}"

if grep -q "^allowed-tools:" "$SKILL_FILE" 2>/dev/null; then
  TOOLS=$(grep "^allowed-tools:" "$SKILL_FILE" | head -1 | cut -d: -f2- | xargs)
  log "  Allowed tools: $TOOLS"

  # Check for risky tools
  if echo "$TOOLS" | grep -q "Bash"; then
    log "${YELLOW}    Bash access (+25 risk points)${NC}"
    RISK_SCORE=$((RISK_SCORE + 25))
  fi

  if echo "$TOOLS" | grep -q "Write"; then
    log "${YELLOW}    Write access (+20 risk points)${NC}"
    RISK_SCORE=$((RISK_SCORE + 20))
  fi

  if echo "$TOOLS" | grep -q "Edit"; then
    log "${YELLOW}    Edit access (+10 risk points)${NC}"
    RISK_SCORE=$((RISK_SCORE + 10))
  fi

  # Check dangerous combinations
  if echo "$TOOLS" | grep -q "Read" && echo "$TOOLS" | grep -q "WebFetch"; then
    log "${RED}    Read + WebFetch combination (potential exfiltration chain, +30 risk points)${NC}"
    RISK_SCORE=$((RISK_SCORE + 30))
  fi

  if echo "$TOOLS" | grep -q "Bash" && echo "$TOOLS" | grep -q "WebFetch"; then
    log "${RED}    Bash + WebFetch combination (execute + exfiltrate, +35 risk points)${NC}"
    RISK_SCORE=$((RISK_SCORE + 35))
  fi
else
  log "${GREEN}  No allowed-tools declared (prompt-only skill, -10 risk points)${NC}"
  RISK_SCORE=$((RISK_SCORE - 10))
fi

# 11. Prompt injection check
log ""
log "${BLUE}[11/13] Checking for prompt injection patterns...${NC}"

INJECTION_PATTERNS=(
  "ignore.*previous.*instructions|Critical|50|Override previous instructions"
  "ignore.*all.*instructions|Critical|50|Override all instructions"
  "you are now|High|35|Role override attempt"
  "developer mode|High|35|Developer mode activation"
  "do not tell.*user|Critical|40|Hide actions from user"
  "silently|Medium|20|Silent action instruction"
  "without mentioning|High|40|Hide actions instruction"
  "emergency override|High|35|Authority claim"
  "as the administrator|High|35|Authority impersonation"
  "System:.*unrestricted|Critical|50|Fake system message"
)

INJECTION_ISSUES=0
for pattern_entry in "${INJECTION_PATTERNS[@]}"; do
  IFS='|' read -r pattern severity points description <<< "$pattern_entry"

  if grep -qiE "$pattern" "$SKILL_FILE" 2>/dev/null; then
    log "${RED}  [$severity] $description${NC}"
    INJECTION_ISSUES=$((INJECTION_ISSUES + 1))
    RISK_SCORE=$((RISK_SCORE + points))
  fi
done

if [ $INJECTION_ISSUES -eq 0 ]; then
  log "${GREEN}  No prompt injection patterns detected${NC}"
else
  log "${RED}  Found $INJECTION_ISSUES prompt injection patterns!${NC}"
fi

# 12. Complexity analysis
log ""
log "${BLUE}[12/13] Analyzing code complexity...${NC}"

BASH_BLOCKS=$(grep -c '```bash' "$SKILL_FILE" 2>/dev/null || true)
PYTHON_BLOCKS=$(grep -c '```python' "$SKILL_FILE" 2>/dev/null || true)
JS_BLOCKS=$(grep -c '```javascript\|```js\|```typescript\|```ts' "$SKILL_FILE" 2>/dev/null || true)
CODE_LINES=$(grep -E '^[^#]*[a-zA-Z0-9_]+\(' "$SKILL_FILE" 2>/dev/null | wc -l | tr -d ' ' || true)

log "  Bash code blocks: $BASH_BLOCKS"
log "  Python code blocks: $PYTHON_BLOCKS"
log "  JS/TS code blocks: $JS_BLOCKS"
log "  Executable lines: ~$CODE_LINES"

if [ "$BASH_BLOCKS" -gt 10 ]; then
  log "${YELLOW}  High bash complexity (+10 risk points)${NC}"
  RISK_SCORE=$((RISK_SCORE + 10))
fi

# 13. Final risk calculation
log ""
log "${BLUE}[13/13] Calculating final risk score...${NC}"

# Adjust score based on source if URL provided
TRUSTED_ORGS="anthropics|openai|microsoft|google|modelcontextprotocol|cloudflare|vercel|supabase|stripe|hashicorp|elastic|grafana|mozilla"
if [[ "$SKILL_INPUT" =~ github\.com ]]; then
  if [[ "$SKILL_INPUT" =~ github\.com/($TRUSTED_ORGS) ]]; then
    log "${GREEN}  Official/trusted source (-15 points)${NC}"
    RISK_SCORE=$((RISK_SCORE - 15))
  else
    log "  Third-party GitHub source"
  fi
fi

# Cap risk score
[ $RISK_SCORE -lt 0 ] && RISK_SCORE=0
[ $RISK_SCORE -gt 100 ] && RISK_SCORE=100

# Generate report
log ""
log "${BLUE}==============================${NC}"
log "${BLUE}    FINAL SECURITY REPORT     ${NC}"
log "${BLUE}==============================${NC}"
log ""
log "OVERALL RISK SCORE: $RISK_SCORE/100"
log ""

if [ $RISK_SCORE -lt 20 ]; then
  log "${GREEN}VERDICT: LOW RISK${NC}"
  log "   Generally safe to use with normal precautions"
  VERDICT="APPROVE"
elif [ $RISK_SCORE -lt 50 ]; then
  log "${YELLOW}VERDICT: MEDIUM RISK${NC}"
  log "   Review carefully before use, test in sandbox"
  VERDICT="APPROVE WITH CAUTION"
elif [ $RISK_SCORE -lt 75 ]; then
  log "${RED}VERDICT: HIGH RISK${NC}"
  log "   Significant security concerns, needs mitigation"
  VERDICT="USE WITH EXTREME CAUTION"
else
  log "${RED}VERDICT: CRITICAL RISK${NC}"
  log "   DO NOT USE without thorough expert review!"
  VERDICT="REJECT"
fi

log ""
log "RECOMMENDATION: $VERDICT"
log ""

# Summary stats
log "Analysis Summary:"
log "   - Lines analyzed: $LINE_COUNT"
log "   - Dangerous patterns: $FOUND_ISSUES"
log "   - Prompt injection patterns: $INJECTION_ISSUES"
log "   - Network URLs: $URL_COUNT"
log "   - File operations: $FILE_OPS"
log "   - Credential access: $CRED_ISSUES"
log ""

log "Full report saved to: $REPORT_FILE"
log ""

# Exit with appropriate code
if [ $RISK_SCORE -ge 75 ]; then
  exit 1
else
  exit 0
fi
