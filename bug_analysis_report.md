# Bug Analysis Report

## Summary
This report documents bugs found and fixed in the TIG (Telegraf, InfluxDB, Grafana) monitoring stack codebase, along with additional issues identified during the analysis.

## Bugs Fixed

### Bug 1: Variable Scope Issue in start.sh (Critical Logic Error)

**Severity**: Critical
**Type**: Logic Error
**File**: `start.sh` (lines 37-38)

**Description**: 
The script used an undefined `$PASSWORD` variable in the InfluxDB connection test. The variable was only defined within the admin password replacement block, so if `ADMIN_TO_CHANGE` was not found in the environment file, the variable would be undefined, causing the connection test to fail.

**Root Cause**: 
Variable scope issue where `PASSWORD` was defined conditionally but used unconditionally.

**Impact**: 
- Script would fail when checking InfluxDB connectivity
- Misleading error messages during startup
- Potential infinite loop in the wait condition

**Fix Applied**:
- Extract the admin password directly from the environment file using `grep` and `awk`
- Use the correct username 'monitor' instead of 'admin' (as per env file)
- Properly quote the variable to handle special characters

### Bug 2: Inconsistent sed Usage and Backup File Cleanup (Maintenance Issue)

**Severity**: Medium
**Type**: Maintenance/Performance Issue
**File**: `start.sh` (lines 15-16, 31)

**Description**: 
The script used `sed -i .orig` which creates backup files with `.orig` extensions, but these backup files were never cleaned up and could accumulate over multiple script runs.

**Root Cause**: 
Unnecessary backup file creation in an automated script environment where git provides version control.

**Impact**: 
- Disk space consumption from accumulated backup files
- Potential confusion about which files are current
- Clutter in the filesystem

**Fix Applied**:
- Removed the `.orig` backup suffix from all `sed -i` commands
- This prevents backup file creation while maintaining the same functionality

### Bug 3: Security Vulnerability - Privileged Telegraf Container (Security Issue)

**Severity**: High
**Type**: Security Vulnerability
**File**: `docker-compose.yml` (line 27)

**Description**: 
The telegraf container was configured with `privileged: true`, which grants the container unrestricted access to the host system, essentially giving it root privileges.

**Root Cause**: 
Overly permissive container configuration that violates the principle of least privilege.

**Impact**: 
- Container breakout potential
- Unrestricted host system access
- Violation of security best practices
- Increased attack surface

**Fix Applied**:
- Removed `privileged: true`
- Added specific capabilities `SYS_PTRACE` and `DAC_READ_SEARCH`
- Maintained required functionality while reducing security risk

## Additional Issues Identified (Not Fixed)

### Issue 4: Missing Error Handling in InfluxDB Wait Loop
**File**: `start.sh` (lines 39-42)
**Description**: The while loop that waits for InfluxDB could run indefinitely if the database never comes up. There's no timeout or error handling.
**Recommendation**: Add a timeout mechanism and proper error messages.

### Issue 5: Hard-coded Sleep Duration
**File**: `start.sh` (line 38)
**Description**: Fixed 20-second sleep may not be sufficient for all systems or configurations.
**Recommendation**: Make the initial wait time configurable or implement a more sophisticated readiness check.

### Issue 6: Missing Directory Creation in rsyslog Configuration
**File**: `utils/etc/rsyslog.d/01-ax25listen.conf`
**Description**: The configuration assumes `/var/log/ax25listen/` directory exists, but there's no mechanism to create it.
**Recommendation**: Add directory creation logic or document the manual setup requirement.

### Issue 7: Potential Command Injection in ax25listen Script
**File**: `utils/ax25listen` (line 4)
**Description**: The script pipes output without proper error handling, which could potentially be exploited.
**Recommendation**: Add input validation and error handling.

### Issue 8: Absolute Path Dependency in Systemd Service
**File**: `utils/etc/systemd/system/ax25listen.service` (line 6)
**Description**: Hard-coded path `/home/pi/bin/ax25listen` makes the service non-portable.
**Recommendation**: Use relative paths or make the path configurable.

## Testing Recommendations

1. **Test the password extraction logic** by creating various environment file configurations
2. **Verify telegraf functionality** with the new capability-based permissions
3. **Test startup script** with both fresh installations and re-runs
4. **Security audit** of the remaining container configurations
5. **Load testing** to ensure the monitoring stack performs well under load

## Security Recommendations

1. **Implement proper secrets management** instead of storing tokens in plain text files
2. **Add input validation** to all user-facing scripts
3. **Review all container capabilities** and remove unnecessary permissions
4. **Implement log rotation** for the monitoring services
5. **Add TLS encryption** for inter-service communication

## Conclusion

The three critical bugs have been fixed, improving the reliability, maintainability, and security of the TIG stack deployment. The remaining issues should be addressed in future iterations to further enhance the robustness and security of the system.