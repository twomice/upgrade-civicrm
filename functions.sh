# Functions for use in upgrade.sh


# Compare two version strings using a given 
# comparison operator.
#
# parameter: VERSION1: a dot-delimited 
#  CiviCRM version string. E.g., 3.1.2, 4.2.19
# parameter: OP: Any one of the following comparison
#   operators:
#     =   (equal to)
#     ==  (equal to)
#     >   (greater than)
#     >=  (greater than or equal to)
#     <   (less than)
#     <=  (less than or equal to)
# parameter: VERSION2: another dot-delimited
#  CiviCRM version string. 
#
# exit code: 0 if the expression "$VERSION1 $OP $VERSION2" 
#   is true; otherwise 1.
#
# Based on code found at http://stackoverflow.com/a/4025065.
version_compare() {
  # Comparison result.
  RESULT=""

  # Prepare to split on dots.
  local IFS=.

  # Initialize local variables.
  local i VERSION1=($1) OP=($2) VERSION2=($3)

#echo "==="
#echo "1: $1"
#echo "2: $2"
#echo "3: $3"
#echo "version1: $VERSION1"
#echo "version2: $VERSION2"
#echo "op: $OP"

  # If versions are identical, return 1.
  if [[ $1 == $3 ]]; then
    RESULT=1
  else
  

    # Loop through parts in version1 and fill 
    # empty trailing fields with zeros, so that
    # VERSION1 and VERSION2 have the same number
    # of fields.
    for ((i=${#VERSION1[@]}; i<${#VERSION2[@]}; i++)); do
      VERSION1[i]=0
    done
  
    # Loop through parts in version1.
    for ((i=0; i<${#VERSION1[@]}; i++)); do
      # Fill empty fields in version2 with zeros.
      if [[ -z ${VERSION2[i]} ]]; then
        VERSION2[i]=0
      fi
#echo "v1 part $i: ${VERSION1[i]}"
#echo "v2 part $i: ${VERSION2[i]}"

      # If the version1 part is greater than its corresponding
      # version2 part, return 2.
      if [[ 10#${VERSION1[i]} -gt 10#${VERSION2[i]} ]]; then
        RESULT=2
        break;
      # If the version1 part is less than its corresponding
      # version2 part, return 0.
      elif [[ 10#${VERSION1[i]} -lt 10#${VERSION2[i]} ]]; then
        RESULT=0
        break;
      fi
    done
    # If we're still here, the versions are effectively
    # equivalent, though not literally identical (e.g.,
    # 1.1.1 and 1.01.1). Return 1.
    if [[ -z $RESULT ]]; then
      RESULT=1
    fi
  fi
#echo "args: $1 $2 $3; result: $RESULT"
#echo "vars: $VERSION1 $OP $VERSION2; result: $RESULT"
#echo "result: $RESULT; op: $OP"

  case $OP in
    '='|'==') 
      if [[ "$RESULT" == "1" ]]; then
        return 0
      else
        return 1
      fi
      ;;
    '>') 
      if [[ "$RESULT" == "2" ]]; then
        return 0
      else
        return 1
      fi
      ;;
    '<') 
      if [[ "$RESULT" == "0" ]]; then
        return 0
      else
        return 1
      fi
      ;;
    '<=') 
      if [[ "$RESULT" -le "1" ]]; then
        return 0
      else
        return 1
      fi
      ;;
    '>=') 
      if [[ "$RESULT" -ge "1" ]]; then
        return 0
      else
        return 1
      fi
      ;;
  esac
}

# Upgrade CiviCRM to the given version.
#
# PARAMETER: VERSION: A three-part dot-delimited
#   CiviCRM version string.
do_upgrade() {
  UPGRADE_VERSION=$1

  if [[ "${UPGRADE_VERSION}x" == "x" ]]; then
    echo "Missing required VERSION"
    echo "Usage: do_upgrade VERSION"
    echo "  VERSION: CiviCRM version to upgrade to."
    return 1
  fi

  echo "Upgrading to ${UPGRADE_VERSION}"


  mkdir -p ${MYDIR}/downloads
  EXTRACT_DIRECTORY=$(mktemp -d $MYDIR/downloads/extract_XXX)

  echo "Fetching source for ${UPGRADE_VERSION}"
  download_and_extract_tarball $UPGRADE_VERSION $EXTRACT_DIRECTORY

  echo "Replacing CiviCRM with source for ${UPGRADE_VERSION}"
  echo "rm -rf $CIVICRM_DIRECTORY"
  rm -rf $CIVICRM_DIRECTORY
  mv $EXTRACT_DIRECTORY/civicrm $CIVICRM_DIRECTORY
  cd $MYDIR
  echo "ls $CIVICRM_DIRECTORY"
  ls $CIVICRM_DIRECTORY
  rm -rf $EXTRACT_DIRECTORY
   
  # Drush upgrade is broken in 4.2 for Drupal 6, so if we're upgrading to
  # 4.2.x on Drupal 6, replace 4.2 drush file with one from 4.3
  if [[ "$DRUPAL_VERSION" == "6" ]]; then
    if version_compare $UPGRADE_VERSION ">=" "4.2.0" && version_compare $UPGRADE_VERSION "<" "4.3.0"; then
      echo "Copying civicrm.drush.inc from 4.3.9 (because it's broken in 4.2)."
      cp ${MYDIR}/civicrm.drush.inc-4.3.9 ${CIVICRM_DIRECTORY}/drupal/drush/civicrm.drush.inc
    fi
  fi

  echo "Calling drush -y civicrm-upgrade-db, to upgrade to ${UPGRADE_VERSION}..."
  smart_drush -y civicrm-upgrade-db
  RESULT=$?
  if [[ "$RESULT" != "0" ]]; then
    echo
    echo 'ERROR: The command `drush -y civicrm-upgrade-db` failed.' 
    echo 'Please visit [site-url]/civicrm/upgrade?reset=1'
    echo 'and perform the upgrade manually.'
    echo -n 'Strike enter to continue when the in-browser upgrade is complete ...'
    read CONTINUE
  fi 
} 

# Run the command defined in CHMOD_CMD in config.sh, if any.
chmod_files() {
  if [ "${CHMOD_CMD}x" != "x" ]; then
    $CHMOD_CMD
  fi
}

# Use Drush to get the database name for Drupal or CiviCRM,
# as indicated by $TYPE
#
# Parameter: $TYPE Either (case-insensitive) 'drupal' or 'civicrm'
print_db_name() {
  TYPE=`echo $1 | tr '[:upper:]' '[:lower:]'`
  case $TYPE in
    'drupal')
      smart_drush status | grep "Database name" | awk '{ print $NF }' 
    ;;
    'civicrm')
      smart_drush ev 'civicrm_initialize(); echo CRM_Core_DAO::singleValueQuery("select database()"); '
    ;;
  esac
}

# Determine whether the given drush command exists
drush_command_exists() {
  DRUSH_COMMAND=$1
  if [[ "${DRUSH_COMMAND}x" == "x" ]]; then
    echo "Missing required DRUSH_COMMAND"
    echo "Usage: drush_command_exists DRUSH_COMMAND"
    echo "  DRUSH_COMMAND: Drush command to test for"
    return 1
  fi

  smart_drush help $DRUSH_COMMAND > /dev/null 2>&1
  RETURN=$?
  return $RETURN
}

# Get the current major Drupal version (e.g., 6, 7, 8)
print_drupal_version() {
  smart_drush status | grep "Drupal version" | awk '{ print $NF }' | awk -F '.' '{ print $1 }'
}

# Get the current CiviCRM version 
print_civicrm_version() {
  smart_drush ev "civicrm_initialize(); require_once('CRM/Utils/System.php'); echo CRM_Utils_System::version();" 
}

# Recursively remove a given file or directory, using sudo only if necessary.
sudo_rm() {
  # Check for unwritable files; if found, we'll use sudo to remove them
  RM=$1
  if [[ -e $RM ]]; then
    FOUND=$(find $RM ! -writable 2>/dev/null | wc -l); 
    if [[ "$FOUND" > "0" ]]; then 
      sudo rm -rf $RM
    else
      rm -rf $RM
    fi
  fi
}

function print_civicrm_directory() {
  FILENAME=$(smart_drush sqlq "select filename from system where name='civicrm'" | tail -n 1)
  echo $(print_drush_status_value "Drupal root")/$(dirname $(dirname $FILENAME))
}

print_drush_status_value() {
  # Ensure sufficient arguments.
  if [ "$#" -ne 1 ]; then
    echo "ERROR: Missing required arguments for $FUNCNAME"
    echo "Usage: $FUNCNAME DRUSH_STATUS_LABEL"
    echo "  DRUSH_STATUS_LABEL: Full case-sensitive label from the desired"
    echo '    `drush status` line'
    exit 1
  fi

  LABEL=$1

  # Set $COLUMNS value to something large. We need this because drush will wrap
  # based on this value, and if it's too small (e.g., when calling directly over
  # ssh without an interactive terminal) that can break our grep|awk magic.
  ORIGINAL_COLUMNS_VALUE=$COLUMNS
  export COLUMNS=300

  smart_drush status | grep -P "${LABEL}\s*:" | awk '{ print $NF }'

  # Return $COLUMNS to its original value.
  export COLUMNS=$ORIGINAL_COLUMNS_VALUE
}

smart_drush() {
  pushd $SITEDIR > /dev/null
  drush "$@"
  return $?
  popd > /dev/null
}


download_and_extract_tarball() {
  UPGRADE_VERSION=$1
  EXTRACT_DIRECTORY=$2

  if [[ "$#" != "2" ]]; then
    echo "ERROR: Missing required arguments"
    echo "Usage: $FUNCNAME UPGRADE_VERSION EXTRACT_DIRECTORY"
    return 1
  fi

  MAX_DOWNLOAD_ATTEMPTS=2
  DOWNLOAD_ATTEMPTS=0
  DOWNLOAD_SUCCESSFUL=0
  
  if [[ "$DRUPAL_VERSION" == "6" ]]; then
    DRUPAL_6_STRING="6"
  else
    DRUPAL_6_STRING=""
  fi

  TARBALL="civicrm-${UPGRADE_VERSION}-drupal${DRUPAL_6_STRING}.tar.gz"

  while [[ "$DOWNLOAD_ATTEMPTS" < "$MAX_DOWNLOAD_ATTEMPTS" && "$DOWNLOAD_SUCCESSFUL" == "0" ]]; do
    cd ${MYDIR}/downloads
    wget -nc http://sourceforge.net/projects/civicrm/files/civicrm-stable/${UPGRADE_VERSION}/${TARBALL}/download -O ${TARBALL}
    # Increment DOWNLOAD_ATTEMPTS counter.
    DOWNLOAD_ATTEMPTS=$((DOWNLOAD_ATTEMPTS+1))

    cp ${TARBALL} $EXTRACT_DIRECTORY
    cd $EXTRACT_DIRECTORY
    echo "In $EXTRACT_DIRECTORY: tar xfz ${TARBALL}"
    tar xfz ${TARBALL}
    RESULT=$?
    if [[ "$RESULT" == "0" ]]; then
      DOWNLOAD_SUCCESSFUL=1
    else
      rm -f ${MYDIR}/downloads/${TARBALL}
    fi
  done
  if [[ "$DOWNLOAD_SUCCESSFUL" == "0" ]]; then
    echo "ERROR: Tarball ${TARBALL} could not download successfully"
    echo "after ${DOWNLOAD_ATTEMPTS} attempts. Exiting."
    exit 1
  fi
}

# Confirm that the config file version matches the code version.
confirm_config_version() {
  CODE_VERSION=2
  if [[ "$CONFIG_VERSION" != "$CODE_VERSION" ]]; then
    echo "ERROR: The variable CONFIG_VERSION is either missing"
    echo "from config.sh or is set to the wrong value. The"
    echo "correct value for this codebase is ${CODE_VERSION}."
    echo "HINT: If you've recently upgraded these scripts,"
    echo "you'll want to consult config.sh.dist for the latest"
    echo "configuration options."
    exit 1
  fi
}

get_sudo() {
  echo "Depending on your system configuration, this script may require"
  echo "sudo access. Would you like to prompt for sudo access now? [yes or no]"
  read GET_SUDO
  case $GET_SUDO in
    [yY] | [yY][Ee][Ss] )
      echo "Securing sudo privileges..."
      sudo echo "Thank you."
      ;;
    *)
      echo "You may be prompted for sudo access later in this script."
      ;;
  esac
}
