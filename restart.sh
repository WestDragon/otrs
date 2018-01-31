#!/usr/bin/env bash
/bin/systemctl stop httpd.service
perl /opt/otrs/bin/otrs.SetPermissions.pl --otrs-user=otrs --web-group=apache
su -c "perl /opt/otrs/bin/otrs.Console.pl Maint::Cache::Delete" -s /bin/bash otrs
su -c "perl /opt/otrs/bin/otrs.Console.pl Maint::WebUploadCache::Cleanup" -s /bin/bash otrs
su -c "perl /opt/otrs/bin/otrs.Console.pl Maint::Config::Rebuild" -s /bin/bash otrs
su -c "perl /opt/otrs/bin/otrs.Console.pl  Maint::Config::Sync" -s /bin/bash otrs
/bin/systemctl start httpd.service

/bin/systemctl start crond.service
su -c "perl /opt/otrs/bin/otrs.Daemon.pl start" -s /bin/bash otrs
