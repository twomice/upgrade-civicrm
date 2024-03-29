#!/bin/bash

# run in tmux, screen, or similar.

# Full system path to the directory containing this file, with trailing slash.
# This line determines the location of the script even when called from a bash
# prompt in another directory (in which case `pwd` will point to that directory
# instead of the one containing this script).  See http://stackoverflow.com/a/246128
MYDIR="$( cd -P "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )/"

# Source config file or exit.
if [ -e ${MYDIR}/config.sh ]; then
  source ${MYDIR}/config.sh
else
  echo "Could not find required config file at ${MYDIR}/config.sh. Exiting."
  exit 1
fi

if [[ "${TARGET_VERSION}x" == "x" || "${SITEDIR}x" == "x" ]]; then
  echo "Missing required settings in config.sh. Please edit the file and try again. Exiting."
  exit 1
fi

# Ensure SITEDIR exists and contains civicrm.settings.php.
if [[ ! -e "$SITEDIR/civicrm.settings.php" ]]; then
  echo "Directory $SITEDIR does not contain civicrm.settings.php. "
  echo "  Please make the correction in config.sh and try again. Exiting."
  exit 1
fi

# Strip civicrm from CIVICRM_MODULES, just in case.
CIVICRM_MODULES=$(echo $CIVICRM_MODULES | sed -e 's/\bcivicrm\b,*//g');

# Include functions script.
if [[ -e ${MYDIR}/functions.sh ]]; then
  source ${MYDIR}/functions.sh
else 
  echo "Could not find required functions file at ${MYDIR}/functions.sh. Exiting."
  exit 1
fi

# Confirm that the config file version matches the code version.
confirm_config_version

# Drush upgrade to 4.1.0 is broken, so refuse to handle it.
if version_compare $TARGET_VERSION "=" "4.1.0"; then
  echo "This script cannot upgrade to 4.1.0."
  echo "Please upgrade manually, or change TARGET_VERSION to something else."
  echo "Exiting."
  exit 1
fi

DRUPAL_DB=`print_db_name drupal`
CIVICRM_DB=`print_db_name civicrm`

if [[ "${DRUPAL_DB}x" == "x" || "${CIVICRM_DB}x" == "x" ]]; then
  echo
  echo "Drupal database: '$DRUPAL_DB'"
  echo "CiviCRM database: '$CIVICRM_DB'"
  echo
  echo "ERROR: Could not determine Drupal or CiviCRM database name."
  echo "Exiting."
  exit 1
fi

echo
echo "WARNINGS:"
echo
echo "1. You're about to upgrade CiviCRM"
echo "   to version $TARGET_VERSION"
echo "   in the site at $SITEDIR"
echo "   which uses the Drupal database '$DRUPAL_DB'"
echo "   and the CiviCRM database '$CIVICRM_DB'"
echo
echo "2. This script can run long; it's recommended to run it"
echo "   in tmux or screen, to prevent problems in case of a"
echo "   dropped connection."
echo
echo "3. You MUST backup files and databsases before continuing."
echo
echo "Do you understand the above warnings and wish to continue? [yes or no]"
read CONTINUE
case $CONTINUE in
  [yY] | [yY][Ee][Ss] )
    echo "Continuing with upgrade."
    ;;
  [nN] | [nN][Oo] )
    echo "Exiting.";
    exit 1
    ;;
   *) echo "Invalid input. Please enter 'yes' or 'no'."
    exit 1
    ;;
esac

get_sudo

# Run CHMOD_CMD if any.
chmod_files

# Determine current CiviCRM version.
CURRENT_VERSION=$(print_civicrm_version)

echo "CURRENT_VERSION: $CURRENT_VERSION"
echo "TARGET_VERSION: $TARGET_VERSION"
if ! version_compare $TARGET_VERSION ">" $CURRENT_VERSION ; then
  echo "Target version ${TARGET_VERSION} is not greater than current version ${CURRENT_VERSION}. Nothing to upgrade. Exiting."
  exit;
fi

echo "Backing up civicrm.settings.php to civicrm.settings.php-preupgrade"
perms=$(stat -c '%a' ${SITEDIR});
chmod a+w ${SITEDIR}
cp -pf ${SITEDIR}/civicrm.settings.php{,-preupgrade}
chmod $perms ${SITEDIR}

