#! /bin/sh

# This script is inspired by and derived from https://www.debian.org/mirror/anonftpsync
# & https://github.com/ZJU-NewMirrors/OldMirrorsScripts/blob/master/bin/simplersync.
# Note: You MUST have rsync 2.6.4 or newer, which is available in sarge.
#
# Copyright (C) 2016 Stawidy <duyizhaozj321@yahoo.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; version 2.
#
# This script is designed for CQUPT Mirror, might not be very generic.

set -e

VERSION="1.0.0"

# Get the name of a mirror
if [[ $1 = repo:* ]]; then
	REPO=${1##repo:}
else
	echo "Usage: $0 repo:{REPONAME}"
	exit 1
fi

# Load the configure file for a mirror
. "$(dirname "$0")/../etc/${REPO}.conf"

# TO is the destination for the base of the mirror directory
# (the dir that holds dists/ and ls-lR).
# (mandatory)
TO="/data/mirror/${MIRROR}";

# Set up the home directory of mirror
HOME="/data";

# Set up url of upstream
RSYNC_HOST="${UPSTREAM_URL}";

# Set up the directory name of upstream
RSYNC_DIR="${MIRROR}";

# Set up the log directory
LOGDIR="/data/log";

# Get the data of system
LOCAL_DATE=$(date '+%Y-%m-%d');

# MAILTO is the address to send logfiles to;
# if it is not defined, no mail will be sent
# (optional)
MAILTO="cqupt-mirror@googlegroups.com";

# LOCK_TIMEOUT is a timeout in minutes.  Defaults to 360 (6 hours).
# This program creates a lock to ensure that only one copy
# of it is mirroring any one archive at any one time.
# Locks held for longer than the timeout are broken, unless
# a running rsync process appears to be connected to $RSYNC_HOST.
LOCK_TIMEOUT="360";

# Note: on some non-Debian systems, hostname doesn't accept -f option.
# If that's the case on your system, make sure hostname prints the full
# hostname, and remove the -f option. If there's no hostname command,
# explicitly replace `hostname -f` with the hostname.

# The hostname must match the "Site" field written in the list of mirrors.
# If hostname doesn't returns the correct value, fill and uncomment below
# HOSTNAME=mirror.domain.tld
HOSTNAME="mirrors.cqupt.edu.cn";

# Set up the logfile for the mirror sync script
LOGFILE="$LOGDIR/$MIRROR-mirror-$LOCAL_DATE.log";

# The temp directory used by rsync --delay-updates is not
# world-readable remotely. It must be excluded to avoid errors.
LOCK="${TO}/${MIRROR}-Archive-Update-in-Progress-${HOSTNAME}";

TMP_EXCLUDE="--exclude .~tmp~/";

# Check for some environment variables
if [ -z "$TO" ] || [ -z "$RSYNC_HOST" ] || [ -z "$RSYNC_DIR" ] || [ -z "$LOGDIR" ]; then
	echo "One of the following variables seems to be empty:"
	echo "TO, RSYNC_HOST, RSYNC_DIR or LOGDIR"
	exit 2
fi

# Exclude targets defined in $TARGET_EXC
for EXC in $TARGET_EXC; do
	EXCLUDE=$EXCLUDE"\
		--exclude $EXC "
done

cd $HOME

# Get in the right directory and set the umask to be group writable
umask 002

# Check to see if another sync is in progress
if [ -f "$LOCK" ]; then
# Note: this requires the findutils find; for other finds, adjust as necessary
  if [ "`find $LOCK -maxdepth 1 -cmin -$LOCK_TIMEOUT`" = "" ]; then
# Note: this requires the procps ps; for other ps', adjust as necessary
    if ps ax | grep '[r]'sync | grep -q $RSYNC_HOST; then
      echo "stale lock found, but a rsync is still running, aiee!"
      exit 1
    else
      echo "stale lock found (not accessed in the last $LOCK_TIMEOUT minutes), forcing update!"
      rm -f $LOCK
    fi
  else
    echo "current lock file exists, unable to start rsync!"
    exit 1
  fi
fi

touch $LOCK

# Note: on some non-Debian systems, trap doesn't accept "exit" as signal
# specification. If that's the case on your system, try using "0".
trap "rm -f $LOCK" exit
trap '' 2

set +e

date +['Start '%F' '%T] >> $LOGFILE

# Now start sync
rsync --recursive --links --hard-links --times \
	    --verbose \
	    --delay-updates \
	    --delete-after \
	    --timeout=3600 \
        --delete-excluded \
        --force \
	    --exclude "$MIRROR-Archive-Update-in-Progress-${HOSTNAME}" \
	    $TMP_EXCLUDE $EXCLUDE \
	    "$RSYNC_HOST/$RSYNC_DIR/" "$TO/" >> $LOGFILE 2>&1
result=$?

if [ "$result" = 0 ]
then
	date +['Succeed '%F' '%T] >> $LOGFILE
else
	echo "ERROR: Help, something weird happened" >> $LOGFILE
	echo "mirroring exited with exitcode $result" >> $LOGFILE
	date +['Failed '%F' '%T] >> $LOGFILE
fi

# It will work if you set up mutt client correctly
if [ -n "$MAILTO" ]; then
	mutt -F ${HOME}/scripts/etc/muttrc.conf -s "Sync log for $MIRROR on $LOCAL_DATE" $MAILTO < $LOGFILE
fi

# All done, clean
rm -f $LOCK
