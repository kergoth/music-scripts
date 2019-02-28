# Commonly used metadata variables
md_vars="track tracknumber tracktotal totaltracks \
         disc discnumber disctotal totaldiscs \
         artist album_artist title album compilation"

die () {
    ret="$1"
    shift
    fmt="$1"
    shift
    printf >&2 "Error: $fmt\n" "$@"
    exit $ret
}

get_metadata () {
    fn="$1"
    shift
    pat="$(echo "$@" | sed -e 's/  */ /g')"
    ffprobe -loglevel quiet -of compact=p=0 -show_entries format_tags "$fn" \
        | tr '|' '\n' \
        | sed -e 's/tag://' \
        | grep -v '\\r' \
        | while IFS="=" read -r key value; do
            if [ -z "$key" ]; then
                continue
            fi
            case "$key" in
                *\ *)
                    key="$(echo "$key" | tr " " _)"
                    ;;
            esac
            key="$(printf '%s\n' "$key" | tr ".:/-#=\`" "_______" | tr "[:upper:]" "[:lower:]" | tr -d '\')"
            case " $pat " in
                *\ $key\ *)
                    ;;
                *)
                    continue
                    ;;
            esac
            value="$(printf '%s\n' "$value" | sed -e 's/"/\\"/g; s/\\$//; s/`/\\`/g')"
            printf '%s="%s"\n' "$key" "$value"
        done
}

eval_metadata () {
    # Useful for debugging shell syntax errors when eval'ing the metadata
    # get_metadata "$@" | while read -r line; do
    #     ( eval "$line" ) >/dev/null 2>&1 || die 1 'Unable to eval `%s`' "$line"
    # done
    eval "$(get_metadata "$@")"
}

eval_common_metadata () {
    fn="$1"
    shift
    if [ $# -eq 0 ]; then
        set -- $md_vars
    fi
    eval_metadata "$fn" "$@"
}
