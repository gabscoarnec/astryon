#!/bin/sh

set -e

cd $(realpath $(dirname $0)/..)

tools/bin/easyboot -e boot astryon.iso
