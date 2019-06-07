#!/bin/bash
rsync -av ../../src/shared/ raw
rsync -av --exclude "config.lua" ../../src/client/ raw
