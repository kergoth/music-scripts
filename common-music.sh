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
            if [ -n "$pat" ]; then
                case " $pat " in
                    *\ $key\ *)
                        ;;
                    *)
                        continue
                        ;;
                esac
            fi
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

get_new_filename () {
    fn="$1"
    source_dir="$2"
    compilation=
    (
        eval_common_metadata "$fn" || die 1 "Failed to eval metadata for $fn"

        oldtracktotal="$tracktotal"
        track="$(get_tracknumber || :)"
        case "$track" in
            */*)
                tracknumber="${track%/*}"
                tracktotal="${track##*/}"
                ;;
            *)
                tracknumber="$track"
                tracktotal=
                ;;
        esac

        disc="$(get_discnumber)" || :
        case "$disc" in
            */*)
                discnumber="${disc%/*}"
                disctotal="${disc##*/}"
                ;;
            *)
                discnumber="$disc"
                disctotal=1
                ;;
        esac

        if [ -n "$tracknumber" ]; then
            newfn="$tracknumber - "
        else
            newfn=
        fi

        if echo "$releasetype" | tr ',' ' ' | grep -qwi compilation \
            || ( [ -n "$compilation" ] && [ "$compilation" = 1 ] ) \
            || ( [ -n "$album_artist" ] && echo "$album_artist" | grep -qi '^various' ); then
            newfn="$newfn$artist - "
            compilation=1
        fi
        newfn="$newfn$title.${fn##*.}"
        if [ "$disctotal" != 1 ]; then
            newfn="$discnumber-$newfn"
        fi
        if [ -n "$compilation" ] && [ "$compilation" -eq 1 ]; then
            artistdir=Compilations
        elif [ -n "$album_artist" ]; then
            artistdir="$album_artist"
        elif [ -n "$artist" ]; then
            artistdir="$artist"
        else
            artistdir="[unknown]"
        fi
        if [ -n "$album" ]; then
            albumdir="$album"
        else
            albumdir="[unknown]"
        fi
        artistdir="$(echo "$artistdir" | tr ':/' '∶／' | sed -e 's/^\.//')"
        albumdir="$(echo "$albumdir" | tr ':/' '∶／' | sed -e 's/^\.//')"
        destdir="$artistdir/$albumdir"
        newfn="$(echo "$newfn" | tr ':/' '∶／')"
        destfn="$source_dir/$destdir/$newfn"
        echo "$destfn"
    )
}

get_tracknumber() {
    case "$track" in
        */*)
            tracknumber="${track%/*}"
            tracktotal="${track##*/}"
            ;;
        '') ;;

        *)
            tracknumber="$track"
            ;;
    esac
    if [ -z "$tracknumber" ]; then
        return 1
    fi
    if [ -z "$tracktotal" ] && [ -n "$totaltracks" ]; then
        tracktotal="$totaltracks"
    fi
    printf "$tracknumber"
    if [ -n "$tracktotal" ]; then
        printf "/$tracktotal"
    fi
    printf '\n'
}

get_discnumber() {
    case "$disc" in
        */*)
            discnumber="${disc%/*}"
            disctotal="${disc##*/}"
            ;;
        '') ;;

        *)
            discnumber="$disc"
            ;;
    esac
    if [ -z "$discnumber" ]; then
        discnumber=1
    fi
    if [ -z "$disctotal" ] && [ -n "$totaldiscs" ]; then
        disctotal="$totaldiscs"
    fi
    printf "$discnumber"
    if [ -n "$disctotal" ]; then
        printf "/$disctotal"
    fi
    printf '\n'
}

# We need to get the total tracks for all discs to get a true total
get_album_track_total() {
    file_count=$(find "$1/" -not -name ._\* \( -iname \*.flac -o -iname \*mp3 -o -iname \*.m4a -o -iname \*.ogg -o -iname \*.dsf \) | wc -l)
    find "$1/" -not -name ._\* \( -iname \*.flac -o -iname \*mp3 -o -iname \*.m4a -o -iname \*.ogg -o -iname \*.dsf \) \
        | (
            total=0
            while read -r fn; do
                eval_common_metadata "$fn"

                track="$(get_tracknumber)"
                case "$track" in
                    */*)
                        tracknumber="${track%/*}"
                        tracktotal="${track##*/}"
                        ;;
                    *)
                        tracknumber="$track"
                        tracktotal=
                        ;;
                esac

                disc="$(get_discnumber)"
                case "$disc" in
                    */*)
                        discnumber="${disc%/*}"
                        disctotal="${disc##*/}"
                        ;;
                    *)
                        discnumber="$disc"
                        disctotal=1
                        ;;
                esac

                existing_total="$(eval "printf '%s' \"\${total$discnumber}\"")"
                if [ -z "$existing_total" ]; then
                    if [ -n "$tracktotal" ]; then
                        eval "total$discnumber=$tracktotal"
                        total=$((total + tracktotal))
                    else
                        return 0
                    fi
                fi
                if [ $total -ge $file_count ]; then
                    break
                fi
            done
            if [ $total -gt 0 ]; then
                echo "$total"
            fi
        )
}

get_genre() {
    if [ -n "$albumgenre" ]; then
        genre="$albumgenre"
    elif [ -z "$genre" ]; then
        # shellcheck disable=SC2016
        genre="$(exiftool -qm -AlbumGenre -p '$AlbumGenre' "$1" 2>/dev/null | xargs)"
        if [ -z "$genre" ]; then
            # shellcheck disable=SC2016
            genre="$(exiftool -qm -Genre -p '$Genre' "$1" 2>/dev/null | xargs)"
        fi
    fi

    # Sanitize / Improve consistency. Better plan: fix the tags
    case "$genre" in
        None|''|Miscellaneous|Other|Unclassifiable|hSH)
            genre=
            ;;
        Soundtracks)
            genre=Soundtrack
            ;;
        Videogame|Video\ Game*)
            genre=Game
            ;;
        Dance\ \&\ DJ)
            genre=Dance
            ;;
        Heavy\ Metal)
            genre=Metal
            ;;
        Holiday)
            genre=Christmas
            ;;
    esac
    if [ "$genre" != Game ]; then
        if echo "$releasetype" | tr ',' ' ' | grep -qwi soundtrack \
            || basename "$dir" | grep -qi soundtrack \
            || basename "$dir" | grep -qiw ost; then
            genre=Soundtrack
        fi
    fi
    if [ -z "$genre" ]; then
        genre=Unknown\ Genre
    fi
    echo "$genre"
}

