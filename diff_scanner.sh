#!/bin/bash

# DiffScanner
# Scans two folders (typically two copies of a codebase or other plain-text files) and allows the user to compare and resolve differing files.
# by iritscen@yahoo.com
#
# HISTORY:
# 1.0 - initial release

###PARAMETER INITIALIZATION###
# Set the field separator to a newline to avoid spaces in paths breaking our variable-setting later
IFS="
"

# Check that we have no more or less than 2 arguments
if [ $# -ne 2 ]; then
	echo "Error: DiffScanner needs to be passed two folders!"
	echo "Usage: diffscanner.sh folder1 folder2"
	exit
fi

# Store parameters
FOLDER1=$1
FOLDER2=$2

# Make sure both arguments are existing folders
if [ ! -d "$FOLDER1" ] || [ ! -d "$FOLDER2" ]; then
	echo "Error: At least one argument is not a folder!"
	echo "Usage: diffscanner.sh folder1 folder2"
	exit
fi

###VARIABLE INITIALIZATION###
VERSION="1.0"
MAXREPLACE=3000

# Variables for stat collection
num_differ=0
num_differ_replaced=0
num_unique_1=0
num_unique_2=0
num_unique_1_copied=0
num_unique_2_copied=0
# scan_progress is set to "1" when we start scanning FOLDER1, then to "2" when we start on FOLDER2, then to "3" when we finish
scan_progress=0
# compare_mode tells the script to compare files by date ("d"), size ("s"), or md5 checksum ("c")
compare_mode=""
# unique_mode tells the script to display files which are unique to FOLDER1 (1), FOLDER2 (2), either side (3), to only show unique files (4), or to ignore unique files (0)
unique_mode=
# date_mode_base tells the script, in compare_mode "d", to report all files with differing modification dates (0), the files that are newer in FOLDER1 (1), or the files that are newer in FOLDER2 (2)
date_mode_base=
# desired_suffix tells the script to only match files with that suffix (actually takes a regex pattern)
desired_suffix=""
# Used for file comparisons
mod_time1=0
mod_time2=0
size1=0
size2=0
# Set up trash and log paths
the_time=$(date "+%Y-%m-%d--%H-%M-%S")
TRASH="$HOME/.Trash/DiffScanner's replaced files ($the_time)"
mkdir "$TRASH"
if [ ! -d "$TRASH" ]; then
	echo "DiffScanner: Could not create folder in Trash for replaced files. Exiting..."
	exit
fi
LOG="$TRASH/DiffScanner log.txt"
echo "DiffScanner "$VERSION" initializing..." >> $LOG
# Declare file variables here so they are globals that can be accessed by bashtrap() upon force-quit
FILE1=""
FILE2=""

# Well, we made it this far, so let's welcome the user
echo "==========================="
echo "Welcome to DiffScanner "$VERSION"."; echo
echo "I see you would like to compare files in"
echo "(1) $FOLDER1 and"
echo "(2) $FOLDER2"; echo
echo "Any files you choose to replace are not deleted, but can be found in the Trash."; echo
echo "You can use the standard Ctrl+C to quit at any time if you get bored."; echo

###UTILITY FUNCTIONS###
# Set up exit message to print in event of user force-quitting script
function bashtrap()
{
	echo
	let unique_total=$num_unique_1_copied+$num_unique_2_copied
	if [ $scan_progress -eq 0 ]; then
		echo "DiffScanner was quit before scan began. No files were changed." | tee -a $LOG
	elif [ $scan_progress -eq 1 ]; then
		echo "DiffScanner was quit during scan of (1) $FOLDER1."
		echo "$unique_total files were copied and $num_differ_replaced files were replaced." | tee -a $LOG
		echo "See log in Trash for details."
	elif [ $scan_progress -eq 2 ]; then
		echo "DiffScanner was quit during scan of (2) $FOLDER2."
		echo "$unique_total files were copied and $num_differ_replaced files were replaced." | tee -a $LOG
		echo "See log in Trash for details."
	elif [ $scan_progress -eq 3 ]; then
		echo "DiffScanner was quit after scan finished."
		echo "$unique_total files were copied and $num_differ_replaced files were replaced." | tee -a $LOG
		echo "See log in Trash for details."
	fi
	exit
}

trap bashtrap INT

# Replace $1 with $2, placing $1 in the Trash
function safeReplace()
{
	DESIRED_PATH="$TRASH/$(basename $1)"
	isFile=

	if ! [ -a "$DESIRED_PATH" ]; then
		mv "$1" "$TRASH"
		cp -a "$2" "$1"
		return
	elif [ -f "$DESIRED_PATH" ]; then
		isFile=true
	elif [ -d "$DESIRED_PATH" ]; then
		isFile=false
	else
		echo "Error: Encountered something that is not a file or directory: $DESIRED_PATH."
		exit
	fi

	ct=0
	TEST_PATH="$DESIRED_PATH"
	until [ $ct -eq $MAXREPLACE ]
	do
		if [ -a "$TEST_PATH" ]; then
			let ct+=1
			# If this is a file and it has a suffix, break the name up at the period so we
			# can insert the unique number at the end of the name and not the suffix
			if $isFile && [[ $DESIRED_PATH == *.* ]]; then
				preDot=${DESIRED_PATH%.*}
				postDot=${DESIRED_PATH##*.}
				TEST_PATH="$preDot $ct.$postDot"
			else
				TEST_PATH="$DESIRED_PATH $ct"
			fi
		else
			break
		fi
	done
	if [ $ct -eq $MAXREPLACE ]; then
		# Just quit, because something is probably wrong
		echo "Error: Cannot find a place in $(dirname $DESIRED_PATH) for $(basename $DESIRED_PATH)."
		exit
	else
		mv "$1" "$TEST_PATH"
		cp -a "$2" "$1"
	fi
}

echo "Querying user for options..." >> $LOG

###SUFFIX QUERY###
echo "Compare only (s)ource files (default), (a)ll files, or only the files with suffixes matching a (r)egex pattern that you will supply?"
read desired_suffix
if [ -z "$desired_suffix" ] || [ "$desired_suffix" == "s" ]; then
	desired_suffix="[mch]"
elif [ "$desired_suffix" == "a" ]; then
	desired_suffix="*"
elif [ "$desired_suffix" == "r" ]; then
	echo "Please enter the regex pattern to match, e.g. [mch] for all files ending in .m, .c, and .h."
	read desired_suffix
else
	echo "Received input that was not \"a\", \"s\", Enter, or \"r\". DiffScanner will scan only source files."
	desired_suffix="[mch]"
fi

###COMPARE MODE QUERY###
echo "Search for differing files according to modification (d)ate, (s)ize, or (c)hecksum (default)?"
read compare_mode
if [ -z "$compare_mode" ]; then
	compare_mode="c"
elif [ "$compare_mode" == "d" ]; then
	# Now we need to know if only newer files are a concern, and which folder is the baseline for "newer"
	echo "Report (a)ll files with differing dates, or only files that are newer on (o)ne side? (If you choose \"o\", the next question is which side.)"
	read a
	if [ -z "$a" ]; then
		date_mode_base=0
	fi
	if [ "$a" == "o" ]; then
		echo "On which side are you interested in seeing the newer files? Type \"1\" for $FOLDER1 and \"2\" for $FOLDER2."
		read a
		if [ "$a" -eq 1 ]; then
			date_mode_base=1
		elif [ "$a" -eq 2 ]; then
			date_mode_base=2
		else
			date_mode_base=0
			echo "Received input that was not \"1\" or \"2\"; DiffScanner will show all differing file dates…"
		fi
	fi
elif [ "$compare_mode" != "s" ] && [ "$compare_mode" != "c" ]; then
	echo "DiffScanner received input which is not \"d\", \"s\", or \"c\". DiffScanner will compare by checksum."
	compare_mode="c"
fi

###UNIQUE MODE QUERY###
echo "Show (a)ll files which are unique to either side,"
echo "files which are unique to only one (s)ide,"
echo "(o)nly show unique files and no matching ones, or"
echo "(i)gnore unique files? (If you choose \"s\", the next question is which side.) (default = all)"
read a
# If user entered nothing, use the "all" choice
if [ -z "$a" ]; then
	unique_mode=3
elif [ "$a" == "s" ]; then
	echo "On which side are you interested in seeing files that are unique?"
	echo "(1) $FOLDER1 or"
	echo "(2) $FOLDER2?"
	read a
	if [ "$a" -eq 1 ]; then
		unique_mode=1
	elif [ "$a" -eq 2 ]; then
		unique_mode=2
	else
		unique_mode=3
		echo "Received input that was not \"1\" or \"2\"; DiffScanner will show all unique files…"
	fi
elif [ "$a" == "i" ]; then
	unique_mode=0
elif [ "$a" == "o" ]; then
	unique_mode=4
else
	unique_mode=3
	echo "Received input that was not \"a\", \"o\", or \"i\"; DiffScanner will show all unique files…"
fi

###MODE REPORTING###
if [ $compare_mode == "d" ] && [ $unique_mode != 4 ]; then
	if [ "$date_mode_base" -eq 0 ]; then
		echo "Scanning the designated folders for files that are newer on either side." | tee -a $LOG
	elif [ "$date_mode_base" -eq 1 ]; then
		echo "Scanning the designated folders for files that are newer in $FOLDER1." | tee -a $LOG
	elif [ "$date_mode_base" -eq 2 ]; then
		echo "Scanning the designated folders for files that are newer in $FOLDER2." | tee -a $LOG
	fi
elif [ $compare_mode == "s" ] && [ $unique_mode != 4 ]; then
	echo "Scanning the designated folders for files that differ in size." | tee -a $LOG
elif [ $compare_mode == "c" ] && [ $unique_mode != 4 ]; then
	echo "Scanning the designated folders for files that differ by checksum." | tee -a $LOG
fi
if [ $unique_mode == 0 ]; then
	echo "(Ignoring unique files.)" | tee -a $LOG
elif [ $unique_mode == 1 ]; then
	echo "Also scanning for unique files in $FOLDER1." | tee -a $LOG
elif [ $unique_mode == 2 ]; then
	echo "Also scanning for unique files in $FOLDER2." | tee -a $LOG
elif [ $unique_mode == 3 ]; then
	echo "Also scanning for unique files on either side." | tee -a $LOG
elif [ $unique_mode == 4 ]; then
	echo "Only scanning for unique files on either side." | tee -a $LOG
fi

echo
scan_progress=1

###FOLDER1 SCAN###
# Check FOLDER1 for files that have differing mod. dates or that are unique to FOLDER1
for FILE1 in `find $FOLDER1 -type f -name "*.${desired_suffix}" -a ! -name ".DS_Store" -a ! -wholename "*.svn*" -a ! -wholename "*/build/*"`; do
	# Change the file's path string to be in FOLDER2
	FILE2=${FILE1#$FOLDER1}
	FILE2=${FOLDER2}${FILE2}
	###UNIQUE MODE SCAN###
	# If there is no such file in FOLDER2 and we are not ignoring unique files...
	if [ ! -f "$FILE2" ] && [ $unique_mode -gt 0 ]; then
		let num_unique_1+=1
		echo "Unique file #$num_unique_1:"
		echo ${FILE1#$FOLDER1/}
		echo "does not exist in"
		echo $FOLDER2
		echo "Copy file to there? (y/n) (default = no)"
		read a
		if [ "$a" == "y" ]; then
			echo "Copying file…"
			 echo "Copying $FILE1 to $FOLDER2." >> $LOG
			 mkdir -p $(dirname $FILE2) && cp -a $FILE1 $FILE2
			 let num_unique_1_copied+=1
		 fi
	# If there is such a file in FOLDER2 and we are not ignoring matching files...
	elif [ -f "$FILE2" ] && [ $unique_mode -lt 4 ]; then
		 ###DATE MODE SCAN###
		 if [ $compare_mode == "d" ]; then
			# First find out which file is older, if either
			### Use quotes around $FILE1?
			mod_time1=$(stat -s $FILE1)
			mod_time1=${mod_time1#*st_mtime=*}
			mod_time1=${mod_time1%% *}
			mod_time2=$(stat -s $FILE2)
			mod_time2=${mod_time2#*st_mtime=*}
			mod_time2=${mod_time2%% *}
			if [ $mod_time1 -gt $mod_time2 ]; then
				first_is_newer=1
			elif [ $mod_time1 -lt $mod_time2 ]; then
				first_is_newer=0
			else
				# Files must be the same age
				first_is_newer=-1
			fi

			# Now we see if the date condition fails to meet the "interested in" criteria the user set
			# If not, "continue" moves to the next file in the 'for' loop
			# First, if the files are the same age, just cut out now
			if [ $first_is_newer -eq -1 ]; then
				continue
			fi
			let num_differ+=1
			# If the user wanted to see only files that were newer in FOLDER1 but FOLDER2 has the newer file, then cut out
			if [ $date_mode_base -eq 1 ] && [ $first_is_newer -ne 1 ]; then
				echo "Skipping differing file #$num_differ that is newer in Folder 2."; echo
				continue
			fi
			# Or if the case is vice-versa, cut out
			if [ $date_mode_base -eq 2 ] && [ $first_is_newer -ne 0 ]; then
				echo "Skipping differing file #$num_differ that is newer in Folder 1."; echo
				continue
			fi

			# If we're still here on this file, then we say to the user...
			echo "Differing file #$num_differ:"
			echo $FILE1
			echo "was modified on $(date -r $mod_time1), and"
			echo $FILE2
			echo "was modified on $(date -r $mod_time2)."
			echo "Use (f)ileMerge to diff-gaze,"
			echo "replace the older file with the (n)ewer one,"
			echo "replace the newer file with the (o)lder one, or"
			echo "(i)gnore file? (default = ignore)"
			read a
			if [ -z "$a" ]; then
				a="i"
			fi
			if [ "$a" == "i" ]; then
				if [ $first_is_newer ]; then
					echo "$FILE1 was newer than it was in $FOLDER2; the file was skipped." >> $LOG
				else
					echo "$FILE2 was newer than it was in $FOLDER1; the file was skipped." >> $LOG
				fi
				echo "Skipping file."
				continue
			fi
			if [ "$a" == "f" ]; then
				echo "Opening FileMerge…"
				opendiff $FILE1 $FILE2
				echo "Now do you want to replace the older with the (n)ewer,"
				echo "the newer with the (o)lder, or"
				echo "(i)gnore the file? (default = ignore)"
				read a
			fi
			if [ "$a" == "n" ]; then
				echo "Replacing older file with newer one."
				if [ $first_is_newer -eq 1 ]; then
					echo "Replacing $FILE2 (which was older) with $FILE1..." >> $LOG
					safeReplace "$FILE2" "$FILE1"
				else
					echo "Replacing $FILE1 (which was older) with $FILE2..." >> $LOG
					safeReplace "$FILE1" "$FILE2"
				fi
				let num_differ_replaced+=1
			elif [ "$a" == "o" ]; then
				echo "Replacing newer file with older one."
				if [ $first_is_newer -eq 1 ]; then
					echo "Replacing $FILE1 (which was newer) with $FILE2..." >> $LOG
					safeReplace "$FILE1" "$FILE2"
				else
					echo "Replacing $FILE2 (which was newer) with $FILE1..." >> $LOG
					safeReplace "$FILE2" "$FILE1"
				fi
				let num_differ_replaced+=1
			else
				echo "Received input that was not \"i\", Enter, \"f\", \"n\", or \"o\". Ignoring file."
				if [ $first_is_newer ]; then
					echo "$FILE1 was newer than it was in $FOLDER2; the file was skipped due to unclear user input." >> $LOG
				else
					echo "$FILE2 was newer than it was in $FOLDER1; the file was skipped due to unclear user input." >> $LOG
				fi
			fi
			echo
		###SIZE MODE SCAN###
		elif [ $compare_mode == "s" ]; then
			size1=$(stat -s "$FILE1")
			size1=${size1#*st_size=*}
			size1=${size1%% *}
			size2=$(stat -s "$FILE2")
			size2=${size2#*st_size=*}
			size2=${size2%% *}
			if [ $size1 != $size2 ]; then
				let num_differ+=1
				echo "Differing file #$num_differ:"
				echo ${FILE1#$FOLDER1/}
				echo "Use (f)ileMerge to diff-gaze,"
				echo "replace file in"
				echo " 2. $FOLDER2 with"
				echo "(1) $FOLDER1,"
				echo "replace file in"
				echo " 1. $FOLDER1 with"
				echo "(2) $FOLDER2, or"
				echo "(i)gnore file? (default = ignore)"
				read a
				if [ -z "$a" ]; then
					a="i"
				fi
				if [ "$a" == "f" ]; then
					echo "Opening FileMerge…"
					opendiff $FILE1 $FILE2
					echo "Now do you want to replace the file in"
					echo " 2. $FOLDER2 with"
					echo "(1) $FOLDER1,"
					echo "replace the file in"
					echo " 1. $FOLDER1 with"
					echo "(2) $FOLDER2, or"
					echo "(i)gnore the file? (default = ignore)"
					read a
				fi
				if [ -z "$a" ]; then
					a="i"
				fi
				# This 'if' stmt prevents the error "integer expression expected" if the user didn't enter 1 or 2 and we hit the next 'if' stmts
				if [ "$a" == "i" ]; then
					# We don't have to do anything here, so NOP
					echo -n	
				elif [ "$a" -eq 1 ]; then
					echo "Replacing file in folder 2."
					echo "Replacing $FILE2 with $FILE1..." >> $LOG
					safeReplace "$FILE2" "$FILE1"
					let num_differ_replaced+=1
				elif [ "$a" -eq 2 ]; then
					echo "Replacing file in folder 1."
					echo "Replacing $FILE1 with $FILE2..." >> $LOG
					safeReplace "$FILE1" "$FILE2"
					let num_differ_replaced+=1
				else
					echo "DiffScanner received input that was not \"1\", \"2\", or \"i\"; skipping file."
					echo "${FILE1#$FOLDER1} differed in size between $FOLDER1 and $FOLDER2; the file was skipped." >> $LOG
				fi
			fi
		###CHECKSUM MODE SCAN###
		elif [ $compare_mode == "c" ]; then
			md1=$(md5 "$FILE1" | grep -o "\b[[:alnum:]]*$")
			md2=$(md5 "$FILE2" | grep -o "\b[[:alnum:]]*$")
			if [ $md1 != $md2 ]; then
				let num_differ+=1
				echo "Differing file #$num_differ:"
				echo ${FILE1#$FOLDER1/}
				echo "Use (f)ileMerge to diff-gaze,"
				echo "replace file in"
				echo " 2. $FOLDER2 with"
				echo "(1) $FOLDER1,"
				echo "replace file in"
				echo " 1. $FOLDER1 with"
				echo "(2) $FOLDER2, or"
				echo "(i)gnore file? (default = ignore)"
				read a
				if [ -z "$a" ]; then
					a="i"
				fi
				if [ "$a" == "f" ]; then
					echo "Opening FileMerge…"
					opendiff $FILE1 $FILE2
					echo "Now do you want to replace the file in"
					echo " 2. $FOLDER2 with"
					echo "(1) $FOLDER1,"
					echo "replace the file in"
					echo " 1. $FOLDER1 with"
					echo "(2) $FOLDER2, or"
					echo "(i)gnore the file? (default = ignore)"
					read a
				fi
				if [ -z "$a" ]; then
					a="i"
				fi
				# This 'if' stmt prevents the error "integer expression expected" if the user didn't enter 1 or 2 and we hit the next 'if' stmts
				if [ "$a" == "i" ]; then
					# We don't have to do anything here, so NOP
					echo -n
				elif [ "$a" -eq 1 ]; then
					echo "Replacing file in folder 2."
					echo "Replacing $FILE2 with $FILE1..." >> $LOG
					safeReplace "$FILE2" "$FILE1"
					let num_differ_replaced+=1
				elif [ "$a" -eq 2 ]; then
					echo "Replacing file in folder 1."
					echo "Replacing $FILE1 with $FILE2..." >> $LOG
					safeReplace "$FILE1" "$FILE2"
					let num_differ_replaced+=1
				else
					echo "Received input that was not \"i\", Enter, \"1\", or \"2\". Ignoring file."
					echo "${FILE1#$FOLDER1} differed in checksum between $FOLDER1 and $FOLDER2; the file was skipped due to unclear user input." >> $LOG
				fi
			fi
		fi
	fi
done

scan_progress=2

###FOLDER2 UNIQUE MODE SCAN###
# Check FOLDER2 for files that are unique to FOLDER2
for FILE2 in `find $FOLDER2 -type f -name "*.${desired_suffix}" -a ! -name ".DS_Store" -a ! -wholename "*.svn*" -a ! -wholename "*/build/*"`; do
	FILE1=${FILE2#$FOLDER2}
	FILE1=${FOLDER1}${FILE1}
	# If there is no such file in FOLDER1 and we are not ignoring unique files...
	if [ ! -f "$FILE1" ] && [ $unique_mode -gt 0 ]; then
		let num_unique_2+=1
		let num_unique_both=$num_unique_1+$num_unique_2
		echo "Unique file #$num_unique_both:"
		echo "${FILE2#$FOLDER2/} does not exist in"
		echo $FOLDER1
		echo "Copy file to there? (y/n) (default = no)"
		read a
		if [ "$a" == "y" ]; then
			echo "Copying file…"
			echo "Copying $FILE2 to $FOLDER1." >> $LOG
			mkdir -p $(dirname $FILE1) && cp -a $FILE2 $FILE1
			let num_unique_2_copied+=1
		fi
	# And that's it! We don't have to do anything if FILE1 does exist because we already took care of matching files from the side of the FOLDER1 'for' loop
	fi
done

scan_progress=3

echo "Finished scan.
$num_unique_1_copied out of $num_unique_1 unique files were copied from (1) $FOLDER1 to (2) $FOLDER2;
$num_unique_2_copied out of $num_unique_2 unique files were copied from (2) $FOLDER2 to (1) $FOLDER1;
$num_differ_replaced out of $num_differ differing files were replaced." | tee -a $LOG