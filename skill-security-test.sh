#!/bin/bash
# skill-security-test.sh
# Comprehensive automated skill security tester
# Usage: bash skill-security-test.sh <URL_OR_FILE_PATH>

set -e

SKILL_INPUT="$1"
TEST_DIR="/tmp/skill-test-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$HOME/.claude/skills/skill-security-auditor/reports/test-$TIMESTAMP.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create report directory
mkdir -p "$HOME/.claude/skills/skill-security-auditor/reports"

# Logging function
log() {
  echo -e "$1" | tee -a "$REPORT_FILE"
}

log "${BLUE}🔒 Skill Security Tester${NC}"
log "${BLUE}=======================${NC}"
log "Testing: $SKILL_INPUT"
log "Report: $REPORT_FILE"
log ""

# Check if input is provided
if [ -z "$SKILL_INPUT" ]; then
  echo "Usage: bash skill-security-test.sh <URL_OR_FILE_PATH>"
  echo "Example: bash skill-security-test.sh https://raw.githubusercontent.com/user/repo/SKILL.md"
  exit 1
fi

# 1. Download or copy skill
log "${BLUE}[1/12] Acquiring skill file...${NC}"
mkdir -p "$TEST_DIR"

if [[ "$SKILL_INPUT" =~ ^https?:// ]]; then
  log "  📥 Downloading from URL..."
  curl -sL "$SKILL_INPUT" -o "$TEST_DIR/SKILL.md"
  if [ $? -ne 0 ]; then
    log "${RED}  ❌ Failed to download skill${NC}"
    exit 1
  fi
else
  log "  📂 Copying local file..."
  cp "$SKILL_INPUT" "$TEST_DIR/SKILL.md"
fi

SKILL_FILE="$TEST_DIR/SKILL.md"
LINE_COUNT=$(wc -l < "$SKILL_FILE")
log "${GREEN}  ✅ Skill acquired ($LINE_COUNT lines)${NC}"

# 2. Static analysis - Dangerous patterns
log ""
log "${BLUE}[2/12] Scanning for dangerous patterns...${NC}"

DANGEROUS_PATTERNS=(
  "rm -rf:Critical:40:Destructive file deletion"
  "dd if=:Critical:40:Disk destroyer command"
  "mkfs:Critical:40:Format filesystem"
  "curl.*-X POST.*\$:High:30:POST request with data"
  "wget.*--post-data:High:30:POST with wget"
  "eval.*\$:High:25:Dynamic code execution"
  "exec.*\$:High:25:Process execution"
  "/etc/passwd:High:30:Sensitive system file"
  ".ssh/id_rsa:Critical:50:SSH private key access"
  "base64 -d.*|:Medium:20:Piped base64 decode"
  "\${.*PASSWORD.*}:High:30:Password environment variable"
  "chmod 777:Medium:15:Insecure permissions"
  "chown root:High:25:Root ownership change"
  "sudo:Medium:20:Privilege escalation"
  "> /dev/null 2>&1 &:Low:10:Background process hiding"
)

FOUND_ISSUES=0
RISK_SCORE=0

for pattern_entry in "${DANGEROUS_PATTERNS[@]}"; do
  IFS=':' read -r pattern severity points description <<< "$pattern_entry"

  if grep -qE "$pattern" "$SKILL_FILE"; then
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
    RISK_SCORE=$((RISK_SCORE + points))

    case $severity in
      Critical)
        log "${RED}  🚨 [$severity] $description${NC}"
        ;;
      High)
        log "${RED}  ⚠️  [$severity] $description${NC}"
        ;;
      Medium)
        log "${YELLOW}  ⚠️  [$severity] $description${NC}"
        ;;
      Low)
        log "${YELLOW}  ℹ️  [$severity] $description${NC}"
        ;;
    esac

    # Show line numbers
    grep -n "$pattern" "$SKILL_FILE" | head -3 | while read -r line; do
      log "      Line: $line"
    done
  fi
done

if [ $FOUND_ISSUES -eq 0 ]; then
  log "${GREEN}  ✅ No dangerous patterns found${NC}"
else
  log "${RED}  ❌ Found $FOUND_ISSUES dangerous patterns! (+$RISK_SCORE risk points)${NC}"
fi

# 3. Obfuscation check
log ""
log "${BLUE}[3/12] Checking for code obfuscation...${NC}"

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

  if grep -qE "$pattern" "$SKILL_FILE"; then
    log "${YELLOW}  ⚠️  $description detected${NC}"
    OBFUSCATED=1
    RISK_SCORE=$((RISK_SCORE + 15))
  fi
done

if [ $OBFUSCATED -eq 0 ]; then
  log "${GREEN}  ✅ No obfuscation detected${NC}"
else
  log "${YELLOW}  ⚠️  Obfuscation found (+15 risk points)${NC}"
fi

# 4. Network activity analysis
log ""
log "${BLUE}[4/12] Analyzing network calls...${NC}"

URLS=$(grep -oE 'https?://[a-zA-Z0-9./?=_&%-]+' "$SKILL_FILE" | sort -u)
URL_COUNT=$(echo "$URLS" | grep -c . || echo 0)

