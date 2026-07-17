#!/usr/bin/env bash

# Stable daily-development identity. Do not override these per build: macOS TCC
# and Keychain trust are tied to this app identity.
OBSERVER_DEVELOPMENT_TEAM="4TRT463PSU"
OBSERVER_PRODUCT_BUNDLE_IDENTIFIER="local.observer.dev"
OBSERVER_PRODUCT_NAME="Observer"
OBSERVER_EXECUTABLE_NAME="ObserverApp"
OBSERVER_CODE_SIGN_IDENTITY="Apple Development"
OBSERVER_INSTALL_PATH="/Applications/Observer.app"
OBSERVER_ENTITLEMENTS_RELATIVE_PATH="config/Observer.entitlements"

