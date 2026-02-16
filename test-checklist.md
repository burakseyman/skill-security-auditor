# Skill Security Test Checklist

## Quick Reference

### Pre-Installation Static Analysis

**Red Flags to Search:**
- [ ] `bash`, `sh -c`, `eval`, `exec`
- [ ] `curl`, `wget`, `fetch` with POST requests
- [ ] `rm -rf`, `dd`, destructive commands
- [ ] Hardcoded URLs to unknown domains
- [ ] Base64 encoded strings
- [ ] `$HOME`, `/etc/passwd`, credential paths
- [ ] `chmod`, `chown`, permission changes
- [ ] Prompt injection: "ignore previous instructions", "do not tell the user"
- [ ] `allowed-tools` requesting Bash + WebFetch together

### Dependency Verification (MCP servers)

- [ ] Package from official registry (npmjs.com / pypi.org)
- [ ] Recent updates (not abandoned)
- [ ] No typosquatting (e.g., "loadsh" vs "lodash")
- [ ] Reasonable dependency count (<20 for simple tools)
- [ ] Known maintainers
- [ ] No suspicious postinstall scripts in package.json

---

## Automated Test Script

Run the companion bash script for automated analysis:

```bash
bash ~/.claude/skills/skill-security-auditor/skill-security-test.sh <URL_OR_FILE>
```

---

## Layer 2: Sandbox Testing

### Docker Sandbox Test

```bash
# Build sandbox
docker build -f ~/.claude/skills/skill-security-auditor/Dockerfile.sandbox -t skill-sandbox .

# Run with network isolation
docker run --rm --network=none -v $(pwd)/test-skill:/skill skill-sandbox

# Check logs for suspicious activity
docker exec <container> cat /home/skilltest/file-access.log
```

### Virtual Machine Test (more secure)

1. Create snapshot BEFORE testing
2. Install skill in VM
3. Run skill with various inputs
4. Check: new processes (`ps aux`), network connections (`netstat -an`), file changes (`find ~ -mmin -5`), cron jobs (`crontab -l`)
5. Revert VM to clean state

---

## Layer 3: Runtime Monitoring

### Network Traffic Monitoring

```bash
# macOS: tcpdump (built-in)
sudo tcpdump -i any -w /tmp/skill-test.pcap

# Run the skill in another terminal, then stop tcpdump
tcpdump -r /tmp/skill-test.pcap -n | less

# Check for POST requests, connections to unknown IPs, DNS queries
```

### File System Monitoring

```bash
# macOS: fs_usage
sudo fs_usage -w -f filesystem > /tmp/fs-monitor.log &

# Run skill, then check
grep -E "(\.ssh|\.aws|\.env|password|credential)" /tmp/fs-monitor.log
```

### Process Monitoring

```bash
# Before and after comparison
ps aux > /tmp/before.txt
# Run skill
ps aux > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

---

## Layer 4: Behavioral Analysis

### Persistence Check

```bash
# Check if skill installed itself to autostart
launchctl list | grep -i skill        # macOS
crontab -l | grep -i skill
cat ~/.bash_profile ~/.zshrc | grep -i skill
```

### Data Exfiltration Test

```bash
# Use fake credentials
export FAKE_API_KEY="TEST_KEY_DO_NOT_SEND"
export FAKE_SECRET="TEST_SECRET_12345"

# Run skill, then check network logs for fake credentials
grep -r "TEST_KEY_DO_NOT_SEND" /tmp/network.log
# If found = MAJOR RED FLAG!
```

---

## Complete Testing Checklist

- [ ] **Static Code Analysis** - Manual review + automated script
- [ ] **Prompt Injection Scan** - Check for override/hide instructions
- [ ] **allowed-tools Review** - Verify tools match stated purpose
- [ ] **Dependency Verification** - Check npm/pip packages
- [ ] **Sandbox Testing** - Docker or VM isolation
- [ ] **Network Monitoring** - tcpdump during execution
- [ ] **File System Monitoring** - Track all file access
- [ ] **Process Monitoring** - Check for background processes
- [ ] **Privilege Check** - No sudo/chmod/chown
- [ ] **Persistence Check** - No autostart installation
- [ ] **Data Exfiltration Test** - Fake credentials test
- [ ] **Git History Analysis** - Check for malicious commits

---

## Risk Minimization Strategy

### Level 1: Quick Check (2 min)
1. Run automated script
2. Check source credibility
3. Read `allowed-tools` field

### Level 2: Balanced (10 min)
1. Automated script + manual code review
2. Dependency check
3. GitHub repo analysis (stars, contributors, issues)

### Level 3: Paranoid Mode (30+ min)
1. Docker sandbox with network isolation
2. Network traffic monitoring
3. File system monitoring
4. Git history analysis
5. Fake credential exfiltration test
