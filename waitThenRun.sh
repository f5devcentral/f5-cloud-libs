#!/bin/bash
# Generated from v2.9.0

while true; do echo waiting for cloud libs install to complete
    if [ -f /config/cloud/cloudLibsReady ]; then
        echo cloud libs installed
        break
    else
        sleep 10
    fi
done
"$@"