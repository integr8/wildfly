#!/bin/bash
. /usr/local/bin/utils.sh
set_management_user && start_application_server_admin_only && wait_for_server
###############################################################

update_max_post_size 150000000

################################################################
kill_application_server

start_application_server && wait_for_server && wait