# Store durable values so we only have to check them once.
DRUPAL_VERSION=$(print_drupal_version)
CIVICRM_DIRECTORY=$(print_civicrm_directory)

echo "======================"
echo "Begin CiviCRM upgrade to ${TARGET_VERSION}"
echo "Disabling CiviCRM-related modules."
smart_drush dis -y $CIVICRM_MODULES 

# Interim upgrade at 4.1.1 required when starting at lower versions.
INTERIM_VERSION="4.1.1"
if version_compare $INTERIM_VERSION ">" $CURRENT_VERSION && version_compare $TARGET_VERSION ">=" $INTERIM_VERSION; then 
  echo "Current version ${CURRENT_VERSION} is below $INTERIM_VERSION. Initiating interim upgrade to $INTERIM_VERSION, on the way to ${TARGET_VERSION}."

  if [[ "$DRUPAL_VERSION" == "6" ]]; then
    echo "Modifying civicrm.settings.php to match ${INTERIM_VERSION}"
    sed -i "s/'Drupal'/'Drupal6'/g" ${SITEDIR}/civicrm.settings.php
  fi

  do_upgrade $INTERIM_VERSION 
  INTERIM_VERSION_DONE=$INTERIM_VERSION
fi

# Interim upgrade at 4.2.1 required when starting at lower versions.
INTERIM_VERSION="4.2.1"
if version_compare $INTERIM_VERSION ">" $CURRENT_VERSION && version_compare $TARGET_VERSION ">=" $INTERIM_VERSION; then 
  echo "Current version ${CURRENT_VERSION} is below $INTERIM_VERSION. Initiating interim upgrade to $INTERIM_VERSION, on the way to ${TARGET_VERSION}."
  
  # Rectify any blank label values.
  # Reference: http://forum.civicrm.org/index.php/topic,32664.msg139364.html#msg139364
  echo "Fixing empty price option labels"
  smart_drush ev "civicrm_initialize(); CRM_Core_DAO::executeQuery(\"UPDATE civicrm_option_value set label = 'Unknown' WHERE label = ''\");"

  echo "Modifying civicrm.settings.php to match ${INTERIM_VERSION}"
  echo "require_once 'CRM/Core/ClassLoader.php';" >> ${SITEDIR}/civicrm.settings.php;
  echo "CRM_Core_ClassLoader::singleton()->register();" >> ${SITEDIR}/civicrm.settings.php

  do_upgrade $INTERIM_VERSION 
  INTERIM_VERSION_DONE=$INTERIM_VERSION
fi

# Now that all interim versions have been upgraded, 
# if TARGET_VERSION is greater than the highest
# completed interim version, or if we never needed 
# an interim version, upgrade to actual TARGET_VERSION.
if [ -z "$INTERIM_VERSION_DONE" ] || version_compare $INTERIM_VERSION_DONE "<" $TARGET_VERSION; then 
  do_upgrade $TARGET_VERSION
fi

echo "smart_drush cc -y all"
smart_drush cc -y all

echo "Clear CiviCRM templates and ConfigAndLog files"
sudo_rm ${SITEDIR}/files/civicrm/templates_c
sudo_rm ${SITEDIR}/files/civicrm/ConfigAndLog

# Re-enable any disabled modules.
echo "Re-enabling CiviCRM-related modules"
smart_drush en -y $CIVICRM_MODULES

# Clear cache; this is sometimes helpful before reverting features.
echo "smart_drush cc all"
smart_drush cc all

# Revert features. Required when $CIVICRM_MODULES included any Features.
if drush_command_exists 'features-revert-all'; then
  echo "Revert all features"
  smart_drush -y features-revert-all
fi

# Clear cache again. FIXME: is this necessary?
echo "smart_drush cc all"
smart_drush cc all

# Run CHMOD_CMD if any.
chmod_files

echo "Done."
echo "NOTE: If you've successfully run this upgrade in a git repo,"
echo "observe that it has changed many CiviCRM files, but has"
echo "not committed them to git. Please take steps to commit"
echo "those changes to git."

