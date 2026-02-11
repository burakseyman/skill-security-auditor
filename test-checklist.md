# Skill Security Test Checklist

## Pre-Installation Static Analysis

### 1. Source Code Review
```bash
# Download skill without installing
curl -o /tmp/skill-to-test.md https://raw.githubusercontent.com/USER/REPO/SKILL.md

# Manual inspection
cat /tmp/skill-to-test.md | grep -E "(bash|curl|wget|eval|exec|rm|dd)"
```

**Red Flags to Search:**
- [ ] `bash`, `sh -c`, `eval`, `exec`
- [ ] `curl`, `wget`, `fetch` with POST requests
- [ ] `rm -rf`, `dd`, destructive commands
- [ ] Hardcoded URLs to unknown domains
- [ ] Base64 encoded strings
- [ ] `$HOME`, `/etc/passwd`, credential paths
- [ ] `chmod`, `chown`, permission changes

### 2. Dependency Verification (for MCP servers)

```bash
# For npm packages
npm info PACKAGE_NAME
npm view PACKAGE_NAME dependencies

# Check package reputation
npm audit PACKAGE_NAME

# For Python packages
pip show PACKAGE_NAME
pip index versions PACKAGE_NAME
```

**Checklist:**
- [ ] Package from official registry (npmjs.com / pypi.org)
- [ ] Recent updates (not abandoned)
- [ ] No typosquatting (e.g., "loadsh" vs "lodash")
- [ ] Reasonable dependency count (<20 for simple tools)
- [ ] Known maintainers

---

## Layer 2: Sandbox Testing (Isolated Environment)

### 3. Docker Sandbox Test

```dockerfile
# Create isolated test environment
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y curl git nodejs npm python3 pip

# Copy skill to test
COPY skill-to-test.md /test/SKILL.md

# Run with limited permissions
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser

# Monitor all file access
CMD ["bash", "-c", "inotifywait -m -r /home/testuser"]
```

**Test Process:**
```bash
# Build sandbox
docker build -t skill-sandbox .

# Run with network isolation
docker run --rm --network=none -v $(pwd)/logs:/logs skill-sandbox

# Check logs for suspicious activity
cat logs/file-access.log
```

### 4. Virtual Machine Test (more secure)

```bash
# macOS: Use UTM or Parallels
# Create snapshot BEFORE testing
# Revert snapshot AFTER testing

# Test steps:
1. Install skill in VM
2. Run skill with various inputs
3. Check:
   - New processes (ps aux)
   - Network connections (netstat -an)
   - File changes (find ~ -mmin -5)
   - Cron jobs (crontab -l)
4. Revert VM to clean state
```

---

## Layer 3: Runtime Monitoring

### 5. Network Traffic Monitoring

```bash
# Install network monitor
brew install wireshark  # macOS

# Or use tcpdump (built-in)
sudo tcpdump -i any -w /tmp/skill-test.pcap

# In another terminal, run the skill
/skill-name "test command"

# Stop tcpdump (Ctrl+C)
# Analyze captured traffic
tcpdump -r /tmp/skill-test.pcap -n | less

# Check for:
# - POST requests with data
# - Connections to unknown IPs
# - DNS queries to suspicious domains
```

**Automated Network Check:**
```bash
#!/bin/bash
# network-monitor.sh

echo "Starting network monitor..."
sudo tcpdump -i any -nn 'tcp or udp' > /tmp/network.log 2>&1 &
TCPDUMP_PID=$!

echo "Running skill..."
# Run your skill here
sleep 5

echo "Stopping monitor..."
sudo kill $TCPDUMP_PID

echo "Analysis:"
grep -E "(POST|PUT|DELETE)" /tmp/network.log
grep -vE "(127.0.0.1|localhost)" /tmp/network.log | grep -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"
```

### 6. File System Monitoring

```bash
# macOS: Use fs_usage
sudo fs_usage -w -f filesystem > /tmp/fs-monitor.log &
FS_PID=$!

# Run skill
/skill-name "test"

# Stop monitoring
sudo kill $FS_PID

# Check for suspicious file access
cat /tmp/fs-monitor.log | grep -E "(\.ssh|\.aws|\.env|password|credential)"
```

**Automated File Monitor:**
```bash
#!/bin/bash
# file-monitor.sh

BEFORE=$(find ~ -type f -newer /tmp/marker 2>/dev/null | wc -l)
touch /tmp/marker

# Run skill
/skill-name "test command"

AFTER=$(find ~ -type f -newer /tmp/marker 2>/dev/null)

echo "New/Modified Files:"
echo "$AFTER"

# Check for suspicious locations
echo "$AFTER" | grep -E "(\/etc|\/usr|\/bin|\.ssh|\.aws)"
```

