#!/bin/sh

cd $(realpath $(dirname $0)/..)

qemu-system-x86_64 -cdrom astryon.iso -serial stdio -enable-kvm $@
