# Commonly used metadata variables
tracknum_vars="track tracknumber tracktotal totaltracks"
discnum_vars="disc discnumber disctotal totaldiscs"
md_vars="$tracknum_vars $discnum_vars \
         genre albumgenre \
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

    case "$fn" in
        *.ogg)
            get_metadata_exif "$fn" "$@"
            return $?
            ;;
    esac

    pat="$(echo "$@" | sed -e 's/  */ /g')"
    ffprobe -v quiet -of flat=s=_ -show_entries format_tags "$fn" \
        | cut -d_ -f3- \
        | while IFS="=" read -r key value; do
            key="$(printf '%s\n' "$key" | tr "[:upper:]" "[:lower:]")"
            if [ -n "$pat" ]; then
                case " $pat " in
                    *\ $key\ *) ;;

                    *)
                        continue
                        ;;
                esac
            fi
            printf '%s=%s\n' "$key" "$value"
        done
}

get_metadata_exif() {
    fn="$1"
    shift
    pat="$(echo "$@" | sed -e 's/  */ /g')"
    exiftool -S "$fn" \
        | sed -e 's/: /=/' \
        | while IFS="=" read -r key value; do
            if [ -z "$key" ]; then
                continue
            fi
            case "$key" in
                *\ *)
                    key="$(echo "$key" | tr -d " ")"
                    ;;
                Albumartist)
                    key="Album_Artist"
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
    fn="$1"
    shift
    eval "$(get_metadata "$fn" "$@")"
    if [ -z "$title" ] && [ -z "$track" ] && [ -z "$tracknumber" ]; then
        eval "$(get_metadata_exif "$@")"
    fi
}

eval_common_metadata() {
    fn="$1"
    shift
    if [ $# -eq 0 ]; then
        set -- $md_vars
    fi
    unset "$@"
    eval_metadata "$fn" "$@"
}

get_new_filename() {
    if [ "$1" = "-d" ]; then
        separate_disc_folders=1
        shift
    else
        separate_disc_folders=0
    fi

    fn="$1"
    source_dir="$2"
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
        if [ -z "$discsubtitle" ]; then
            discsubtitle="$setsubtitle"
        fi
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

    if echo "$releasetype" | tr '/,;' '   ' | grep -qwi compilation \
        || ([ -n "$compilation" ] && [ "$compilation" = 1 ]) \
        || ([ -n "$album_artist" ] && echo "$album_artist" | grep -qi '^various'); then
        newfn="$newfn$artist - "
        compilation=1
    fi

    if [ -z "$title" ]; then
        if [ -n "$tracknumber" ]; then
            title="Track $tracknumber"
        else
            title=Unknown
        fi
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
    track="$(get_tracknumber || :)"
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

preparebar() {
# $1 - bar length
# $2 - bar char
    barlen=$1
    barspaces=$(printf "%*s" "$1")
    barchars=$(printf "%*s" "$1" | tr ' ' "${2:-▇}")
}

clearlen="$(tput cols)"
clearspaces=$(printf "%*s" "$clearlen")
clearbar() {
    printf "\r$clearspaces\r"
}

progressbar() {
# $1 - number (-1 for clearing the bar)
# $2 - max number
    if [ $1 -eq -1 ]; then
        printf "\r  $barspaces\r"
    else
        barch=$(($1*barlen/$2))
        barsp=$((barlen-barch))
        printf "\r%s[%.${barch}s%.${barsp}s]%s\r" "${3:+$3 }" "$barchars" "$barspaces" "${4:+ $4}"
    fi
}

