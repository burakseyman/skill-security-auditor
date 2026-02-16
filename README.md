# Skill Security Auditor v2.0

Comprehensive security testing suite for Claude Skills and MCP servers.

## Files

| File | Description |
|------|-------------|
| `SKILL.md` | Main skill definition (for Claude Code) |
| `skill-security-test.sh` | Automated security test script |
| `test-checklist.md` | Manual test checklist |
| `Dockerfile.sandbox` | Isolated test environment (Docker) |
| `reports/` | Auto-generated test reports |
| `LICENSE` | MIT License |

## Quick Start

### From Within Claude Code

```bash
/skill-security-auditor
# Then provide a URL, file path, or paste code
```

### Automated Test Script

```bash
# Run directly
bash ~/.claude/skills/skill-security-auditor/skill-security-test.sh <URL_OR_FILE>

# Create alias (optional)
echo 'alias skill-test="bash ~/.claude/skills/skill-security-auditor/skill-security-test.sh"' >> ~/.zshrc
source ~/.zshrc

# Usage
skill-test https://raw.githubusercontent.com/USER/REPO/SKILL.md
skill-test ~/Downloads/suspicious-skill.md
```

## Risk Scores

| Score | Level | Recommendation |
|-------|-------|----------------|
| 0-20 | LOW | Safe to use |
| 21-50 | MEDIUM | Review carefully, test in sandbox |
| 51-75 | HIGH | Expert review required |
| 76-100 | CRITICAL | DO NOT USE |

## What v2.0 Checks

- **Pattern detection**: Dangerous commands, destructive operations, credential access
- **Prompt injection**: Override instructions, hidden actions, social engineering
- **allowed-tools analysis**: Tool risk levels, dangerous combinations (Read+WebFetch, Bash+WebFetch)
- **Supply chain**: postinstall scripts, typosquatting, dependency confusion
- **MCP-specific**: SSRF, path traversal, excessive OAuth scope, env var leakage
- **Source verification**: GitHub repo analysis via `gh` CLI (stars, contributors, issues, maintenance)
- **Positive signals**: Risk reducers for trusted sources, open source, active maintenance
- **Context-aware**: Distinguishes documentation examples from actual threats

## Changelog

### v2.0.0 (2026-02-16)
- Added `allowed-tools` to SKILL.md (Read, Glob, Grep, Bash, WebFetch)
- Added Claude Code skill architecture knowledge
- Added prompt injection detection (10 patterns)
- Added allowed-tools risk matrix with tool combination analysis
- Added supply chain attack detection (postinstall, typosquatting, dependency confusion)
- Added MCP-specific attack vectors (SSRF, path traversal, OAuth scope, env leakage)
- Added context-aware analysis to reduce false positives
- Added risk reducers (positive security signals)
- Added two-tier output format (concise default, detailed for high risk)
- Added GitHub repo analysis via `gh` CLI with expanded trusted organizations
- Fixed subshell variable scoping bug in bash script
- Added input validation and curl timeout to bash script
- Added prompt injection scanning to bash script (step 11/13)
- Added report rotation (keeps last 50)
- Removed self-triggering example commands from SKILL.md
- Updated Dockerfile to Ubuntu 24.04 with shellcheck/jq
- Cleaned up test-checklist.md (removed duplicated script, halved length)
- Added LICENSE file

### v1.0.0 (2026-02-09)
- Initial release

## Known Limitations

- Static analysis cannot catch all attack vectors; runtime monitoring complements it
- Context-aware analysis may have false negatives for sophisticated obfuscation
- Risk scores are heuristic, not definitive -- always combine with manual review
- GitHub repo analysis requires `gh` CLI to be installed and authenticated
- The bash script performs text-level pattern matching, not semantic analysis

## License

MIT