if [ $URL_COUNT -gt 0 ]; then
  log "  📡 Found $URL_COUNT unique URLs:"
  echo "$URLS" | head -10 | while read -r url; do
    # Check if URL is suspicious
    if echo "$url" | grep -qE "(pastebin|0bin|hastebin|tempfile|anonfile)"; then
      log "${RED}    🚨 SUSPICIOUS: $url${NC}"
      RISK_SCORE=$((RISK_SCORE + 30))
    elif echo "$url" | grep -qE "(github\.com|gitlab\.com|pypi\.org|npmjs\.com)"; then
      log "${GREEN}    ✅ TRUSTED: $url${NC}"
    else
      log "${YELLOW}    ⚠️  UNKNOWN: $url${NC}"
      RISK_SCORE=$((RISK_SCORE + 5))
    fi
  done

  if [ $URL_COUNT -gt 10 ]; then
    log "    ... and $((URL_COUNT - 10)) more URLs"
  fi
else
  log "${GREEN}  ✅ No hardcoded URLs${NC}"
fi

# 5. File operations check
log ""
log "${BLUE}[5/12] Checking file operations...${NC}"

FILE_OPS=$(grep -nE "(Write|Edit|Bash.*>|mv |cp |rm )" "$SKILL_FILE" | wc -l)

if [ $FILE_OPS -gt 0 ]; then
  log "${YELLOW}  ⚠️  $FILE_OPS file operations detected${NC}"
  grep -nE "(Write|Edit|Bash.*>)" "$SKILL_FILE" | head -5 | while read -r line; do
    log "    $line"
  done
  RISK_SCORE=$((RISK_SCORE + 5))
else
  log "${GREEN}  ✅ No file operations${NC}"
fi

# 6. Credential access check
log ""
log "${BLUE}[6/12] Checking credential access...${NC}"

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
  if grep -qE "$pattern" "$SKILL_FILE"; then
    log "${RED}  🚨 Potential credential access: $pattern${NC}"
    CRED_ISSUES=$((CRED_ISSUES + 1))
    RISK_SCORE=$((RISK_SCORE + 20))
  fi
done

if [ $CRED_ISSUES -eq 0 ]; then
  log "${GREEN}  ✅ No credential access detected${NC}"
else
  log "${RED}  ❌ Found $CRED_ISSUES credential access patterns (+$((CRED_ISSUES * 20)) risk points)${NC}"
fi

# 7. Dependencies check
log ""
log "${BLUE}[7/12] Checking external dependencies...${NC}"

NPM_DEPS=$(grep -oE "npm install [a-zA-Z0-9@/_-]+" "$SKILL_FILE" | cut -d' ' -f3- | sort -u)
PIP_DEPS=$(grep -oE "pip install [a-zA-Z0-9_-]+" "$SKILL_FILE" | cut -d' ' -f3- | sort -u)

if [ -n "$NPM_DEPS" ]; then
  log "  📦 npm dependencies:"
  echo "$NPM_DEPS" | while read -r dep; do
    log "    - $dep"
  done
  RISK_SCORE=$((RISK_SCORE + 5))
fi

if [ -n "$PIP_DEPS" ]; then
  log "  📦 pip dependencies:"
  echo "$PIP_DEPS" | while read -r dep; do
    # Check if it's a known safe package
    if echo "$dep" | grep -qE "^(numpy|pandas|scipy|requests|matplotlib)$"; then
      log "${GREEN}    ✅ $dep (trusted)${NC}"
    else
      log "${YELLOW}    ⚠️  $dep (verify)${NC}"
      RISK_SCORE=$((RISK_SCORE + 3))
    fi
  done
fi

if [ -z "$NPM_DEPS" ] && [ -z "$PIP_DEPS" ]; then
  log "${GREEN}  ✅ No external dependencies${NC}"
fi

# 8. Privilege requirements check
log ""
log "${BLUE}[8/12] Checking privilege requirements...${NC}"

if grep -qE "(sudo|chmod 777|chown root)" "$SKILL_FILE"; then
  log "${RED}  ❌ CRITICAL: Privilege escalation detected!${NC}"
  grep -nE "(sudo|chmod 777|chown root)" "$SKILL_FILE" | head -5 | while read -r line; do
    log "    $line"
  done
  RISK_SCORE=$((RISK_SCORE + 40))
else
  log "${GREEN}  ✅ No privilege escalation${NC}"
fi

# 9. Metadata extraction
log ""
log "${BLUE}[9/12] Extracting metadata...${NC}"

if grep -q "^name:" "$SKILL_FILE"; then
  NAME=$(grep "^name:" "$SKILL_FILE" | cut -d: -f2- | xargs)
  log "  📝 Skill name: $NAME"
fi

if grep -q "^description:" "$SKILL_FILE"; then
  DESC=$(grep "^description:" "$SKILL_FILE" | cut -d: -f2- | xargs | cut -c1-100)
  log "  📄 Description: $DESC..."
fi

