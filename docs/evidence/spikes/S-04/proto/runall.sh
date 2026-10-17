#!/bin/zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname $0)"
./.build/release/s04 harness $PWD/work 20 > run-1.20.0.txt 2>&1
S04_CHECKPOINTS=1 ./.build/release/s04 harness $PWD/work 20 alt-overflow > run-1.20.0-ckpt-alt-overflow.txt 2>&1
./.build199/release/s04 harness $PWD/work 20 > run-1.99.0.txt 2>&1
S04_CHECKPOINTS=1 ./.build199/release/s04 harness $PWD/work 20 alt-overflow > run-1.99.0-ckpt-alt-overflow.txt 2>&1
echo finished > run-done.txt
