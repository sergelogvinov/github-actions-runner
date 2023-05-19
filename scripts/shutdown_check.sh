#!/bin/bash -e

if [ -f /tmp/shutdown ]; then
    echo "Shutting down..."

    rm -f /tmp/shutdown
fi
