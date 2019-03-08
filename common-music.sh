# Commonly used metadata variables
tracknum_vars="track tracknumber tracktotal totaltracks"
discnum_vars="disc discnumber disctotal totaldiscs"
md_vars="$tracknum_vars $discnum_vars \
         artist album_artist title album compilation discsubtitle"

die() {
    ret="$1"
    shift
    fmt="$1"
    shift
    printf >&2 "Error: $fmt\n" "$@"
    exit $ret
}

fn_sanitize() {
    echo "$@" | tr -d '™ ' | sed -e 's/^\.//; s/ :/:/g; s/:$//' | unidecode | tr ':/' '∶／'
}

get_metadata() {
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
                    *\ $key\ *) ;;

                    *)
                        continue
                        ;;
                esac
            fi
            value="$(printf '%s\n' "$value" | sed -e 's/"/\\"/g; s/\\$//; s/`/\\`/g')"
            printf '%s="%s"\n' "$key" "$value"
        done
}

eval_metadata() {
    # Useful for debugging shell syntax errors when eval'ing the metadata
    # get_metadata "$@" | while read -r line; do
    #     ( eval "$line" ) >/dev/null 2>&1 || die 1 'Unable to eval `%s`' "$line"
    # done
    eval "$(get_metadata "$@")"
}

eval_common_metadata() {
    fn="$1"
    shift
    if [ $# -eq 0 ]; then
        set -- $md_vars
    fi
    eval_metadata "$fn" "$@"
}

get_new_filename() {
    separate_disc_folders=0
    OPTIND=0
    while getopts d opt; do
        case "$opt" in
            d)
                separate_disc_folders=1
                ;;
            *)
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    fn="$1"
    source_dir="$2"
    compilation=
    (
        eval_common_metadata "$1" \
            || {
                echo >&2 "Failed to eval metadata for $fn"
                return 1
            }

        if [ -z "$title" ]; then
            echo >&2 "Error: no title for $fn"
            return 1
        fi

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

        if [ -n "$album" ]; then
            albumdir="$album"
        else
            albumdir="[unknown]"
        fi

        fn_tracknumber="$tracknumber"
        if [ "$disctotal" != 1 ] \
            || ([ -n "$discnumber" ] && [ "$discnumber" -gt 1 ]); then
            if [ $separate_disc_folders -eq 0 ]; then
                if [ -n "$tracknumber" ]; then
                    fn_tracknumber="$discnumber-$tracknumber"
                else
                    fn_tracknumber="$discnumber-0"
                fi
            else
                if [ -n "$discsubtitle" ]; then
                    albumdir="$albumdir Disc $discnumber: $discsubtitle"
                else
                    albumdir="$albumdir Disc $discnumber"
                fi
            fi
        fi

        if [ -n "$fn_tracknumber" ]; then
            newfn="$fn_tracknumber - "
        else
            newfn=
        fi

        if echo "$releasetype" | tr '/,' '  ' | grep -qwi compilation \
            || ([ -n "$compilation" ] && [ "$compilation" = 1 ]) \
            || ([ -n "$album_artist" ] && echo "$album_artist" | grep -qi '^various'); then
            newfn="$newfn$artist - "
            compilation=1
        fi

        newfn="$newfn$title.${fn##*.}"

        if [ -n "$compilation" ] && [ "$compilation" -eq 1 ]; then
            artistdir=Compilations
        elif [ -n "$album_artist" ]; then
            artistdir="$album_artist"
        elif [ -n "$artist" ]; then
            artistdir="$artist"
        else
            artistdir="[unknown]"
        fi
        artistdir="$(fn_sanitize "$artistdir")"
        albumdir="$(fn_sanitize "$albumdir" | sed -e 's/^The \(.*\)/\1, The/')"
        destdir="$artistdir/$albumdir"
        newfn="$(fn_sanitize "$newfn")"
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
get_album_track_total_indiv_discs() {
    first_track="$(music_find "$1" | head -n 1)"
    (
        eval_common_metadata "$1" $tracknum_vars

        track="$(get_tracknumber)"
        case "$track" in
            */*)
                tracktotal="${track##*/}"
                ;;
            *)
                tracktotal=
                ;;
        esac
        if [ -n "$tracktotal" ]; then
            echo "$tracktotal"
        else
            return 1
        fi
    )
}

music_find() {
    finddir="$1"
    shift
    find -H "$finddir" -type f -not -name ._\* \( -iname \*.flac -o -iname \*mp3 -o -iname \*.m4a -o -iname \*.ogg -o -iname \*.dsf \) "$@"
}

nonmusic_find() {
    finddir="$1"
    shift
    find -H "$finddir" -type f -not \( -name ._\* -o -iname \*.flac -o -iname \*mp3 -o -iname \*.m4a -o -iname \*.ogg -o -iname \*.dsf \) "$@"
}

# We need to get the total tracks for all discs to get a true total
get_album_track_total() {
    file_count="$(music_find "$1" | wc -l)"
    music_find "$1" \
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
    lower_genre="$(echo "$genre" | tr '[:upper:]' '[:lower:]')"
    case "$lower_genre" in
        none | '' | miscellaneous | other | unclassifiable | hsh)
            genre=
            ;;
        soundtracks)
            genre=Soundtrack
            ;;
        videogame | video\ game* | vgm | game*)
            genre=Game
            ;;
        dance\ \&\ dj)
            genre=Dance
            ;;
        heavy\ metal)
            genre=Metal
            ;;
        holiday)
            genre=Christmas
            ;;
    esac
    base="$(basename "$(dirname "$1")")"
    if [ "$genre" != Game ] \
        && ([ -z "$2" ] || ! echo "$base" | grep -qEx "$2"); then
        if echo "$releasetype" | tr '/,' '  ' | grep -qwi soundtrack \
            || echo "$base" | grep -qi soundtrack \
            || echo "$base" | grep -qiw ost; then
            genre=Soundtrack
        fi
    fi
    if [ -z "$genre" ]; then
        genre=Unknown\ Genre
    fi
    echo "$genre"
}
