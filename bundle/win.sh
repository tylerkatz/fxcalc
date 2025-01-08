#!/bin/bash
set -e

echo "Building Windows bundle..."
fyne package -os windows -icon ui/assets/fxcalc_logo.png --id com.tylerkatz.fxcalc --name fxcalc

echo "Done! The application bundle has been created as fxcalc.exe"
