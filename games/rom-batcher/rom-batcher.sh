#!/bin/bash

NON_INTERACTIVE=n
DELETE_SOURCE_ARCHIVES=n
DELETE_SOURCE_ROMS=n
CURRENT_WORKING_DIR=.
POSITIONAL_ARGS=()

showHelp() {
    echo "Rom Batcher - Batch Job your ROMs Management"
    echo ""
    echo "Usage: rom-batcher [<options>...]"
    echo ""
    echo "<options>"
    echo "      --roms-dir=</path/to/roms>  -   The path where the roms are stored, if not specified it will use the current directory where the script was executed"
    echo "  -h, --help                      -   Shows this help menu"
    echo "  -q, --non-interactive           -   Executes this script quitely or non-interactively"
    echo "      --delete-source-roms        -   Deletes the source roms after compression or conversion"
    echo "      --delete-source-archives    -   Deletes the source archives after extraction"
}

isNonInteractive() {
    if [[ $NON_INTERACTIVE =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Ask the user the confirmation to do things
askConfirmation() {
    if isNonInteractive; then
        return 0
    else
        read -p "${1}: (y/N) " -n 1 -r
        echo "" #move to next line
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0 # 0 = true
        else
            return 1 # 1 = false
        fi
    fi
}

# Check if a package exists
checkIfPackageExists() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    else
        echo "$1 is not installed"
        return 1
    fi
}

# The Extractor
extract() {
    case "${1}" in
    *.tar.bz2)
        if checkIfPackageExists tar; then
            tar xvjf "${1}"
        fi
        ;;
    *.tar.gz)
        if checkIfPackageExists tar; then
            tar xvzf "${1}"
        fi
        ;;
    *.bz2)
        if checkIfPackageExists bunzip2; then
            bunzip2 "${1}"
        fi
        ;;
    *.rar)
        if checkIfPackageExists rar; then
            rar x "${1}"
        fi
        ;;
    *.gz)
        if checkIfPackageExists gunzip; then
            gunzip "${1}"
        fi
        ;;
    *.tar)
        if checkIfPackageExists tar; then
            tar xvf "${1}"
        fi
        ;;
    *.tbz2)
        if checkIfPackageExists tar; then
            tar xvjf "${1}"
        fi
        ;;
    *.tgz)
        if checkIfPackageExists tar; then
            tar xvzf "${1}"
        fi
        ;;
    *.zip)
        if checkIfPackageExists unzip; then
            unzip -o -d "$(dirname "${1}")" "${1}"
        fi
        ;;
    *.Z)
        if checkIfPackageExists uncompress; then
            uncompress "${1}"
        fi
        ;;
    *.7z)
        assumeYes=""
        if isNonInteractive; then assumeYes="-y"; fi
        if checkIfPackageExists 7z; then
            7z x "${1}" -o"$(dirname "${1}")" "${assumeYes}"
        fi
        ;;
    *) echo "Unsupported extraction format for ${1}" ;;
    esac
}

# Entry point for decompression of roms
extractArchive() {
    if askConfirmation "Extract all (zipped) Roms?"; then
        echo "Extracting all(zipped) Roms"
        # find all archives in 3 sub folder depth
        # example ./game.zip ./console/game.zip ./manufacturer/console/game.zip
        findCommand='find . -maxdepth 3 -type f \( -iname "*.zip" -o -iname "*.7z" \)'
        eval "${findCommand}" | while read -r filename; do extract "${filename}"; done
        # delete the source files
        if (isNonInteractive && [[ $DELETE_SOURCE_ARCHIVES =~ ^[Yy]$ ]]) || askConfirmation "Remove the source archives?"; then
            eval "${findCommand}" -delete
        fi
    fi
}

# Delete the compressed files
deleteCompressedFiles() {
    convertedFiles=$1
    echo "${convertedFiles}"
    convertedFilesCount="${#convertedFiles[@]}"
    echo "Total Compressed Files ${convertedFilesCount}"
    if [[ "${convertedFilesCount}" -gt 0 ]]; then
        if (isNonInteractive && [[ $DELETE_SOURCE_ROMS =~ ^[Yy]$ ]]) || askConfirmation "Remove the source roms?"; then
            for file in "${convertedFiles[@]}"; do
                rm -f "${file%.*}".{gdi,iso,cue,bin}
            done
        fi
    fi
}

