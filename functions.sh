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
#echo
#echo "v1 part $i: ${VERSION1[i]}"
#echo "v2 part $i: ${VERSION2[i]}"

      # If the version1 part is greater than its corresponding
      # version2 part, return 0.
      if ((10#${VERSION1[i]} > 10#${VERSION2[i]})); then
        RESULT=2
        break;
      # If the version1 part is less than its corresponding
      # version2 part, return 1.
      elif ((10#${VERSION1[i]} < 10#${VERSION2[i]})); then
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
#echo "args: $1 $2 $3: $RESULT"
#echo "vars: $VERSION1 $OP $VERSION2: $RESULT"
#echo "result: $RESULT; op $OP"

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
  
  TARBALL="civicrm-${UPGRADE_VERSION}-drupal6.tar.gz"
  
  echo "Fetching source for ${UPGRADE_VERSION}"
  pushd ${CONFIGDIR}
  wget -nc http://sourceforge.net/projects/civicrm/files/civicrm-stable/${UPGRADE_VERSION}/${TARBALL}/download -O ${TARBALL}
  cp ${TARBALL} ${SITEDIR}/sites/all/modules/.
  echo "cp ${TARBALL} ${SITEDIR}/sites/all/modules/."
  ls -al ${SITEDIR}/sites/all/modules/${TARBALL}
  
  echo "Replacing CiviCRM with source for ${UPGRADE_VERSION}"
  pushd $MODULEDIR
  rm -rf civicrm
  echo "tar xfz ${TARBALL}" 
  tar xfz ${TARBALL}
  rm ${TARBALL}
      
  # Drush upgrade is broken in 4.2, so if we're upgrading to
  # 4.2.x, replace 4.2 drush file with one from 4.3
  if version_compare $UPGRADE_VERSION ">=" "4.2.0" && version_compare $UPGRADE_VERSION "<" "4.3.0"; then
    echo "Copying civicrm.drush.inc from 4.3.9 (because it's broken in 4.2)."
    cp ${CONFIGDIR}/civicrm.drush.inc-4.3.9 ${SITEDIR}/sites/all/modules/civicrm/drupal/drush/civicrm.drush.inc
  fi

  pushd $SITEDIR

  echo "Calling drush -y civicrm-upgrade-db, to upgrade to ${UPGRADE_VERSION}..."
  drush -y civicrm-upgrade-db
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
get_db_name() {
  TYPE=`echo $1 | tr '[:upper:]' '[:lower:]'`
  case $TYPE in
    'drupal')
      DRUSH_CMD='sql-connect'
    ;;
    'civicrm')
      DRUSH_CMD='civicrm-sql-connect'
    ;;
  esac
  cd $SITEDIR
  for i in $(drush $DRUSH_CMD); do echo $i | grep '\--database=' | awk -F '=' '{ print $2 }'; done;
}
