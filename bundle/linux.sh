#!/bin/bash
set -e

echo "Building Linux bundle..."
fyne package -os linux -icon ui/assets/fxcalc_logo.png --id com.tylerkatz.fxcalc --name fxcalc

echo "Done! The application bundle has been created as fxcalc"