# compress psp iso with ciso
cisoCompression() {
    if checkIfPackageExists ciso; then
        echo "Checking if any files are eligible for conversion for CSO"
        mapfile -t files < <(find . -type f \( -iname "*.iso" \))
        eligibleFiles=()
        shopt -s nocasematch
        for file in "${files[@]}"; do
            directory=$(dirname "${file}")
            if [[ "${directory}" =~ (.)?(sony)?(\ )?(.|-|/)?(\ )?(playstation|ppssp|ps)(\ )?(p|portable) ]]; then
                eligibleFiles+=("${file}")
            fi
        done
        shopt -u nocasematch
        if [[ "${#eligibleFiles[@]}" -gt 0 ]] && askConfirmation "Compress all PSP to CSO"; then
            echo "There are totally ${#eligibleFiles[@]} files eligible for conversion"
            convertedFiles=()
            echo "Converting supported files to cso"
            #for file in */*.{gdi,cue,iso}; do
            for file in "${eligibleFiles[@]}"; do
                input="${file}"
                output="${file%.*}.cso"
                echo "Converting ${input} to ${output}"
                if [[ -f "${output}" ]]; then
                    echo "${output} exists skipping conversion"
                    convertedFiles+=("${input}")
                else
                    read -p "Enter the compression value (0-9): [default=5]" -n 1 -r compressionLevel
                    if [[ ! "${compressionLevel}" =~ [0-9] ]]; then
                        compressionLevel=5
                    fi
                    if chdman ciso "${compressionLevel}" "${input}" "${output}"; then
                        convertedFiles+=("${input}")
                    fi
                fi
            done
            deleteCompressedFiles "${convertedFiles[@]}"
        fi
    fi
}

# compress roms using chdman
chdCompression() {
    if checkIfPackageExists chdman; then
        echo "Checking if any files are eligible for conversion for CHD"
        mapfile -t files < <(find . -type f \( -iname "*.gdi" -o -iname "*.cue" -o -iname "*.iso" \))
        eligibleFiles=()
        shopt -s nocasematch
        for file in "${files[@]}"; do
            directory=$(dirname "${file}")
            # checking if the file is placed in either console or emulator folder
            if ! [[ "${directory}" =~ (.)?(sony)?(\ )?(.|-|/)?(\ )?(playstation|ppssp|ps)(\ )?(p|portable) ]] && { [[ "${directory}" =~ (.)?(sony)?(\ )?(.|-)?(\ )?(playstation|duckstation|aethersx|pcsx|ps)(\ )?(x|1|2) ]] || [[ "${directory}" =~ (.)?(sega)?(\ )?(.|-)?(\ )?(dreamcast|saturn|flycast|redream) ]]; }; then
                eligibleFiles+=("${file}")
            fi
        done
        shopt -u nocasematch
        if [[ "${#eligibleFiles[@]}" -gt 0 ]] && askConfirmation "Convert all supported Roms to CHD"; then
            echo "There are totally ${#eligibleFiles[@]} files eligible for conversion"
            convertedFiles=()
            echo "Converting supported files to chd"
            #for file in */*.{gdi,cue,iso}; do

            for file in "${eligibleFiles[@]}"; do
                directory=$(dirname "${file}")
                input="${file}"
                output="${file%.*}.chd"
                echo "Converting ${input} to ${output}"
                if [[ -f "${output}" ]]; then
                    echo "${output} exists skipping conversion"
                    convertedFiles+=("${input}")
                else
                    if chdman createcd -i "${input}" -o "${output}"; then
                        convertedFiles+=("${input}")
                    fi
                fi
            done

            deleteCompressedFiles "${convertedFiles[@]}"
        fi
    fi
}

# Entry point for compress
compressRoms() {
    if askConfirmation "Compress Roms?"; then
        echo "Starting Compression"
        cisoCompression
        chdCompression
    fi
}

# while [[ $# -gt 0 ]]; do
for i in "$@"; do
    case $1 in
    -q | --non-interactive)
        NON_INTERACTIVE=y
        shift # past argument=value
        ;;
    -h | --help)
        showHelp
        exit 0
        ;;
    --delete-source-roms)
        DELETE_SOURCE_ROMS=y
        shift
        ;;
    --delete-source-archives)
        DELETE_SOURCE_ARCHIVES=y
        shift
        ;;
    --roms-dir=*)
        CURRENT_WORKING_DIR="${i#*=}"
        shift
        ;;
    -* | --*)
        echo "Unknown option $1"
        exit 1
        ;;
    *)
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift                   # past argument
        ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

cd "$CURRENT_WORKING_DIR" || exit 1
dir=$(pwd)

echo "Selected Roms Directory - ${dir}"

extractArchive

compressRoms
