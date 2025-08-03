#!/bin/bash

# COLORES 
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
whiteColor="\e[0;37m\033[1m"
yellowColour="\e[0;33m\033[1m"

cookie=/tmp/cookies_tw.txt
r_default=720p
hilos_default=100 
 
base=$(basename $0)
output="$base.json"
file_m3u8="$base.m3u8"

# Lista de comandos requeridos
DEPENDENCIAS=(jq ffmpeg xargs)

for cmd in "${DEPENDENCIAS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${yellowColour}[-] La herramienta '$cmd' no está instalada. Por favor instalala antes de continuar.${endColour}"
        exit 1
    fi
done

trap ctrl_c INT

ctrl_c() {
	echo -e "${yellowColour}[!] Saliendo...${endColour}"
    exit 1
}

modo_uso() {
    echo -e "${yellowColour}Modo de uso:  $(basename $0) [OPCIONES] ${endColour}"
    echo  "Ejemplo 1: $0 -c 123456788 -r 1080 -w 200"
    echo  "Ejemplo 2: $0 -l staryuuki"
    echo -e "\nOPCIONES:"
    echo -e " -c 1234567890 \t Codigo identificador del video. Ej 1234567890"
    echo -e " -r 1080 \t Resolucion del video: 1080 (1920x1080), 720 (1280x720), 480 (852x480) ,360 (640x360), 160 (284x160)."
    echo -e " -w 50 \t\t Numero de workers para descargar en paralelo. Por defecto 200"
    echo -e " -l userId \t Listar todos los videos del usuario/canal"
    echo -e " -h \t\t Muestra esta ayuda y termina\n"
    exit 0
}