if grep -q "^license:" "$SKILL_FILE"; then
  LICENSE=$(grep "^license:" "$SKILL_FILE" | cut -d: -f2- | xargs)
  log "  📜 License: $LICENSE"

  if [[ "$LICENSE" =~ ^(MIT|Apache|BSD)$ ]]; then
    log "${GREEN}    ✅ Open source license${NC}"
  else
    log "${YELLOW}    ⚠️  Non-standard license${NC}"
    RISK_SCORE=$((RISK_SCORE + 10))
  fi
fi

if grep -q "^author:" "$SKILL_FILE"; then
  AUTHOR=$(grep "^author:" "$SKILL_FILE" | cut -d: -f2- | xargs)
  log "  👤 Author: $AUTHOR"
fi

# 10. Allowed tools check
log ""
log "${BLUE}[10/12] Checking allowed tools...${NC}"

if grep -q "^allowed-tools:" "$SKILL_FILE"; then
  TOOLS=$(grep "^allowed-tools:" "$SKILL_FILE" | cut -d: -f2- | xargs)
  log "  🔧 Allowed tools: $TOOLS"

  # Check for risky tools
  if echo "$TOOLS" | grep -q "Bash"; then
    log "${YELLOW}    ⚠️  Bash access (review commands)${NC}"
    RISK_SCORE=$((RISK_SCORE + 10))
  fi

  if echo "$TOOLS" | grep -qE "(Write|Edit)"; then
    log "${YELLOW}    ⚠️  File modification access${NC}"
    RISK_SCORE=$((RISK_SCORE + 5))
  fi
fi

# 11. Complexity analysis
log ""
log "${BLUE}[11/12] Analyzing code complexity...${NC}"

BASH_BLOCKS=$(grep -c '```bash' "$SKILL_FILE" || echo 0)
PYTHON_BLOCKS=$(grep -c '```python' "$SKILL_FILE" || echo 0)
CODE_LINES=$(grep -E '^[^#]*[a-zA-Z0-9_]+\(' "$SKILL_FILE" | wc -l)

log "  📊 Bash code blocks: $BASH_BLOCKS"
log "  📊 Python code blocks: $PYTHON_BLOCKS"
log "  📊 Executable lines: ~$CODE_LINES"

if [ $BASH_BLOCKS -gt 10 ]; then
  log "${YELLOW}  ⚠️  High bash complexity (+10 risk points)${NC}"
  RISK_SCORE=$((RISK_SCORE + 10))
fi

# 12. Final risk calculation
log ""
log "${BLUE}[12/12] Calculating final risk score...${NC}"

# Adjust score based on source if URL provided
if [[ "$SKILL_INPUT" =~ github\.com ]]; then
  if [[ "$SKILL_INPUT" =~ github\.com/(anthropics|openai|microsoft) ]]; then
    log "${GREEN}  ✅ Official/trusted source (-20 points)${NC}"
    RISK_SCORE=$((RISK_SCORE - 20))
  else
    log "  ℹ️  Third-party GitHub source"
  fi
fi

# Ensure score doesn't go negative
[ $RISK_SCORE -lt 0 ] && RISK_SCORE=0

# Generate report
log ""
log "${BLUE}═══════════════════════════════════${NC}"
log "${BLUE}        FINAL SECURITY REPORT       ${NC}"
log "${BLUE}═══════════════════════════════════${NC}"
log ""
log "📊 ${BLUE}OVERALL RISK SCORE: $RISK_SCORE/100${NC}"
log ""

if [ $RISK_SCORE -lt 20 ]; then
  log "🟢 ${GREEN}VERDICT: LOW RISK${NC}"
  log "   Generally safe to use with normal precautions"
  VERDICT="APPROVE"
elif [ $RISK_SCORE -lt 50 ]; then
  log "🟡 ${YELLOW}VERDICT: MEDIUM RISK${NC}"
  log "   Review carefully before use, test in sandbox"
  VERDICT="APPROVE WITH CAUTION"
elif [ $RISK_SCORE -lt 75 ]; then
  log "🟠 ${RED}VERDICT: HIGH RISK${NC}"
  log "   Significant security concerns, needs mitigation"
  VERDICT="USE WITH EXTREME CAUTION"
else
  log "🔴 ${RED}VERDICT: CRITICAL RISK${NC}"
  log "   DO NOT USE without thorough expert review!"
  VERDICT="REJECT"
fi

log ""
log "📋 ${BLUE}RECOMMENDATION: $VERDICT${NC}"
log ""

# Summary stats
log "📈 ${BLUE}Analysis Summary:${NC}"
log "   - Lines analyzed: $LINE_COUNT"
log "   - Dangerous patterns: $FOUND_ISSUES"
log "   - Network URLs: $URL_COUNT"
log "   - File operations: $FILE_OPS"
log "   - Credential access: $CRED_ISSUES"
log ""

log "📄 Full report saved to: $REPORT_FILE"
log ""

# Cleanup
rm -rf "$TEST_DIR"

# Exit with appropriate code
if [ $RISK_SCORE -ge 75 ]; then
  exit 1
else
  exit 0
fi
