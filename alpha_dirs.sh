#!/bin/bash

#Source our utility library
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`


#"move", "copy" or "link"
MODE="move"
IGNORE_THE=false
DRY_RUN=false
RECURSE=false
DEST_DIR=""

#used as a line-centric cache of files to process
PENDING_FILES=""

USAGE=$(cat <<USAGE_END
  Usage: alpha_dirs.sh options (-h) DEST_DIR SOURCE1 [SOURCE2 ... ]

    Take the files from one or more source files/directories and organize them
    into an first-letter organized set of directories so users can easily navigate
    directories using smart devices (like TV's) that lack fast navigation or
    sorting features.

    dest_dir/
    ├── a
    │   ├── Abc
    │   └── Amazing.txt
    ├── b
    │   ├── Baseball.jpg
    │   └── bats
    └── c
        ├── Cows.jpg
        └── crazy_recipe.html


    -h: Print this Message
    
    -d/--dry-run      : Do not move/link any files, just output the paths that would be 
                        created

    -l/--link         : Instead of moving (default) or copying the files, simply link them with
                        symbolic links. 

    -c/--copy         : Instead of moving (default) or linking the files, copy them to the dest
                        directory.

    -t/--ignore-the   : Ignores any leading "the" and whitespace at the beginning of filenames
                        (case insensitive). This option is useful for Movies/TV Shows so names
                        like "The Great Gatsby" will be in g/ rather than t/.

    -r/--recurse      : Recurse into the SOURCE_DIR directories looking for regular files.
                        (Default behavior is to simply take any files at the top level and ignore
                        the rest).

    SOURCE1-N: The files/directories to use for sorting/organizing.
       
USAGE_END
)

usage() {
  echo "${USAGE}"
  echo ""
}

#Generic function to ask "are you sure" that defaults to "no" and exits
user_query_continue(){
    local user_prompt=$1
    if [[ -z $user_prompt ]] ; then
        user_prompt="Are you sure you want to continue? [N/y]?"
    fi
    read -p "$user_prompt" REPLY
    if echo $REPLY | grep -iq "^y" ;then
        echo "Continuing..."
    else
        echo "exiting"; exit 1;
    fi
}

validate_source(){
    echo "validating '$1'"
    [ -e "$1" ] && [ -r "$1" ] && ([ -f "$1" ] || [ -d "$1" ]) || \
    { echo "Not a valid (readable) file/directory: $1... Bailing"; exit 1; }
}

iterate_source(){
  #TODO: Do we need to handle symlinks and other special types?
  local find_output=""

  #file source
  if [ -f "$1" ]; then
    if [ -z "$PENDING_FILES" ]; then
      PENDING_FILES="$1"
    else
      PENDING_FILES="${PENDING_FILES}
${1}"
    fi
  fi

  #directory source
  if [ -d "$1" ]; then
    if $RECURSE; then
      find_output=$(find "$1" -type f)
    else
      find_output=$(find "$1" -maxdepth 1 -mindepth 1)
    fi
    if [ -z "$PENDING_FILES" ]; then
      PENDING_FILES="$find_output"
    else
      PENDING_FILES="${PENDING_FILES}
${find_output}"
    fi
  fi
}

operate_on_file(){
  local first_letter="$1"
  local source_file=$(realpath "$2")
  local bname=$(basename "$source_file")

  local target="${DEST_DIR}/${first_letter}"

  #Create the dest dir (if it doesn't exist)
  if [ ! -e "$target" ]; then
    mkdir -p "$target" || { echo "Unable to create directory \"${target}\", exiting..."; exit 1; }
  else
    [ -d "$target" ] && \
    [ -w "$target" ] || \
    { echo "Target directory \"${target}\" exists, but is not a writeable directory, exiting..."; exit 1; }
  fi

  #Handle dupes
  if [ -e "$target/$bname" ]; then
    echo "Duplicate file \"$source_file\" found! Skipping...."
    return
  fi

  case "$MODE" in 
    'move')
      mv "$source_file" "$target" || { exit 1; }
    ;;
    'copy')
      cp -a "$source_file" "$target" || { exit 1; }
    ;;
    'link')
      ln -s "$source_file" "$target" || { exit 1; }
    ;;
  esac 
}

TEMP=$(getopt -o 'hdlctr' -l 'help,dry-run,link,copy,ignore-the,recurse' -n 'alpha_dirs.sh' -- "$@")

if [ $? -ne 0 ]; then
  echo 'Terminating...' >&2
  exit 1
fi

# Note the quotes around "$TEMP": they are essential!
eval set -- "$TEMP"
unset TEMP

MODES_SPECIFIED=0
while true; do
    case "$1" in 
        '-h'|'--help')
          usage;
          exit 0;
        ;;
        '-c'|'--copy')
          MODE="copy"
          shift
          MODES_SPECIFIED=$((MODES_SPECIFIED+1))
        ;;
        '-l'|'--link')
          MODE="link"
          shift
          MODES_SPECIFIED=$((MODES_SPECIFIED+1))
        ;;
        '-t'|'--ignore-the')
          IGNORE_THE=true
          shift 
        ;;
        '-r'|'--recurse')
          RECURSE=true
          shift
        ;;
        '--')
          shift
          break
        ;;
        *)
          usage;
          echo 'Invalid argument specified!' >&2
          exit 1
        ;;
    esac
done

#Make sure the user only specified one mode
if [ $MODES_SPECIFIED -gt 1 ]; then
    echo "Error: Only *one* create (-l) or copy (-c) option may be specified. Exiting..."
    exit 1
fi

#Make sure there are sources and a DEST specified
if (( "$#" < 2 )); then
  echo "There are not enough arguments, exiting";
  usage
  exit 1
fi

DEST_DIR="$1"
shift

#TODO: Do we need to check for embedded directories (SOURCE is inside DEST?)


#Ensure each source exists (bail if it doesn't)
#and collate them into a big list
for s in "$@"; do
  validate_source "$s"
  iterate_source "$s"
done

echo "PENDING_FILES is: $PENDING_FILES"

#get the basenames of every file
BASENAMES=""
while read -r line; do
  BASENAMES="${BASENAMES}"$(basename "$line")"
"
done <<< "$PENDING_FILES"

echo "Basenames is: $BASENAMES"

#If we're stripping leading "The" words, do that here
#otherwise just strip leading whitespace
if $IGNORE_THE; then
  BASENAMES=$(echo "$BASENAMES" | sed 's/^[^[:alnum:]]\+//' |sed 's/^[Tt][Hh][Ee][^[:alnum:]]*//' )
else
  BASENAMES=$(echo "$BASENAMES" | sed 's/^[ \t.]+//')
fi

echo "Corrected basenames is: $BASENAMES"

#Get the first letters
FIRST_CHARS=""
while read -r line; do
  FIRST_CHARS="${FIRST_CHARS}${line:0:1}
"
done <<< "$BASENAMES"
FIRST_CHARS=$(echo "$FIRST_CHARS" |tr '[:upper:]' '[:lower:]')

echo "First chars is: $FIRST_CHARS"

#Finally, iterate the PENDING_FILES and operate on each
while read -u 3 -r file_path && read -u 4 -r first_letter; do
  #echo "path is \"$file_path", first letter is \"$first_letter\";
  operate_on_file "$first_letter" "$file_path"
done 3< <(echo "$PENDING_FILES") 4< <(echo "$FIRST_CHARS")


