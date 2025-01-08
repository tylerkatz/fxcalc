#!/bin/bash
set -e

echo "Building macOS bundle..."
fyne package -os darwin -icon ui/assets/fxcalc_logo.png --id com.tylerkatz.fxcalc --name fxcalc

echo "Done! The application bundle has been created as fxcalc.app"
