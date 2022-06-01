#! /bin/sh

askConfirmation() {
    read -p "${1}: (y/N) " -n 1 -r
    echo "" #move to next line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0 # 0 = true
    else
        return 1 # 1 = false
    fi
}

extract() {
    echo "param ${1}"
    case "${1}" in
    *.tar.bz2) tar xvjf "${1}" ;;
    *.tar.gz) tar xvzf "${1}" ;;
    *.bz2) bunzip2 "${1}" ;;
    # *.rar) rar x "${1}" ;;
    *.gz) gunzip "${1}" ;;
    *.tar) tar xvf "${1}" ;;
    *.tbz2) tar xvjf "${1}" ;;
    *.tgz) tar xvzf "${1}" ;;
    *.zip) unzip -o -d "$(dirname "${1}")" "${1}" ;;
    # *.Z) uncompress $1 ;;
    *.7z) 7z x "${1}";;
    *) echo "Unsupported extraction format for ${1}" ;;
    esac
}

compressUsingChdman() {
    chdman createcd -i "${1}" -o "${2}"
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}



if askConfirmation "Extract all (zipped) Roms?"; then
    echo "Extracting all(zipped) Roms"
    # find all archives in 3 sub folder depth
    # example ./game.zip ./console/game.zip ./manufacturer/console/game.zip
    find . -type f -name "*.zip" -maxdepth 3 | while read filename; do extract "${filename}"; done
    # delete the source files
    if askConfirmation "Remove the source archives?"; then
        find . -type f -name "*.zip" -maxdepth 3 -delete
    fi
fi

if askConfirmation "Convert all supported Roms to CHD"; then
    convertedFiles=()
    echo "Converting supported files to chd"
    for file in */*.{gdi,cue,iso}; do
        directory=$(dirname "${file}")
        # checking if the file is placed in either console or emulator folder
        if [[ "${directory}" =~ (.)?(sony)?(\s)?(.|-)?(\s)?(playstation|duckstation|aethersx|pcsx|ps)(\s)?(x|1|2) ]] && [[ "${directory}" =~ (.)?(sega)?(\s)?(.|-)?(\s)?(dreamcast|saturn|flycast|redream) ]]; then
            input="${file}"
            output="${file%.*}.chd"
            if [[ ! "${convertedFiles[*]}" =~ "${file%.*}" ]]; then
                if compressUsingChdman "${input}" "${output}"; then
                    convertedFiles+=("${input}")
                fi
            fi
        fi
    done
    convertedFilesCount="${#convertedFiles[@]}"
    echo "Converted ${convertedFilesCount}"
    if [[ "${convertedFilesCount}" > 0 ]]; then
        echo "${convertedFiles}"

        if askConfirmation "Remove the source roms?"; then
            for file in "${convertedFiles}"; do
                rm -f "${file%.*}".{gdi,iso,cue,bin}
            done
        fi
    fi
fi
