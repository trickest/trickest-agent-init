All notable changes to this project will be documented in this file.

## [v0.1.3] (2024-01-09)
### Feature
* Add `debian` support for `rsyslog` installation atempt.

### Compatibility
* Change all `command -v` to `which`.
* Update command for checking processor architecture.

### Fix
* Add warning for ARM64 agent.

## [v0.1.2] (2024-01-04)
### Fix
* Do not exit when service is not detected.

## [v0.1.1] (2023-12-11)
### Feature
* Added ARM64 support.

## [v0.1.0] (2023-12-11)

### Compatibility
* #1 - Updating 'systemctl show' on `start_and_verify_service` step not to use `--value` option, supports older `systemctl` versions. 

### Fix
* Fix logger not passing due to, looks like, having same message.

### Feature
* Automatically detect rsyslog user, and group, use that info to set directory permissions.
* Automatically detect AppArmor, and add rsyslog Trickest patch.