upgrade_civicrm

Bash script to upgrade CiviCRM from the command line, on Drupal sites.

===================
CONFIGURATION

Copy config.sh.dist to config.sh, and then edit config.sh
according to the comments in that file.

===================
USAGE

After configuration is complete, run
bash ./upgrade.sh

===================
RECOVERY

The script recover.sh will attempt to restore your site
to it's pre-upgrade state. This script takes its configuration
settings from config.sh; comments in config.sh indicate
which settings are used for recover.sh, and whether they're
required or optional.

Note the following requirements for recovery.sh:
  * CiviCRM code is handled by git, and has not been
    committed since running upgrade.sh.
  * zcat
  * pv