### 7. Process Monitoring

```bash
# Before running skill
ps aux > /tmp/before.txt

# Run skill
/skill-name "test"

# After running skill
ps aux > /tmp/after.txt

# Compare
diff /tmp/before.txt /tmp/after.txt

# Check for:
# - New background processes
# - Unexpected network connections
# - High CPU/memory usage
```

---

## Layer 4: Behavioral Analysis

### 8. Privilege Escalation Check

```bash
# Check if skill attempts privilege escalation
sudo grep -r "sudo" ~/.claude/skills/SKILLNAME/
sudo grep -r "chmod" ~/.claude/skills/SKILLNAME/
sudo grep -r "chown" ~/.claude/skills/SKILLNAME/

# Monitor sudo attempts
sudo tail -f /var/log/auth.log  # Linux
log show --predicate 'process == "sudo"' --info --last 1h  # macOS
```

### 9. Persistence Check

```bash
# Check if skill installed itself to autostart
launchctl list | grep -i skill  # macOS
crontab -l | grep -i skill
cat ~/.bash_profile ~/.zshrc | grep -i skill
find ~/.config -name "*skill*" -type f
```

### 10. Data Exfiltration Test

```bash
# Use fake credentials
export FAKE_API_KEY="TEST_KEY_DO_NOT_SEND"
export FAKE_SECRET="TEST_SECRET_12345"

# Run skill
/skill-name "test with fake creds"

# Check network logs for fake credentials
grep -r "TEST_KEY_DO_NOT_SEND" /tmp/network.log
grep -r "TEST_SECRET_12345" /tmp/network.log

# If found = MAJOR RED FLAG!
```

---

## Layer 5: Automated Security Scanning

### 11. Use Security Tools

```bash
# For npm packages
npm install -g snyk
snyk test PACKAGE_NAME

# For Python
pip install safety
safety check

# For general code scanning
brew install shellcheck
shellcheck ~/.claude/skills/SKILLNAME/*.sh
```

### 12. Git History Analysis

```bash
# Clone the repo
git clone https://github.com/USER/REPO.git /tmp/skill-repo

# Check commit history for suspicious changes
cd /tmp/skill-repo
git log --all --full-history --oneline

# Check for deleted sensitive commits
git reflog

# Look for large binary files (malware?)
git rev-list --objects --all | git cat-file --batch-check='%(objectsize) %(objectname) %(rest)' | sort -nr | head -20

# Check for credential leaks
git log -p | grep -i -E "(password|api_key|secret|token)"
```

---

## 🧪 Comprehensive Test Script

Here's a ready-to-use test script:

