#!/bin/bash

set -e

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine "childlogdir"
cd "$PWD/../"
CHILDLOGDIR=`./script/run_with_carton.sh ./script/mediawords_query_config.pl "//supervisor/childlogdir"`
if [[ -z "$CHILDLOGDIR" ]]; then
    echo "\"childlogdir\" is undefined in the configuration."
    exit 1
fi
CHILDLOGDIR="$(cd "$CHILDLOGDIR" && pwd )"

./script/run_with_carton.sh ./script/mediawords_generate_supervisord_conf.pl

# PYTHONHOME might have been set by run_carton.sh to make use of Media Cloud's
# virtualenv under mc-venv. Supervisor doesn't support Python 3, to unset
# PYTHONHOME for Supervisor's Python 2.7 to search for modules at correct
# location.
unset PYTHONHOME

cd "supervisor/"

cd "$PWD/"
/usr/local/bin/supervisord --childlogdir "$CHILDLOGDIR" --configuration "$PWD/supervisord.conf"
