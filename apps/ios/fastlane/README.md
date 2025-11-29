fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

Run tests

### ios build_debug

```sh
[bundle exec] fastlane ios build_debug
```

Build for development (local debugging)

### ios staging

```sh
[bundle exec] fastlane ios staging
```

Deploy staging build for internal testing

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Deploy beta build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Deploy to App Store

### ios sync_certs

```sh
[bundle exec] fastlane ios sync_certs
```

Sync code signing certificates and profiles using match

### ios register_devices_from_file

```sh
[bundle exec] fastlane ios register_devices_from_file
```

Register new devices from a file

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Take screenshots for all device sizes

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
