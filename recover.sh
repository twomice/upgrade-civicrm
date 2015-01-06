# Full system path to the directory containing this file, with trailing slash.
# This line determines the location of the script even when called from a bash
# prompt in another directory (in which case `pwd` will point to that directory
# instead of the one containing this script).  See http://stackoverflow.com/a/246128
MYDIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"   

# Source config file or exit.
if [ -e ${MYDIR}/config.sh ]; then
  source ${MYDIR}/config.sh
else
  echo "Could not find required config file at ${MYDIR}/config.sh. Exiting."
  exit
fi

# Include functions script.
if [[ -e ${MYDIR}/functions.sh ]]; then
  source ${MYDIR}/functions.sh
else 
  echo "Could not find required functions file at ${MYDIR}/functions.sh. Exiting."
  exit
fi

# Confirm that the config file version matches the code version.
confirm_config_version

# Confirm presense of required settings.
if [[ "${SITEDIR}x" == "x" || "${DRUPAL_SQL_GZ}x" == "x" || "${CIVICRM_SQL_GZ}x" == "x" ]]; then
  echo "Missing required settings in config.sh. Please edit the file and try again. Exiting."
  exit 
fi

# Confirm existence of sql.gz files
FILE_MISSING=0
if [[ ! -e $DRUPAL_SQL_GZ ]]; then
  echo "Could not find DRUPAL_SQL_GZ file: ${DRUPAL_SQL_GZ}"
  FILE_MISSING=1
fi
if [[ ! -e $CIVICRM_SQL_GZ ]]; then
  echo "Could not find CIVICRM_SQL_GZ file: ${CIVICRM_SQL_GZ}"
  FILE_MISSING=1
fi
if [[ "$FILE_MISSING" == "1" ]]; then
  echo "Exiting."
  exit 1
fi

# Determine database names.
DRUPAL_DB=`get_db_name drupal`
CIVICRM_DB=`get_db_name civicrm`
if [[ "${DRUPAL_DB}x" == "x" ]]; then
  DRUPAL_DB=$FALLBACK_DRUPAL_DB_NAME
fi
if [[ "${CIVICRM_DB}x" == "x" ]]; then
  CIVICRM_DB=$FALLBACK_CIVICRM_DB_NAME
fi

if [[ "${DRUPAL_DB}x" == "x" || "${CIVICRM_DB}x" == "x" ]]; then
  echo
  echo "Drupal database: '$DRUPAL_DB'"
  echo "CiviCRM database: '$CIVICRM_DB'"
  echo
  echo "ERROR: Could not determine Drupal or CiviCRM database name."
  echo "This means $0 will probably not work with the current configuration."
  echo "But you can try providing the databese names in config.sh"
  echo "variables FALLBACK_DRUPAL_DB_NAME and FALLBACK_CIVICRM_DB_NAME."
  echo "Exiting."
  exit 1
fi

echo
echo "WARNINGS:"
echo
echo "1. You're about to DROP these two databases"
echo "     Drupal:  '${DRUPAL_DB}'"
echo "     CiviCRM: '${CIVICRM_DB}'"
echo "   and replace them with the contents of these two files"
echo "     Drupal:  ${DRUPAL_SQL_GZ}"
echo "     CiviCRM: ${CIVICRM_SQL_GZ}"
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

# Get sudo privileges.
get_sudo

# Restore civicrm files using git.
echo "Restoring CiviCRM files"
CIVICRM_DIRECTORY=$FALLBACK_CIVICRM_DIRECTORY
if [[ -z $CIVICRM_DIRECTORY || ! -d $CIVICRM_DIRECTORY ]]; then
  echo "ERROR: Cannot determine CiviCRM directory path, or the directory"
  echo "was not found. Please check the value of FALLBACK_CIVICRM_DIRECTORY"
  echo "in config.sh"
  exit 1
fi

CIVICRM_DIRNAME=$(basename $CIVICRM_DIRECTORY)

cd ${CIVICRM_DIRECTORY}
cd ..
git reset HEAD ${CIVICRM_DIRNAME} 
rm -rf ${CIVICRM_DIRNAME}
git checkout -- ${CIVICRM_DIRNAME} 

sudo_rm -rf ${SITEDIR}/files/civicrm/templates_c/*
sudo_rm -rf ${SITEDIR}/files/civicrm/ConfigAndLog/*

# Restore civicrm.settings.php file from preupgrade copy.
cp ${SITEDIR}/civicrm.settings.php{-preupgrade,}

# Run CHMOD_CMD if any.
chmod_files

# Drop existing databases.
echo "Dropping databases"
mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  drop database if exists ${DRUPAL_DB}; 
  create database ${DRUPAL_DB}; 
  drop database if exists ${CIVICRM_DB}; 
  create database ${CIVICRM_DB}
"

# Restore databases from backup.
echo "Restoring databases"
# Get uncompressed size of SQL files.
DRUPAL_SQL_GZ_SIZE=`gzip -l $DRUPAL_SQL_GZ | awk '{ print $2 }' | tail -n1`
CIVICRM_SQL_GZ_SIZE=`gzip -l $CIVICRM_SQL_GZ | awk '{ print $2 }' | tail -n1`

# Piping zcat is usually faster per file than using the unzipped content directly.
zcat ${DRUPAL_SQL_GZ} | pv -er -p -s $DRUPAL_SQL_GZ_SIZE -N "Drupal DB restore" | mysql -u root -p${MYSQL_ROOT_PASSWORD} -D ${DRUPAL_DB}
zcat ${CIVICRM_SQL_GZ} | pv -er -p -s $CIVICRM_SQL_GZ_SIZE -N "CiviCRM DB restore" | mysql -u root -p${MYSQL_ROOT_PASSWORD} -D ${CIVICRM_DB}

