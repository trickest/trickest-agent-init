All notable changes to this project will be documented in this file.

## [v0.1.0] (draft)

### Compatibility
* Fix logger not passing due to, looks like, having same message.
* #1 - Updating 'systemctl show' on `start_and_verify_service` step not to use `--value` option, supports older `systemctl` versions. 