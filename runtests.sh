#!/bin/bash

set -e

PWD=`dirname $0`

bash $PWD/verify-dns.sh
bash $PWD/ping1.sh
bash $PWD/networkPolicy.sh
bash $PWD/webDBSvc.sh