procesar() {
    vodID=$OPTARG_C
    r_default=$([[ $OPTARG_R -ne "" ]] && echo $OPTARG_R"p"  || echo $r_default )
    if [[ $OPTARG_R -eq "1080"  ]] ; then r_default=chunked ; fi 
    hilos=$([[ $OPTARG_W -ne "" ]] && echo $OPTARG_W || echo $hilos_default )

    folder_parts=$vodID"_$r_default/parts/"
    mkdir -p $folder_parts
        
    folder_data=$vodID"_"$r_default"/data/"
    mkdir -p $folder_data
  
    url="https://player.twitch.tv/?autoplay=true&parent=meta.tag&player=facebook&video=$vodID"

    curl -s -X GET  "$url"  -c $cookie  -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:108.0) Gecko/20100101 Firefox/108.0' >/dev/null
    device_id=$(grep -i "unique_id_durable" "$cookie" | awk '{print $NF}')

    payload=$(jq -n --arg vodID "$vodID" '{
        operationName: "PlaybackAccessToken_Template",
        query: "query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!, $platform: String!) { streamPlaybackAccessToken(channelName: $login, params: {platform: $platform, playerBackend: \"mediaplayer\", playerType: $playerType}) @include(if: $isLive) { value signature authorization { isForbidden forbiddenReasonCode } __typename } videoPlaybackAccessToken(id: $vodID, params: {platform: $platform, playerBackend: \"mediaplayer\", playerType: $playerType}) @include(if: $isVod) { value signature __typename }}",
        variables: {
            isLive: false,
            login: "",
            isVod: true,
            vodID: $vodID,
            playerType: "site",
            platform: "web"
        }
    }')

    curl -s 'https://gql.twitch.tv/gql' \
        -H 'authorization: undefined' \
        -H 'client-id: kimne78kx3ncx6brgo4mv6wki5h1ko' \
        -H 'device-id: '$device_id \
        -H 'content-type: application/json' \
        -H 'origin: https://player.twitch.tv' \
        -H 'referer: https://player.twitch.tv/' \
        -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36' \
        --data-raw "$payload" > "$folder_data$output"

    if ! jq empty "$folder_data$output" 2>/dev/null; then
        echo -e "${yellowColour}[-] JSON no válido. Abortando.${endColour}"
        exit 1
    fi

    signature=$(jq -r '.data.videoPlaybackAccessToken.signature' "$folder_data$output")
    expires=$(jq -r '.data.videoPlaybackAccessToken.value' "$folder_data$output" | jq -r '.expires')

    if [[ -z "$signature" ]]; then
        echo -e "${yellowColour}[-] No se pudo obtener un signature válido. Abortando.${endColour}"
        exit 1
    fi

    curl -s 'https://usher.ttvnw.net/vod/'$vodID'.m3u8?acmb=&allow_source=true&browser_family=chrome&browser_version=136.0&cdm=wv&enable_score=true&include_unavailable=true&os_name=Linux&os_version=undefined&p=2366355&platform=web&player_backend=mediaplayer&player_version=1.42.0-rc.1&playlist_include_framerate=true&reassignments_supported=true&sig='$signature'&supported_codecs=av1,h264&token=%7B%22authorization%22%3A%7B%22forbidden%22%3Afalse%2C%22reason%22%3A%22%22%7D%2C%22chansub%22%3A%7B%22restricted_bitrates%22%3A%5B%5D%7D%2C%22device_id%22%3A%22'$device_id'%22%2C%22expires%22%3A'$expires'%2C%22https_required%22%3Atrue%2C%22privileged%22%3Afalse%2C%22user_id%22%3Anull%2C%22version%22%3A3%2C%22vod_id%22%3A'$vodID'%2C%22maximum_resolution%22%3A%22FULL_HD%22%2C%22maximum_video_bitrate_kbps%22%3A12500%2C%22maximum_resolution_reasons%22%3A%7B%22QUAD_HD%22%3A%5B%22AUTHZ_NOT_LOGGED_IN%22%5D%2C%22ULTRA_HD%22%3A%5B%22AUTHZ_NOT_LOGGED_IN%22%5D%7D%2C%22maximum_video_bitrate_kbps_reasons%22%3A%5B%22AUTHZ_DISALLOWED_BITRATE%22%5D%7D&transcode_mode=cbr_v1' \
        -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36' \
        -H 'Accept: application/x-mpegURL, application/vnd.apple.mpegurl, application/json, text/plain' \
        -H 'Referer;' > "$folder_data$file_m3u8"

    url_file=$(grep http "$folder_data$file_m3u8" | grep "$r_default" | head -1)

    if [[ -z "$url_file" ]]; then
        echo -e "${yellowColour}[-] No se encontró una URL válida. Saliendo...${endColour}"
        exit 1
    fi

    curl -s -X GET "$url_file" > "$folder_data$base.$r_default.m3u8"

    last_part=$(echo "$url_file" | awk '{print $NF}' FS='/')
    url_video=$(echo "$url_file" | awk -F $last_part '{print $1}')
    
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Descargado todas las de partes de video ${endColour}"
    
    ts_list=$(grep "\.ts" "$folder_data$base.$r_default.m3u8")
    [ -z "$ts_list" ] && ts_list=$(grep "\.ts" "$folder_data$file_m3u8")

    # CONTAR CANTIDAD DE ARCHIVOS TS 
    total_parts=$(echo "$ts_list" | wc -l)
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Total de partes a descargar: $total_parts ${endColour}"

    # DESCARGANDO EN PARALELO CON XARGS Y WGET (wget ya que me permite reconectar la parte descargada)
    max_retries=4
    fail_log=$(mktemp)

    echo "$ts_list" | nl | xargs -P "$hilos" -I {} bash -c '
        line=($0)
        num=$(printf "%04d" "${line[0]}")
        part=${line[1]}
        part_path="'"$folder_parts"'$part.mp4"

        echo "[#$num/'$total_parts'] ⏳ Descargando $part" >&2

        for attempt in $(seq 1 '"$max_retries"'); do
            wget --tries=1 \
                --no-check-certificate \
                --retry-connrefused \
                --wait=1 \
                --quiet \
                --continue \
                "'"$url_video"'$part" \
                --output-document="$part_path"

            if [[ -s "$part_path" ]]; then
                echo "[#$num/'$total_parts'] ✅ Completado $part" >&2
                break
            else
                echo "[#$num/'$total_parts'] ❌ Falló intento $attempt para $part" >&2
                sleep 1
            fi
        done

        if [[ ! -s "$part_path" ]]; then
            echo "$part" >> "'"$fail_log"'"
        fi
    ' {}

    wait

    # Reintentar archivos fallidos
    if [[ -s "$fail_log" ]]; then
        echo "🔁 Reintentando fragmentos fallidos:" >&2
        while read part; do
            echo "↩️ Reintentando $part..." >&2
            wget --tries=4 \
                --no-check-certificate \
                --retry-connrefused \
                --wait=2 \
                --quiet \
                --continue \
                "$url_video$part" \
                --output-document="$folder_parts$part.mp4"

            if [[ -s "$folder_parts$part.mp4" ]]; then
                echo "✅ Reintento exitoso: $part" >&2
            else
                echo "❌ Aún fallido tras reintentos: $part" >&2
            fi
        done < "$fail_log" 
    fi

    rm -f "$fail_log"
    
    # GENERANDO LISTADO DE TS DESCARGADOS
    filesMP4=$vodID"_"$r_default"/files.txt" 
    echo "$ts_list" | xargs -I {} echo "file 'parts/{}.mp4'" >> $filesMP4

    # UNIENDO VIDEOS
    logInfo=$folder_data"ffmpeg.log"
    time=$(date +%H%M%S)
    video=$vodID"_"$r_default"/"$vodID"_"$r_default"_"$time".mp4"

    echo -e   "${yellowColour}[+]${endColour}${whiteColor} Uniendo partes con ffmpeg.${endColour}"

    ffmpeg -safe 0  -f concat -i $filesMP4  -bsf:a aac_adtstoasc  -vcodec copy $video >$logInfo 2>&1 

    if [[ $? -ne 0 ]]; then
        echo -e "${yellowColour}[-] Error al unir video. Verifica el log: $logInfo${endColour}"
        exit 1
    fi

    echo  -e  "${yellowColour}[+]${endColour}${whiteColor} Proceso terminado. ${endColour}"
    echo  -e  "${yellowColour}[+]${endColour}${whiteColor} Video: $video ${endColour}"

    rm -fr "$filesMP4" 2>/dev/null
    rm -fr "$folder_data$base.$r_default.m3u8"
    rm -fr "$folder_data$output"
    rm -fr "$folder_data$file_m3u8"
    rm -fr "$folder_parts"

    exit 0

}

