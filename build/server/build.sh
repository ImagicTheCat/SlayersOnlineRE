#!/bin/bash
rsync -av ../../src/shared/ .
rsync -av --exclude "config.lua" ../../src/server/ .
