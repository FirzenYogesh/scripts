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
    *.7z) 7z x "${1}" ;;
    *) echo "Unsupported extraction format for ${1}" ;;
    esac
}

decompress() {
    if askConfirmation "Extract all (zipped) Roms?"; then
        echo "Extracting all(zipped) Roms"
        # find all archives in 3 sub folder depth
        # example ./game.zip ./console/game.zip ./manufacturer/console/game.zip
        find . -type f -name "*.zip" -maxdepth 3 | while read -r filename; do extract "${filename}"; done
        # delete the source files
        if askConfirmation "Remove the source archives?"; then
            find . -type f -name "*.zip" -maxdepth 3 -delete
        fi
    fi
}

cisoCompression() {
    if ! command -v ciso >/dev/null 2>&1; then
        if askConfirmation "Compress all PSP to CSO"; then
            convertedFiles=()
            echo "Converting supported files to chd"
            for file in */*.{gdi,cue,iso}; do
                directory=$(dirname "${file}")
                if [[ "${directory}" =~ (.)?(sony)?(\s)?(.|-)?(\s)?(playstation|ppssp|ps)(\s)?(p|portable) ]]; then
                    input="${file}"
                    output="${file%.*}.cso"
                    read -p "Enter the compression value (0-9): [default=5]" -n 1 -r compressionLevel
                    if [[ ! "${compressionLevel}" =~ [0-9] ]]; then
                        compressionLevel=5
                    fi
                    if chdman ciso "${compressionLevel}" "${input}" "${output}"; then
                        convertedFiles+=("${input}")
                    fi
                fi
            done
        fi
    else
        echo "ciso is not installed"
    fi
}

chdCompression() {
    if ! command -v chdman >/dev/null 2>&1; then
        if askConfirmation "Convert all supported Roms to CHD"; then
            convertedFiles=()
            echo "Converting supported files to chd"
            for file in */*.{gdi,cue,iso}; do
                directory=$(dirname "${file}")
                # checking if the file is placed in either console or emulator folder
                if [[ "${directory}" =~ (.)?(sony)?(\s)?(.|-)?(\s)?(playstation|duckstation|aethersx|pcsx|ps)(\s)?(x|1|2) ]] && [[ "${directory}" =~ (.)?(sega)?(\s)?(.|-)?(\s)?(dreamcast|saturn|flycast|redream) ]]; then
                    input="${file}"
                    output="${file%.*}.chd"
                    if chdman createcd -i "${input}" -o "${output}"; then
                        convertedFiles+=("${input}")
                    fi
                fi
            done
            convertedFilesCount="${#convertedFiles[@]}"
            echo "Converted ${convertedFilesCount}"
            if [[ "${convertedFilesCount}" -gt 0 ]]; then
                echo "${convertedFiles}"
                if askConfirmation "Remove the source roms?"; then
                    for file in "${convertedFiles[@]}"; do
                        rm -f "${file%.*}".{gdi,iso,cue,bin}
                    done
                fi
            fi
        fi
    else
        echo "chdman is not installed"
    fi
}

compress() {
    if askConfirmation "Compress Roms?"; then
        echo "Starting Compression"
        cisoCompression
        chdCompression
    fi
}

decompress

compress