listar_videos() {
    channelOwnerLogin=$OPTARG_L
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Listado de videos de $channelOwnerLogin ${endColour}"
    cookie=/tmp/cookies_tw.txt

    curl -s -c $cookie -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'  "https://www.twitch.tv/$channelOwnerLogin/about" >/dev/null 2>&1
    unique_id_durable=$(grep -i "unique_id_durable" "$cookie" | awk '{print $NF}')

    if [[ -z "$unique_id_durable" ]]; then
        echo -e "${yellowColour}[-] No se encontró un id válido. Saliendo.${endColour}"
        exit 1
    fi

    YEAR=$(date +%Y)

    for MONTH in {1..12}; do
        output=$channelOwnerLogin.$MONTH.json
        MONTH_PADDED=$(printf "%02d" $MONTH)
        START_AT="${YEAR}-${MONTH_PADDED}-01T00:00:00.000Z"
        LAST_DAY=$(date -d "${YEAR}-${MONTH_PADDED}-01 +1 month -1 day" +%d)
        END_AT="${YEAR}-${MONTH_PADDED}-${LAST_DAY}T23:59:59.059Z"
        
        payload=$(jq -n \
            --arg channelOwnerLogin "$channelOwnerLogin" \
            --arg startAt "$START_AT" \
            --arg endAt "$END_AT" \
            '[{
                "operationName": "StreamSchedule",
                "variables": {
                    "login": $channelOwnerLogin,
                    "startingWeekday": "MONDAY",
                    "startAt": $startAt,
                    "endAt": $endAt
                },
                "extensions": {
                    "persistedQuery": {
                        "version": 1,
                        "sha256Hash": "83552f5614707fd3e897495c18875b6fa9c83d8cf11e73b9f158f3173b4f3b75"
                    }
                }
            }
        ]')

        curl -s 'https://gql.twitch.tv/gql' \
            -H 'client-id: kimne78kx3ncx6brgo4mv6wki5h1ko' \
            -H 'origin: https://www.twitch.tv' \
            -H 'referer: https://www.twitch.tv/' \
            -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36' \
            -H 'x-device-id: '$unique_id_durable \
            --data-raw  "$payload" > $output

        cat "$output" | jq -r '.[].data.user.videos.edges[].node | "🆔 ID: \(.id)\n🎥 Título: \(.title)\n👁️  Vistas: \(.viewCount)\n🕒 Duración: \(.lengthSeconds) segundos\n📅 Fecha: \(.createdAt)\n---------"'

        rm -fr $channelOwnerLogin*.json

        sleep 1

    done

    exit 0 
}


[[ $# -eq 0 ]] && modo_uso

VARIABLE_C=0
VARIABLE_L=0

while getopts ":c:r:w:l:h" opt; do
    case $opt in
        c) VARIABLE_C=1; OPTARG_C="$OPTARG" ;;  # Código de video
        r) OPTARG_R="$OPTARG" ;;                # Resolución
        w) OPTARG_W="$OPTARG" ;;                # Workers
        l) VARIABLE_L=1; OPTARG_L="$OPTARG" ;;  # Listar videos
        h) modo_uso ;;
        \?) echo -e "${yellowColour}[-]${endColour} Opción no válida: -$OPTARG"; exit 1 ;;
        :)  echo -e "${yellowColour}[!]${endColour} La opción -$OPTARG requiere un argumento"; exit 1 ;;
    esac
done

shift $((OPTIND-1))

# -l staryuuki  
if [[ $VARIABLE_L -eq 1 ]]  ; then
    listar_videos "$OPTARG_L"
    exit 0
fi

# -c 123456780  
if [[ $VARIABLE_C -ne 1 ]]  ; then
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Se necesita un codigo de video para continuar ${endColour}"
    modo_uso
fi

procesar "$OPTARG_C" "$OPTARG_R" "$OPTARG_W"

