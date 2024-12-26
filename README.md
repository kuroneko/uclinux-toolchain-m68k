# uclinux toolchain for m68k/coldfire.

This is based on the old 20160818 build tools for m68k.

Patches are included to fix build issues on modern Linux environments.

This toolchain is not yet heavily tested with the current build config, so use
at your own risk.

## Building

The contrainer runtime needs network access to build this dockerfile still -
there's some live downloading of sources which was present in the original
build process that haven't been removed/supressed yet.

## Config / usage

Binarys inside the image are inside `/opt/m68k-uclinux-tools`

It's recommended you use a bind mount volume to bring your workspace/sources into
the container, and simply run the toolchain from within the container against 
your bindmounted sources.