```bash
#!/bin/bash
# skill-security-test.sh
# Comprehensive skill security tester

SKILL_URL="$1"
SKILL_NAME="$(basename $SKILL_URL .md)"
TEST_DIR="/tmp/skill-test-$$"

echo "🔒 Skill Security Tester"
echo "======================="
echo "Testing: $SKILL_URL"
echo ""

# 1. Download skill
echo "[1/10] Downloading skill..."
mkdir -p "$TEST_DIR"
curl -sL "$SKILL_URL" -o "$TEST_DIR/SKILL.md"

# 2. Static analysis
echo "[2/10] Running static analysis..."
DANGEROUS_PATTERNS=(
  "rm -rf"
  "dd if="
  "curl.*-X POST"
  "wget.*--post"
  "eval.*$"
  "exec.*$"
  "/etc/passwd"
  ".ssh/id_rsa"
  "base64 -d"
)

FOUND_ISSUES=0
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if grep -q "$pattern" "$TEST_DIR/SKILL.md"; then
    echo "  ⚠️  Found: $pattern"
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
  fi
done

if [ $FOUND_ISSUES -eq 0 ]; then
  echo "  ✅ No dangerous patterns found"
else
  echo "  ❌ Found $FOUND_ISSUES dangerous patterns!"
fi

# 3. Check for obfuscation
echo "[3/10] Checking for obfuscation..."
if grep -qE "(base64|xxd|rot13|openssl enc)" "$TEST_DIR/SKILL.md"; then
  echo "  ⚠️  Potential obfuscation detected"
else
  echo "  ✅ No obfuscation detected"
fi

# 4. Network activity check
echo "[4/10] Analyzing network calls..."
NETWORK_CALLS=$(grep -oE "https?://[a-zA-Z0-9./?=_-]+" "$TEST_DIR/SKILL.md" | sort -u)
if [ -n "$NETWORK_CALLS" ]; then
  echo "  📡 Found URLs:"
  echo "$NETWORK_CALLS" | sed 's/^/    /'
else
  echo "  ✅ No hardcoded URLs"
fi

# 5. File operations check
echo "[5/10] Checking file operations..."
if grep -qE "(Write|Edit|rm|mv|cp).*/" "$TEST_DIR/SKILL.md"; then
  echo "  ⚠️  File operations detected (review needed)"
else
  echo "  ✅ No direct file operations"
fi

# 6. Credential access check
echo "[6/10] Checking credential access..."
if grep -qE "(\$HOME|process\.env|\.aws|\.ssh|credentials)" "$TEST_DIR/SKILL.md"; then
  echo "  ⚠️  Potential credential access"
else
  echo "  ✅ No credential access"
fi

# 7. Dependencies check
echo "[7/10] Checking dependencies..."
DEPS=$(grep -oE "(pip install|npm install|gem install) [a-zA-Z0-9_-]+" "$TEST_DIR/SKILL.md")
if [ -n "$DEPS" ]; then
  echo "  📦 Dependencies found:"
  echo "$DEPS" | sed 's/^/    /'
else
  echo "  ✅ No external dependencies"
fi

# 8. Privilege check
echo "[8/10] Checking privilege requirements..."
if grep -qE "(sudo|chmod 777|chown)" "$TEST_DIR/SKILL.md"; then
  echo "  ❌ Privilege escalation detected!"
else
  echo "  ✅ No privilege escalation"
fi

# 9. Metadata check
echo "[9/10] Checking metadata..."
if grep -q "^name:" "$TEST_DIR/SKILL.md"; then
  NAME=$(grep "^name:" "$TEST_DIR/SKILL.md" | cut -d: -f2 | tr -d ' ')
  echo "  📝 Skill name: $NAME"
fi
if grep -q "^license:" "$TEST_DIR/SKILL.md"; then
  LICENSE=$(grep "^license:" "$TEST_DIR/SKILL.md" | cut -d: -f2 | tr -d ' ')
  echo "  📜 License: $LICENSE"
fi

# 10. Overall risk score
echo "[10/10] Calculating risk score..."
RISK_SCORE=0

[ $FOUND_ISSUES -gt 0 ] && RISK_SCORE=$((RISK_SCORE + FOUND_ISSUES * 10))
grep -q "base64" "$TEST_DIR/SKILL.md" && RISK_SCORE=$((RISK_SCORE + 25))
grep -q "curl.*POST" "$TEST_DIR/SKILL.md" && RISK_SCORE=$((RISK_SCORE + 20))
grep -q "sudo" "$TEST_DIR/SKILL.md" && RISK_SCORE=$((RISK_SCORE + 30))

echo ""
echo "🎯 RISK SCORE: $RISK_SCORE/100"

if [ $RISK_SCORE -lt 20 ]; then
  echo "🟢 LOW RISK - Generally safe"
elif [ $RISK_SCORE -lt 50 ]; then
  echo "🟡 MEDIUM RISK - Review carefully"
elif [ $RISK_SCORE -lt 75 ]; then
  echo "🟠 HIGH RISK - Use with caution"
else
  echo "🔴 CRITICAL RISK - Do not use!"
fi

# Cleanup
rm -rf "$TEST_DIR"
```

---

## 📋 Complete Testing Checklist

- [ ] **Static Code Analysis** - Manual review + grep patterns
- [ ] **Dependency Verification** - Check npm/pip packages
- [ ] **Sandbox Testing** - Docker or VM isolation
- [ ] **Network Monitoring** - tcpdump during execution
- [ ] **File System Monitoring** - Track all file access
- [ ] **Process Monitoring** - Check for background processes
- [ ] **Privilege Check** - No sudo/chmod/chown
- [ ] **Persistence Check** - No autostart installation
- [ ] **Data Exfiltration Test** - Fake credentials test
- [ ] **Git History Analysis** - Check for malicious commits
- [ ] **Automated Scanning** - shellcheck, snyk, safety
- [ ] **Community Verification** - Check GitHub issues/PRs

---

## 🎯 Risk Minimization Strategy

### Level 1: Paranoid Mode (Maximum Security)
```bash
1. VM snapshot
2. Network isolation
3. Fake credentials
4. Monitor everything
5. Code review every line
6. Revert VM
```

### Level 2: Balanced (Recommended)
```bash
1. Static analysis
2. Dependency check
3. Sandbox test
4. Network monitor
5. File monitor
```

### Level 3: Quick Check (Minimum)
```bash
1. Grep dangerous patterns
2. Check source credibility
3. Read code manually
```

---

## 🚀 Ready-to-Use Test

Would you like me to save the above script? Here's how you'll use it:

```bash
bash skill-security-test.sh https://raw.githubusercontent.com/USER/REPO/SKILL.md
```

It automatically runs all tests and provides a risk score!

Should I create the test script? 🎯
